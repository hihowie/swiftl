import SwiftUI
import AppKit

@main
struct TranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(viewModel: appDelegate.viewModel)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { UpdateWindowController.shared.checkForUpdates() }
            }
            CommandGroup(after: .windowArrangement) {
                Button("Show SwifTL") { appDelegate.showMainWindow() }
                    .keyboardShortcut("1", modifiers: .command)
            }
        }
    }
}

class MainWindow: NSWindow {}

class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var mainWindow: MainWindow?
    let viewModel: TranslatorViewModel = {
        // Carry over language choices when upgrading from the sandboxed build.
        let defaults = UserDefaults.standard
        let keys = ["DefaultSourceLanguageCode", "DefaultTargetLanguageCode"]
        if keys.allSatisfy({ defaults.string(forKey: $0) == nil }),
           let identifier = Bundle.main.bundleIdentifier {
            let path = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers/\(identifier)/Data/Library/Preferences/\(identifier).plist")
            if let data = try? Data(contentsOf: path),
               let previous = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let source = previous[keys[0]] as? String, let target = previous[keys[1]] as? String {
                defaults.set(source, forKey: keys[0])
                defaults.set(target, forKey: keys[1])
            }
        }
        return TranslatorViewModel()
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        let window = MainWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SwifTL"
        window.contentView = NSHostingView(rootView: ContentView().environmentObject(viewModel))
        window.contentMinSize = NSSize(width: 400, height: 600)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("SwifTLMainWindow")
        mainWindow = window
        showMainWindow()
        SelectionTranslation.shared.start(appDelegate: self)
        UpdateInstaller.shared.restoreStatus()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag || mainWindow?.isVisible != true { showMainWindow() }
        return true
    }

    func showMainWindow() {
        guard let window = mainWindow else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
