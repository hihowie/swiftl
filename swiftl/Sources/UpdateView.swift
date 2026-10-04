import SwiftUI
import AppKit

struct UpdateStatusView: View {
    @ObservedObject var checker: UpdateChecker
    @ObservedObject private var installer = UpdateInstaller.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Updates").font(.subheadline.weight(.medium))
            Text("Current version: \(checker.currentVersion)").font(.caption).foregroundColor(.secondary)
            switch checker.status {
            case .idle:
                Text("Check GitHub Releases for a newer version.").font(.caption).foregroundColor(.secondary)
            case .checking:
                HStack { ProgressView().controlSize(.small); Text("Checking GitHub…").font(.caption) }
            case .upToDate:
                Text("You’re up to date.").font(.caption).foregroundColor(.green)
            case .noReleases:
                Text("No stable releases have been published yet.").font(.caption).foregroundColor(.secondary)
            case .failed(let message):
                Text(message).font(.caption).foregroundColor(.red)
            case .available(let release):
                Text("Version \(release.version) is available.").font(.caption).foregroundColor(.green)
                HStack {
                    if release.archiveURL != nil && release.archiveSHA256 != nil {
                        Button("Install and Restart") { installer.install(release) }.disabled(installer.busy)
                    }
                    if let installer = release.installerURL {
                        Button("Download installer") { NSWorkspace.shared.open(installer) }
                    }
                    Button("View release") { NSWorkspace.shared.open(release.releaseURL) }
                }
                Text("Install and Restart updates this app automatically. Settings are kept; current text is cleared on restart. The DMG is available for manual installation.")
                    .font(.caption).foregroundColor(.secondary)
            }
            if let message = installer.message {
                HStack {
                    if installer.busy { ProgressView().controlSize(.small) }
                    Text(message).font(.caption).foregroundColor(installer.busy ? .secondary : .primary)
                }
            }
            HStack {
                Button("Check for Updates…") { checker.check() }.disabled(checker.status == .checking || installer.busy)
                Spacer()
                Button("GitHub Releases") { NSWorkspace.shared.open(UpdateChecker.releasesURL) }
            }
        }
    }
}

final class UpdateWindowController: NSWindowController {
    static let shared = UpdateWindowController()
    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 340), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "SwifTL Updates"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: UpdateStatusView(checker: .shared).padding(20).frame(width: 460, height: 340, alignment: .topLeading))
        window.center()
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }
    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        UpdateChecker.shared.check()
    }
}
