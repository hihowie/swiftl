import Foundation
import Combine
import AppKit
import CryptoKit

struct UpdateInstallError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// Filesystem work is isolated so tests can validate an update without touching the installed app.
struct PreparedUpdate {
    let destination: URL
    let candidate: URL
    let backup: URL
    let staging: URL
}

enum UpdateFiles {
    static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        // Drain both streams together before waiting so a verbose subprocess cannot fill a pipe.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateInstallError(message: "Update verification or file operation failed. " + (String(data: data, encoding: .utf8) ?? "Unknown error").prefix(300))
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func isProtectedLocation(_ destination: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let path = destination.resolvingSymlinksInPath().standardizedFileURL.path
        return ["Desktop", "Documents", "Downloads", "Library/Mobile Documents"].contains { folder in
            let root = home.appendingPathComponent(folder).resolvingSymlinksInPath().standardizedFileURL.path
            return path == root || path.hasPrefix(root + "/")
        }
    }

    static func prepare(archive: URL, expectedHash: String, version: String, destination: URL) throws -> PreparedUpdate {
        let fm = FileManager.default
        guard !isProtectedLocation(destination) else {
            throw UpdateInstallError(message: "Automatic updates cannot run from Desktop, Documents, Downloads, or iCloud Drive. Move SwifTL to Applications first, then retry.")
        }
        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard hash == expectedHash else { throw UpdateInstallError(message: "The downloaded update checksum does not match GitHub. Try downloading again.") }
        let parent = destination.deletingLastPathComponent()
        guard destination.pathExtension == "app", fm.isWritableFile(atPath: parent.path),
              fm.isWritableFile(atPath: destination.path), !destination.path.contains("/AppTranslocation/"),
              !destination.path.hasPrefix("/Volumes/") else {
            throw UpdateInstallError(message: "SwifTL cannot replace this app copy. Move it to a writable Applications folder, or update manually.")
        }
        let entries = try run("/usr/bin/unzip", ["-Z1", archive.path]).split(separator: "\n").map(String.init)
        guard !entries.isEmpty, entries.allSatisfy({ name in
            let components = name.split(separator: "/", omittingEmptySubsequences: false)
            return !name.hasPrefix("/") && !components.contains("..") && !components.contains(".")
                && !name.contains("\\") && !name.contains("\r")
                && (name.hasPrefix("SwifTL.app/") || name.hasPrefix("__MACOSX/"))
        }) else { throw UpdateInstallError(message: "The update archive contains unexpected paths.") }
        let listing = try run("/usr/bin/zipinfo", ["-l", archive.path])
        guard !listing.split(separator: "\n").contains(where: { $0.hasPrefix("l") }) else {
            throw UpdateInstallError(message: "The update archive contains unsupported symbolic links.")
        }
        let staging = fm.temporaryDirectory.appendingPathComponent("SwifTL-update-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let candidate = parent.appendingPathComponent(".SwifTL-update-" + UUID().uuidString + ".app", isDirectory: true)
        let backup = parent.appendingPathComponent(".SwifTL-backup-" + UUID().uuidString + ".app", isDirectory: true)
        do {
            _ = try run("/usr/bin/ditto", ["-x", "-k", archive.path, staging.path])
            let app = staging.appendingPathComponent("SwifTL.app")
            let infoURL = app.appendingPathComponent("Contents/Info.plist")
            let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), format: nil) as? [String: Any]
            guard info?["CFBundleIdentifier"] as? String == "com.example.swiftl",
                  let installed = info?["CFBundleShortVersionString"] as? String,
                  let installedVersion = AppVersion(installed), let expectedVersion = AppVersion(version),
                  installedVersion == expectedVersion,
                  fm.fileExists(atPath: app.appendingPathComponent("Contents/MacOS/SwifTL").path) else {
                throw UpdateInstallError(message: "The update app identity or version does not match its release.")
            }
            _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
            try fm.copyItem(at: app, to: candidate)
            _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", candidate.path])
            return PreparedUpdate(destination: destination, candidate: candidate, backup: backup, staging: staging)
        } catch {
            try? fm.removeItem(at: candidate)
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    // The helper survives app termination, performs same-filesystem renames, and can restore the backup.
    // A test can skip launching UI while exercising exactly the same replacement and rollback operations.
    static func helper(_ prepared: PreparedUpdate, processID: Int32, relaunch: Bool = true) throws -> Process {
        let script = prepared.staging.appendingPathComponent("install.sh")
        let text = """
        #!/bin/sh
        target="$1"
        candidate="$2"
        backup="$3"
        old_pid="$4"
        launch="$5"
        count=0
        while /bin/kill -0 "$old_pid" 2>/dev/null; do
          count=$((count + 1))
          if [ "$count" -ge 150 ]; then
            printf '%s\\n' 'failed: SwifTL did not quit. No files were replaced.' > "$6"
            exit 1
          fi
          /bin/sleep 0.2
        done
        if ! /bin/mv "$target" "$backup"; then
          printf '%s\\n' 'failed: Could not move the previous app. Update manually.' > "$6"
          if [ "$launch" = 1 ]; then /usr/bin/open "$target"; fi
          exit 1
        fi
        if ! /bin/mv "$candidate" "$target"; then
          /bin/mv "$backup" "$target"
          printf '%s\\n' 'failed: Could not install the update. The previous app was restored.' > "$6"
          if [ "$launch" = 1 ]; then /usr/bin/open "$target"; fi
          exit 1
        fi
        printf '%s\\n' 'installed' > "$6"
        if [ "$launch" = 1 ]; then
          if ! /usr/bin/open "$target"; then
            /bin/mv "$target" "$candidate"
            /bin/mv "$backup" "$target"
            printf '%s\\n' 'failed: Could not reopen the new app. The previous app was restored.' > "$6"
            /usr/bin/open "$target"
            exit 1
          fi
        fi
        """
        try text.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = [script.path, prepared.destination.path, prepared.candidate.path, prepared.backup.path,
                            String(processID), relaunch ? "1" : "0", prepared.staging.appendingPathComponent("status").path]
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()
        return helper
    }
}

@MainActor
final class UpdateInstaller: ObservableObject {
    static let shared = UpdateInstaller()
    @Published private(set) var message: String?
    @Published private(set) var busy = false
    private var helperProcess: Process?
    private let pendingKey = "PendingUpdateStaging"

