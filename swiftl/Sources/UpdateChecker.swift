import Foundation
import Combine

struct AppVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ value: String) {
        let text = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let major = Int(parts[0]), let minor = Int(parts[1]),
              let patch = parts.count == 3 ? Int(parts[2]) : 0 else { return nil }
        self.major = major; self.minor = minor; self.patch = patch
    }
    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

struct AvailableUpdate: Equatable {
    let version: String
    let releaseURL: URL
    let installerURL: URL?
    let archiveURL: URL?
    let archiveSHA256: String?
}

enum UpdateStatus: Equatable {
    case idle, checking, upToDate, noReleases
    case available(AvailableUpdate)
    case failed(String)
}

final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    static let releasesURL = URL(string: "https://github.com/hihowie/swiftl/releases")!
    static let latestURL = URL(string: "https://api.github.com/repos/hihowie/swiftl/releases/latest")!
    @Published private(set) var status: UpdateStatus = .idle
    let currentVersion: String
    private let session: URLSession

    init(session: URLSession = .shared, currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown") {
        self.session = session
        self.currentVersion = currentVersion
    }

    func check() {
        guard status != .checking else { return }
        guard let current = AppVersion(currentVersion) else {
            status = .failed("The installed app version is unavailable. Download a release from GitHub.")
            return
        }
        status = .checking
        var request = URLRequest(url: Self.latestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SwifTL/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        session.dataTask(with: request) { [weak self] data, response, error in
            let status: UpdateStatus
            if let error = error {
                status = .failed("Could not reach GitHub: \(error.localizedDescription) Try again.")
            } else if let http = response as? HTTPURLResponse {
                switch http.statusCode {
                case 404: status = .noReleases
                case 403, 429: status = .failed("GitHub denied the request or its request limit was reached. Try again later.")
                case 200:
                    do {
                        guard let data = data else { throw ReleaseError.invalid }
                        status = try Self.parse(data, current: current)
                    } catch { status = .failed("GitHub returned an invalid release. Open Releases to check manually.") }
                default: status = .failed("GitHub returned HTTP \(http.statusCode). Try again.")
                }
            } else { status = .failed("No response from GitHub. Try again.") }
            DispatchQueue.main.async { self?.status = status }
        }.resume()
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
            let state: String
            let digest: String?
        }
        let tag_name: String
        let html_url: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }
    private enum ReleaseError: Error { case invalid }

    private static func trustedURL(_ string: String, path: String) -> URL? {
        guard let url = URL(string: string), url.scheme == "https", url.host == "github.com",
              url.user == nil, url.password == nil, url.port == nil,
              url.path == path, url.query == nil, url.fragment == nil else { return nil }
        return url
    }

    private static func parse(_ data: Data, current: AppVersion) throws -> UpdateStatus {
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard !release.draft, !release.prerelease else { return .noReleases }
        guard let version = AppVersion(release.tag_name),
              let page = trustedURL(release.html_url, path: "/hihowie/swiftl/releases/tag/\(release.tag_name)") else { throw ReleaseError.invalid }
        guard version > current else { return .upToDate }
        let assetName = "SwifTL-\(release.tag_name)-universal.dmg"
        let asset = release.assets.first { $0.name == assetName && $0.state == "uploaded" }
        let installer = asset.flatMap { trustedURL($0.browser_download_url, path: "/hihowie/swiftl/releases/download/\(release.tag_name)/\(assetName)") }
        let archiveName = "SwifTL-\(release.tag_name)-universal.zip"
        let archive = release.assets.first { $0.name == archiveName && $0.state == "uploaded" }
        let archiveURL = archive.flatMap { trustedURL($0.browser_download_url, path: "/hihowie/swiftl/releases/download/\(release.tag_name)/\(archiveName)") }
        let digest = archive?.digest.flatMap { value -> String? in
            guard value.hasPrefix("sha256:") else { return nil }
            let hash = String(value.dropFirst(7)).lowercased()
            return hash.count == 64 && hash.allSatisfy { "0123456789abcdef".contains($0) } ? hash : nil
        }
        return .available(AvailableUpdate(version: release.tag_name, releaseURL: page, installerURL: installer,
                                         archiveURL: archiveURL, archiveSHA256: digest))
    }
}
