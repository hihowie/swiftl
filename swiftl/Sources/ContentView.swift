import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var viewModel: TranslatorViewModel
    @FocusState private var inputFocused: Bool
    @State private var showingSettings = false
    @State private var showCopyFeedback = false

    private var isBusy: Bool { viewModel.isTranslating || viewModel.isSelectingArea }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SwifTL").font(.title2.weight(.semibold))
                Spacer()
                Button { SelectionTranslation.shared.translateClipboard() } label: {
                    Image(systemName: "clipboard")
                }
                .help("Translate clipboard (⌘⌥⇧T)")
                .accessibilityLabel("Translate clipboard")
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
                .disabled(isBusy)
            }
            HStack(alignment: .languageControlCenter, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("From").font(.caption).foregroundColor(.secondary)
                    Picker("Source language", selection: $viewModel.sourceLanguage) {
                        ForEach(viewModel.availableLanguages, id: \.code) { language in
                            Text(language.name).tag(language)
                        }
                    }
                    .labelsHidden()
                    .alignmentGuide(.languageControlCenter) { $0[VerticalAlignment.center] }
                }
                Button { viewModel.swapLanguages() } label: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .buttonStyle(.borderless)
                .alignmentGuide(.languageControlCenter) { $0[VerticalAlignment.center] }
                .help("Swap languages")
                .accessibilityLabel("Swap languages")
                VStack(alignment: .leading, spacing: 4) {
                    Text("To").font(.caption).foregroundColor(.secondary)
                    Picker("Target language", selection: $viewModel.targetLanguage) {
                        ForEach(viewModel.availableLanguages, id: \.code) { language in
                            Text(language.name).tag(language)
                        }
                    }
                    .labelsHidden()
                    .alignmentGuide(.languageControlCenter) { $0[VerticalAlignment.center] }
                }
            }
            .disabled(isBusy)
            Text("Original text").font(.headline)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.inputText)
                    .font(.body)
                    .tint(.primary)
                    .scrollContentBackground(.hidden)
                    .padding(5)
                    .accessibilityLabel("Text to translate")
                    .focused($inputFocused)
                if viewModel.inputText.isEmpty {
                    Text("Type or paste text to translate…")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10).padding(.top, 5)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 140)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.25))
                    .allowsHitTesting(false)
            )
            HStack {
                Button("Translate") { viewModel.translateInput() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy || viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.sourceLanguage == viewModel.targetLanguage)
                Button("Clear") { viewModel.clearInput() }
                    .disabled(isBusy || (viewModel.inputText.isEmpty && viewModel.translatedText.isEmpty && viewModel.errorMessage == nil))
                Spacer()
                Button { viewModel.startAreaSelection() } label: {
                    Label("Screenshot", systemImage: "viewfinder")
                }
                .disabled(isBusy || viewModel.sourceLanguage == viewModel.targetLanguage)
            }
            if viewModel.sourceLanguage == viewModel.targetLanguage {
                Text("Choose different source and target languages.").font(.caption).foregroundColor(.red)
            }
            if viewModel.isTranslating {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Translating…").font(.caption).foregroundColor(.secondary)
                }
            }
            if let error = viewModel.errorMessage {
                Text(error).font(.caption).foregroundColor(.red).lineLimit(3)
            }
            Divider()
            HStack {
                Text("Translation").font(.headline)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(viewModel.translatedText, forType: .string)
                    showCopyFeedback = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showCopyFeedback = false }
                } label: {
                    Label(showCopyFeedback ? "Copied!" : "Copy", systemImage: "doc.on.doc")
                }
                .disabled(viewModel.translatedText.isEmpty || isBusy)
            }
            ScrollView {
                Text(viewModel.translatedText.isEmpty ? "Your translation will appear here." : viewModel.translatedText)
                    .foregroundColor(viewModel.translatedText.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(16)
        .frame(minWidth: 400, minHeight: 600)
        .onAppear { inputFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            if notification.object is MainWindow && !showingSettings {
                inputFocused = true
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: viewModel)
        }
    }
}


private extension VerticalAlignment {
    enum LanguageControlCenter: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }

    static let languageControlCenter = VerticalAlignment(LanguageControlCenter.self)
}
