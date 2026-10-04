import SwiftUI
import AppKit
import Carbon
import ApplicationServices
import AVFoundation

// Carbon hot keys work across apps without observing every keystroke.
final class SelectionTranslation: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = SelectionTranslation()
    @Published var shortcutChoice = UserDefaults.standard.integer(forKey: "SelectionShortcutChoice") {
        didSet {
            UserDefaults.standard.set(shortcutChoice, forKey: "SelectionShortcutChoice")
            registerShortcuts()
        }
    }
    @Published var showSelectionButton = UserDefaults.standard.bool(forKey: "ShowSelectionButton") {
        didSet {
            UserDefaults.standard.set(showSelectionButton, forKey: "ShowSelectionButton")
            configureSelectionButton()
        }
    }
    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()
    @Published private(set) var selectionStatus = "Select text in another app to show the button."
    private let selectionQueue = DispatchQueue(label: "SwifTL.selection", qos: .userInitiated)
    private var detectionGeneration = UUID()
    @Published var shortcutError: String?
    @Published var isPinned = false
    @Published var isSpeaking = false
    @Published var notice: String?
    private var panel: SelectionPanel?
    private var indicator: SelectionPanel?
    private var selectionMonitor: Any?
    private var indicatorLocalMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var selectionWork: DispatchWorkItem?
    private var detectedText: String?
    private var detectedAnchor: NSRect?
    private var hotKeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var captureInProgress = false
    private var model: TranslatorViewModel?
    private let speech = AVSpeechSynthesizer()
    private var activeUtterance: AVSpeechUtterance?
    var appDelegate: AppDelegate?

    static let shortcutLabels = ["⌥⇧T", "⌃⌥T", "⌘⇧Y"]
    var shortcutLabel: String { Self.shortcutLabels.indices.contains(shortcutChoice) ? Self.shortcutLabels[shortcutChoice] : Self.shortcutLabels[0] }

    func start(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        speech.delegate = self
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event = event, let context = context else { return OSStatus(eventNotHandledErr) }
            var key = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
            guard result == noErr else { return result }
            let owner = Unmanaged<SelectionTranslation>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                if key.id == 1 { owner.translateSelection() }
                if key.id == 2 { owner.translateClipboard() }
            }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else {
            shortcutError = "Could not register global shortcuts. Use the Services menu instead."
            return
        }
        registerShortcuts()
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        configureSelectionButton()
    }

    func registerShortcuts() {
        guard handler != nil else { return }
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        let choices: [(UInt32, UInt32)] = [
            (UInt32(kVK_ANSI_T), UInt32(optionKey | shiftKey)),
            (UInt32(kVK_ANSI_T), UInt32(controlKey | optionKey)),
            (UInt32(kVK_ANSI_Y), UInt32(cmdKey | shiftKey))
        ]
        let choice = choices.indices.contains(shortcutChoice) ? choices[shortcutChoice] : choices[0]
        var failures = false
        for (id, combination) in [(UInt32(1), choice), (UInt32(2), (UInt32(kVK_ANSI_T), UInt32(cmdKey | optionKey | shiftKey)))] {
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(combination.0, combination.1, EventHotKeyID(signature: 0x5377544C, id: id), GetApplicationEventTarget(), 0, &reference)
            if status == noErr, let reference = reference { hotKeys.append(reference) } else { failures = true }
        }
        shortcutError = failures ? "A shortcut is unavailable. Choose another combination or use Services." : nil
    }

    private func configureSelectionButton() {
        hideSelectionButton()
        if let monitor = selectionMonitor { NSEvent.removeMonitor(monitor); selectionMonitor = nil }
        if let monitor = indicatorLocalMonitor { NSEvent.removeMonitor(monitor); indicatorLocalMonitor = nil }
        if let observer = activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer); activationObserver = nil }
        guard showSelectionButton, appDelegate != nil else { return }
        selectionMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .keyDown]) { [weak self] event in
            guard let self = self else { return }
            self.hideSelectionButton()
            guard event.type == .leftMouseUp, self.panel?.isVisible != true,
                  let target = NSWorkspace.shared.frontmostApplication,
                  target.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self.refreshAccessibility()
            guard self.accessibilityGranted else {
                self.selectionStatus = "Accessibility is not enabled for this running copy of SwifTL."
                return
            }
            let work = DispatchWorkItem { [weak self] in
                guard let self = self, self.showSelectionButton,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else { return }
                self.detectSelection(in: target)
            }
            self.selectionWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
        indicatorLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self] event in
            if event.window !== self?.indicator { self?.hideSelectionButton() }
            return event
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.hideSelectionButton()
        }
    }

    func refreshAccessibility() { accessibilityGranted = AXIsProcessTrusted() }

    private func readSelection(in target: NSRunningApplication, completion: @escaping (SelectedTextResult?, Bool) -> Void) {
        let point = NSEvent.mouseLocation
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let browser = target.bundleIdentifier?.hasPrefix("com.google.Chrome") == true
            || target.bundleIdentifier == "com.microsoft.edgemac"
            || target.bundleIdentifier == "com.brave.Browser"
        selectionQueue.async {
            let reader = SelectedTextReader()
            let result = reader.read(processID: target.processIdentifier, browser: browser, mouse: CGPoint(x: point.x, y: top - point.y))
            let secure = reader.encounteredSecureField
            if result == nil, !secure, browser {
                self.selectionQueue.asyncAfter(deadline: .now() + 0.2) {
                    let retry = SelectedTextReader()
                    let result = retry.read(processID: target.processIdentifier, browser: browser, mouse: CGPoint(x: point.x, y: top - point.y))
                    let secure = retry.encounteredSecureField
                    DispatchQueue.main.async { completion(result, secure) }
                }
            } else {
                DispatchQueue.main.async { completion(result, secure) }
            }
        }
    }

    private func detectSelection(in target: NSRunningApplication) {
        let generation = detectionGeneration
        readSelection(in: target) { [weak self] result, secure in
            guard let self = self, self.showSelectionButton, self.detectionGeneration == generation,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else { return }
            guard !secure else { self.selectionStatus = "Password fields are skipped."; return }
            guard let result = result else {
                self.selectionStatus = "Could not read selected text from \(target.localizedName ?? "this app"). Try the selection shortcut or copy text."
                return
            }
            self.selectionStatus = "Selected text found in \(target.localizedName ?? "this app")."
            self.detectedText = result.text
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            self.detectedAnchor = result.bounds.map { NSRect(x: $0.minX, y: top - $0.maxY, width: $0.width, height: $0.height) }
            self.showDetectedButton()
        }
    }

    private func showDetectedButton() {
        if indicator == nil {
            let window = SelectionPanel(contentRect: NSRect(x: 0, y: 0, width: 36, height: 32), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.level = .floating
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = NSHostingView(rootView:
                Button { [weak self] in self?.translateDetectedSelection() } label: {
                    Image(systemName: "character.bubble").frame(width: 36, height: 32)
                }.buttonStyle(.plain).background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 7)).help("Translate selection")
                    .accessibilityLabel("Translate selection")
            )
            indicator = window
        }
        let point = NSEvent.mouseLocation
        if let frame = NSScreen.screens.first(where: { $0.frame.contains(point) })?.visibleFrame {
            indicator?.setFrameOrigin(NSPoint(x: min(max(point.x + 10, frame.minX), frame.maxX - 36), y: min(max(point.y - 40, frame.minY), frame.maxY - 32)))
        }
        indicator?.orderFrontRegardless()
    }

    private func hideSelectionButton() {
        detectionGeneration = UUID()
        selectionWork?.cancel()
        selectionWork = nil
        indicator?.orderOut(nil)
        detectedText = nil
        detectedAnchor = nil
    }

    private func translateDetectedSelection() {
        let text = detectedText
        let anchor = detectedAnchor
        hideSelectionButton()
        guard let text = text else { return }
        show(text: text, anchor: anchor)
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func translateSelection() {
        guard !captureInProgress else { return }
        guard AXIsProcessTrusted() else {
            show(text: nil, error: "Enable SwifTL in System Settings → Privacy & Security → Accessibility. Or copy text and press ⌘⌥⇧T.")
            return
        }
        let target = NSWorkspace.shared.frontmostApplication
        guard let target = target else { return }
        captureInProgress = true
        readSelection(in: target) { [weak self] result, secure in
            guard let self = self else { return }
            self.captureInProgress = false
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else { return }
            if secure {
                self.show(text: nil, error: "Password fields cannot be translated.")
            } else if let result = result {
                let top = NSScreen.screens.first?.frame.maxY ?? 0
                let anchor = result.bounds.map { NSRect(x: $0.minX, y: top - $0.maxY, width: $0.width, height: $0.height) }
                self.show(text: result.text, anchor: anchor)
            } else if target.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                self.show(text: nil, error: "Select text in another app and press \(self.shortcutLabel), or copy it and press ⌘⌥⇧T.")
            } else {
                self.copySelection(from: target)
            }
        }
    }

    private func copySelection(from target: NSRunningApplication) {
        let pasteboard = NSPasteboard.general
        // Snapshot every representation, including images and rich text.
        let snapshot = pasteboard.pasteboardItems?.map { item in
            item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
        } ?? []
        let initialCount = pasteboard.changeCount
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier,
              let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false) else { return }
        captureInProgress = true
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        let deadline = Date().addingTimeInterval(0.8)
        func poll() {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
                captureInProgress = false
                return
            }
            if pasteboard.changeCount != initialCount {
                let copiedCount = pasteboard.changeCount
                let text = pasteboard.string(forType: .string)
                // Restore only the copy we observed; never overwrite a later clipboard update.
                if pasteboard.changeCount == copiedCount {
                    pasteboard.clearContents()
                    let items = snapshot.map { representations -> NSPasteboardItem in
                        let item = NSPasteboardItem()
                        representations.forEach { item.setData($0.1, forType: $0.0) }
                        return item
                    }
                    if !items.isEmpty { pasteboard.writeObjects(items) }
                }
                captureInProgress = false
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else { return }
                show(text: text, error: text == nil ? "Could not copy selected text. Copy it manually, then press ⌘⌥⇧T." : nil)
            } else if Date() >= deadline {
                captureInProgress = false
                show(text: nil, error: "No selected text was found. Copy text manually, then press ⌘⌥⇧T, or use Screenshot.")
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { poll() }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { poll() }
    }

    func translateClipboard() {
        show(text: NSPasteboard.general.string(forType: .string), error: "Copy text first, then press ⌘⌥⇧T.")
    }

    @objc func translateSelectedText(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        show(text: pasteboard.string(forType: .string), error: "No text was provided by this app.")
    }

    private func show(text: String?, error: String? = nil, anchor: NSRect? = nil) {
        guard let appDelegate = appDelegate else { return }
        hideSelectionButton()
        stopSpeaking()
        notice = nil
        isPinned = false
        let quick = appDelegate.viewModel.makeQuickTranslationModel()
        model = quick
        quick.inputText = text ?? ""
        if let text = text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !quick.automaticLanguage && quick.sourceLanguage == quick.targetLanguage {
                quick.errorMessage = "Choose different source and target languages in the main window."
            } else { quick.translateInput() }
        } else { quick.errorMessage = error ?? "Select text to translate." }
        if panel == nil {
            let window = SelectionPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 480), styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
            window.title = "Quick Translation"
            window.level = .floating
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.onClose = { [weak self] in self?.stopSpeaking(); self?.removeMonitors() }
            panel = window
        }
        guard let panel = panel else { return }
        panel.contentView = NSHostingView(rootView: SelectionResultView(model: quick, coordinator: self))
        let mouse = NSEvent.mouseLocation
        let reference = anchor ?? NSRect(origin: mouse, size: .zero)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(reference.origin) }) ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let size = panel.frame.size
            var y = reference.minY - size.height - 8
            if y < frame.minY { y = reference.maxY + 8 }
            panel.setFrameOrigin(NSPoint(x: min(max(reference.midX - size.width / 2, frame.minX), frame.maxX - size.width), y: min(max(y, frame.minY), frame.maxY - size.height)))
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless() // Keep the source app and its selection active.
        }
        // Let the opening mouse event finish before observing outside clicks.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self, weak quick] in
            guard let self = self, let quick = quick, self.model === quick, self.panel?.isVisible == true else { return }
            self.installMonitors()
        }
    }

    private func installMonitors() {
        removeMonitors()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            guard let self = self else { return }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.dismiss() }
            } else if !self.isPinned { self.dismiss() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            guard let self = self, let panel = self.panel, panel.isVisible else { return event }
            if event.type == .keyDown, event.keyCode == 53 { self.dismiss(); return nil }
            if event.type != .keyDown, event.window !== panel, !self.isPinned { self.dismiss() }
            return event
        }
    }
    private func removeMonitors() {
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor); globalMonitor = nil }
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor); localMonitor = nil }
    }
    func dismiss() {
        panel?.orderOut(nil)
        stopSpeaking()
        removeMonitors()
    }
    func openInMainWindow() {
        guard let model = model, let main = appDelegate?.viewModel else { return }
        guard !main.isTranslating, !main.isSelectingArea else { notice = "Wait for the main window’s translation to finish."; return }
        main.adoptResult(from: model)
        dismiss()
        appDelegate?.showMainWindow()
    }
    func speak(_ text: String, language: String) {
        if isSpeaking { stopSpeaking(); return }
        let utterance = AVSpeechUtterance(string: text)
        let locale = ["zh-Hans": "zh-CN", "zh-Hant": "zh-TW" ][language] ?? language
        utterance.voice = AVSpeechSynthesisVoice(language: locale)
        activeUtterance = utterance
        isSpeaking = true
        speech.speak(utterance)
    }
    func stopSpeaking() { activeUtterance = nil; speech.stopSpeaking(at: .immediate); isSpeaking = false }
    private func finishSpeaking(_ utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.activeUtterance === utterance else { return }
            self.activeUtterance = nil
            self.isSpeaking = false
        }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { finishSpeaking(utterance) }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { finishSpeaking(utterance) }
}

