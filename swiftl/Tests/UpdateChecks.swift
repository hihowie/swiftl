import Foundation
import CryptoKit

final class ReleaseProtocol: URLProtocol {
    static var data = Data()
    static var code = 200
    static var failure: Error?
    static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        if let error = Self.failure { client?.urlProtocol(self, didFailWithError: error); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct UpdateChecks {
    static func check(_ value: @autoclosure () -> Bool, _ name: String) {
        guard value() else { fatalError("FAIL: \(name)") }
        print("PASS: \(name)")
    }
    static func wait(_ checker: UpdateChecker) {
        let end = Date().addingTimeInterval(25)
        while checker.status == .checking && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        check(checker.status != .checking, "update request finishes")
    }
    static func hash(_ file: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
    }
    static func release(_ tag: String = "v1.2.0", _ changes: [String: Any] = [:]) throws -> Data {
        var value: [String: Any] = ["tag_name": tag, "html_url": "https://github.com/hihowie/swiftl/releases/tag/\(tag)", "draft": false, "prerelease": false,
            "assets": ["zip", "dmg"].map { ext in ["name": "SwifTL-\(tag)-universal.\(ext)", "browser_download_url": "https://github.com/hihowie/swiftl/releases/download/\(tag)/SwifTL-\(tag)-universal.\(ext)", "state": "uploaded", "digest": "sha256:" + String(repeating: "a", count: 64)] }]
        changes.forEach { value[$0.key] = $0.value }
        return try JSONSerialization.data(withJSONObject: value)
    }
    static func main() throws {
        check(AppVersion("v1.10.0")! > AppVersion("1.9.9")!, "numeric version ordering")
        check(AppVersion("1.0") == AppVersion("1.0.0"), "legacy two-part version")
        for value in ["", "1", "1..0", "1.2.3.4", "1.0-beta", "1.0.0+build", "-1.0", "９.０", "9999999999999999999999.0"] {
            check(AppVersion(value) == nil, "invalid version rejected: \(value)")
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReleaseProtocol.self]
        let checker = UpdateChecker(session: URLSession(configuration: config), currentVersion: "1.1.0")
        func request(_ data: Data, code: Int = 200) { ReleaseProtocol.data = data; ReleaseProtocol.code = code; checker.check(); checker.check(); wait(checker) }
        request(try release())
        guard case .available(let update) = checker.status else { fatalError("new version missing") }
        check(update.archiveSHA256?.count == 64 && update.archiveURL != nil && update.installerURL != nil, "verified ZIP and manual DMG available")
        check(ReleaseProtocol.requests.count == 1, "duplicate submission suppressed")
        check(ReleaseProtocol.requests[0].url == UpdateChecker.latestURL && ReleaseProtocol.requests[0].value(forHTTPHeaderField: "Authorization") == nil, "public repository endpoint needs no token")
        request(try release("v1.1.0")); check(checker.status == .upToDate, "same version is current")
        request(try release("v1.0.0")); check(checker.status == .upToDate, "older release does not downgrade")
        request(Data(), code: 404); check(checker.status == .noReleases, "no first release handled")
        for code in [403, 429, 500] { request(Data(), code: code); if case .failed = checker.status {} else { fatalError("HTTP error missing") } }
        for key in ["draft", "prerelease"] { request(try release("v1.2.0", [key: true])); check(checker.status == .noReleases, "\(key) ignored") }
        request(try release("v1.2.0", ["assets": []])); if case .available(let item) = checker.status { check(item.archiveURL == nil && item.installerURL == nil, "missing assets permit release-page fallback") }
        request(try release("v1.2.0", ["html_url": "https://github.com/other/swiftl/releases/tag/v1.2.0"])); if case .failed = checker.status {} else { fatalError("wrong repo accepted") }
        request(Data("invalid".utf8)); if case .failed = checker.status {} else { fatalError("bad JSON accepted") }
        ReleaseProtocol.failure = URLError(.notConnectedToInternet); request(Data()); if case .failed = checker.status {} else { fatalError("offline error missing") }
        ReleaseProtocol.failure = nil; request(try release()); if case .available = checker.status {} else { fatalError("retry failed") }
        let unsafeAssets: [[String: String]] = [["name": "SwifTL-v1.2.0-universal.zip", "state": "uploaded", "browser_download_url": "https://evil.example/update.zip", "digest": "sha256:bad"]]
        request(try release("v1.2.0", ["assets": unsafeAssets])); if case .available(let item) = checker.status { check(item.archiveURL == nil && item.archiveSHA256 == nil, "untrusted download URL and invalid checksum rejected") }

        let fm = FileManager.default
        let mockHome = URL(fileURLWithPath: "/tmp/swiftl-home")
        for folder in ["Desktop", "Documents", "Downloads", "Library/Mobile Documents"] {
            check(UpdateFiles.isProtectedLocation(mockHome.appendingPathComponent(folder + "/SwifTL.app"), home: mockHome), "protected folder blocked before app quits: \(folder)")
        }
        check(!UpdateFiles.isProtectedLocation(mockHome.appendingPathComponent("Applications/SwifTL.app"), home: mockHome), "writable Applications permits automatic update")
        check(!UpdateFiles.isProtectedLocation(mockHome.appendingPathComponent("Desktop-other/SwifTL.app"), home: mockHome), "folder detection respects path boundaries")
        let root = fm.temporaryDirectory.appendingPathComponent("SwifTL update tests ' $ " + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let app = root.appendingPathComponent("SwifTL.app")
        let contents = app.appendingPathComponent("Contents")
        try fm.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try fm.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: contents.appendingPathComponent("MacOS/SwifTL"))
        let info: [String: String] = ["CFBundleIdentifier": "com.example.swiftl", "CFBundleExecutable": "SwifTL", "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "1.2.0", "CFBundleVersion": "1"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        _ = try UpdateFiles.run("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
        let zip = root.appendingPathComponent("update.zip")
        func archive() throws { try? fm.removeItem(at: zip); _ = try UpdateFiles.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", app.path, zip.path]) }
        try archive()
        let target = root.appendingPathComponent("installed copy.app")
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: target.appendingPathComponent("marker"))
        func reject(_ checksum: String, _ version: String, _ name: String) throws {
            do { _ = try UpdateFiles.prepare(archive: zip, expectedHash: checksum, version: version, destination: target); fatalError("accepted \(name)") } catch { check(fm.fileExists(atPath: target.appendingPathComponent("marker").path), "\(name) preserves installed app") }
        }
        try reject(String(repeating: "0", count: 64), "v1.2.0", "checksum mismatch")
        try reject(hash(zip), "v1.3.0", "version mismatch")
        try reject(hash(zip), "invalid", "invalid version")
        let prepared = try UpdateFiles.prepare(archive: zip, expectedHash: hash(zip), version: "v1.2.0", destination: target)
        let helper = try UpdateFiles.helper(prepared, processID: Int32.max, relaunch: false)
        helper.waitUntilExit()
        check(helper.terminationStatus == 0 && fm.fileExists(atPath: target.appendingPathComponent("Contents/MacOS/SwifTL").path), "automatic installation replaces app in paths with spaces and shell characters")
        check(fm.fileExists(atPath: prepared.backup.appendingPathComponent("marker").path), "previous app kept as backup")
        try? fm.removeItem(at: prepared.staging)
        let rollbackStage = root.appendingPathComponent("rollback")
        try fm.createDirectory(at: rollbackStage, withIntermediateDirectories: true)
        let rollback = PreparedUpdate(destination: target, candidate: root.appendingPathComponent("missing.app"), backup: root.appendingPathComponent("backup.app"), staging: rollbackStage)
        let failed = try UpdateFiles.helper(rollback, processID: Int32.max, relaunch: false)
        failed.waitUntilExit()
        check(failed.terminationStatus != 0 && fm.fileExists(atPath: target.appendingPathComponent("Contents/MacOS/SwifTL").path), "replacement failure restores previous app")
        let rollbackStatus = try String(contentsOf: rollbackStage.appendingPathComponent("status"))
        check(rollbackStatus.hasPrefix("failed:"), "rollback reports failure")
        // Corrupt the signed executable while preserving a correct archive checksum.
        let executable = contents.appendingPathComponent("MacOS/SwifTL")
        var bytes = try Data(contentsOf: executable); bytes.append(0); try bytes.write(to: executable)
        try archive()
        try Data("old".utf8).write(to: target.appendingPathComponent("marker"))
        try reject(hash(zip), "v1.2.0", "invalid code signature")
        try fm.createSymbolicLink(at: contents.appendingPathComponent("unsafe-link"), withDestinationURL: URL(fileURLWithPath: "/tmp"))
        try archive(); try reject(hash(zip), "v1.2.0", "archive symbolic link")
        if CommandLine.arguments.contains("--live") {
            let live = UpdateChecker(currentVersion: "1.0.0"); live.check(); wait(live)
            if case .available(let item) = live.status {
                check(item.archiveURL != nil && item.archiveSHA256 != nil, "published release provides verified automatic-update archive")
                let downloaded = root.appendingPathComponent("github-release.zip")
                var downloadFinished = false
                var downloadFailure: Error?
                URLSession.shared.downloadTask(with: item.archiveURL!) { temporary, response, error in
                    var problem = error
                    if let temporary = temporary, (response as? HTTPURLResponse)?.statusCode == 200 {
                        do { try fm.copyItem(at: temporary, to: downloaded) } catch { problem = error }
                    } else if problem == nil { problem = UpdateInstallError(message: "Live ZIP download failed") }
                    let finishedProblem = problem
                    DispatchQueue.main.async { downloadFailure = finishedProblem; downloadFinished = true }
                }.resume()
                let downloadDeadline = Date().addingTimeInterval(180)
                while !downloadFinished && Date() < downloadDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
                check(downloadFinished && downloadFailure == nil, "real GitHub ZIP download")
                let actual = try UpdateFiles.prepare(archive: downloaded, expectedHash: item.archiveSHA256!, version: item.version, destination: target)
                let actualHelper = try UpdateFiles.helper(actual, processID: Int32.max, relaunch: false)
                actualHelper.waitUntilExit()
                check(actualHelper.terminationStatus == 0, "published universal app checksum, signature, version, and installation verified in disposable copy")
                try? fm.removeItem(at: actual.staging)
                let current = UpdateChecker(currentVersion: String(item.version.dropFirst(item.version.hasPrefix("v") ? 1 : 0))); current.check(); wait(current)
                check(current.status == .upToDate, "live GitHub current-version check")
            } else { fatalError("Live release unavailable: \(live.status)") }
        }
        print("All update checks passed")
    }
}
