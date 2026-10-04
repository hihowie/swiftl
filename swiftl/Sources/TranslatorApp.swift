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
    let viewModel = TranslatorViewModel()

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
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
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