final class SelectionPanel: NSPanel {
    var onClose: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func close() { onClose?(); super.close() }
}

struct SelectionResultView: View {
    @ObservedObject var model: TranslatorViewModel
    @ObservedObject var coordinator: SelectionTranslation
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Quick Translation").font(.caption).foregroundColor(.secondary)
                Spacer()
                Button { coordinator.isPinned.toggle() } label: {
                    Image(systemName: coordinator.isPinned ? "pin.fill" : "pin")
                }.help(coordinator.isPinned ? "Unpin" : "Keep open").accessibilityLabel(coordinator.isPinned ? "Unpin" : "Pin translation")
            }
            TranslationResultView(model: model)
            if model.errorMessage != nil && !model.inputText.isEmpty {
                Button("Retry") { model.translateInput() }.disabled(model.isTranslating)
            }
            if !AXIsProcessTrusted(), model.errorMessage != nil {
                Button("Enable Accessibility…") { coordinator.requestAccessibility() }
            }
            if let notice = coordinator.notice { Text(notice).font(.caption).foregroundColor(.red) }
            HStack {
                Button(copied ? "Copied!" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.translatedText, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }.disabled(model.translatedText.isEmpty)
                Button(coordinator.isSpeaking ? "Stop" : "Read aloud") { coordinator.speak(model.translatedText, language: model.result?.target.code ?? model.targetLanguage.code) }.disabled(model.translatedText.isEmpty)
                Spacer()
            }
            HStack {
                Button("Open in main window") { coordinator.openInMainWindow() }.disabled(model.isTranslating || model.inputText.isEmpty)
                Spacer()
                Button("Close") { coordinator.dismiss() }
            }
        }.padding(14).frame(width: 400, height: 480)
    }
}