    func restoreStatus() {
        guard let path = UserDefaults.standard.string(forKey: pendingKey) else { return }
        let staging = URL(fileURLWithPath: path)
        guard let status = try? String(contentsOf: staging.appendingPathComponent("status"), encoding: .utf8) else { return }
        UserDefaults.standard.removeObject(forKey: pendingKey)
        if status.hasPrefix("failed:") { message = status.trimmingCharacters(in: .whitespacesAndNewlines) }
        else { message = "SwifTL was updated successfully. The previous app remains beside it as a hidden backup." }
    }

    func install(_ release: AvailableUpdate) {
        guard !busy else { return }
        guard let url = release.archiveURL, let hash = release.archiveSHA256 else {
            message = "This release has no verified ZIP update package. Use Download installer instead."
            return
        }
        busy = true
        message = "Downloading update…"
        Task {
            var prepared: PreparedUpdate?
            do {
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 180)
                request.setValue("SwifTL", forHTTPHeaderField: "User-Agent")
                let (temporary, response) = try await URLSession.shared.download(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw UpdateInstallError(message: "GitHub could not provide the update package. Try again.")
                }
                message = "Verifying update…"
                let destination = Bundle.main.bundleURL
                let ready = try await Task.detached(priority: .userInitiated) {
                    try UpdateFiles.prepare(archive: temporary, expectedHash: hash, version: release.version, destination: destination)
                }.value
                prepared = ready
                UserDefaults.standard.set(ready.staging.path, forKey: pendingKey)
                message = "Installing update and restarting…"
                helperProcess = try UpdateFiles.helper(ready, processID: ProcessInfo.processInfo.processIdentifier)
                NSApp.terminate(nil)
            } catch {
                if let prepared = prepared {
                    try? FileManager.default.removeItem(at: prepared.candidate)
                    try? FileManager.default.removeItem(at: prepared.staging)
                    UserDefaults.standard.removeObject(forKey: pendingKey)
                }
                message = "Update failed: \(error.localizedDescription) You can download the installer manually."
                busy = false
            }
        }
    }
}
