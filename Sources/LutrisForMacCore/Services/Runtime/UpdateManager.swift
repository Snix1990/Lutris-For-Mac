import Foundation
import AppKit

// MARK: - ReleaseInfo

public struct ReleaseInfo: Codable {
    public let version: String
    public let downloadURL: URL?
    public let releaseNotes: String?
    public let publishedAt: Date?

    public init(version: String, downloadURL: URL?, releaseNotes: String?, publishedAt: Date?) {
        self.version = version
        self.downloadURL = downloadURL
        self.releaseNotes = releaseNotes
        self.publishedAt = publishedAt
    }
}

// MARK: - UpdateManager

@MainActor
public final class UpdateManager: ObservableObject {
    public static let shared = UpdateManager()

    @Published public var updateAvailable: ReleaseInfo?
    @Published public var isChecking = false
    @Published public var lastCheckDate: Date?

    private let repoOwner = "Snix1990"
    private let repoName = "Lutris-For-Mac"

    private let defaultsLastCheckKey = "updateLastCheck"
    private let defaultsIgnoredVersionKey = "updateIgnoredVersion"

    private init() {}

    // MARK: - Check

    public func checkForUpdate() async {
        isChecking = true
        defer { isChecking = false }

        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return
        }

        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("LutrisForMac/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String else {
            return
        }

        let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        guard latestVersion.compare(currentVersion, options: .numeric) == .orderedDescending else {
            return
        }

        let ignoredVersion = UserDefaults.standard.string(forKey: defaultsIgnoredVersionKey)
        guard latestVersion != ignoredVersion else { return }

        let assets = json["assets"] as? [[String: Any]] ?? []
        let asset = assets.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }
                ?? assets.first { ($0["name"] as? String)?.hasSuffix(".zip") == true }
        let downloadURL = asset.flatMap { ($0["browser_download_url"] as? String).flatMap { URL(string: $0) } }
        let body = json["body"] as? String

        let iso = ISO8601DateFormatter()
        let published = (json["published_at"] as? String).flatMap { iso.date(from: $0) }

        let info = ReleaseInfo(version: tagName, downloadURL: downloadURL, releaseNotes: body, publishedAt: published)
        updateAvailable = info
        lastCheckDate = Date()
        UserDefaults.standard.set(Date(), forKey: defaultsLastCheckKey)

        NotificationManager.info(title: "Update verfügbar", message: "\(repoName) \(tagName) – Zum Download klicken", duration: 6)
    }

    // MARK: - Actions

    public func downloadUpdate(_ info: ReleaseInfo) {
        if let url = info.downloadURL {
            NSWorkspace.shared.open(url)
        } else {
            let fallback = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/latest")!
            NSWorkspace.shared.open(fallback)
        }
    }

    public func ignoreVersion(_ info: ReleaseInfo) {
        let v = info.version.hasPrefix("v") ? info.version : "v\(info.version)"
        UserDefaults.standard.set(v, forKey: defaultsIgnoredVersionKey)
        updateAvailable = nil
    }

    // MARK: - Headless Mode

    public var headlessMode: Bool {
        ProcessInfo.processInfo.environment["DISPLAY"] == nil &&
        ProcessInfo.processInfo.environment["WAYLAND_DISPLAY"] == nil
    }

    // MARK: - Health-Check

    public func healthCheck(game: Game) -> HealthCheckResult {
        if game.runner == "Wine" || game.runner == "CrossOver" {
            let winePath: String
            if let bp = game.wineBinaryPath, !bp.isEmpty {
                winePath = bp
            } else if let v = WineManager.shared.installedVersions.first(where: { $0.name == game.wineVersionName }) {
                winePath = v.wineBinaryPath
            } else {
                winePath = "/usr/local/bin/wine64"
            }

            guard FileManager.default.isExecutableFile(atPath: winePath) else {
                return .failure("Wine binary not found or not executable: \(winePath)")
            }

            if let prefixPath = game.winePrefixPath, !prefixPath.isEmpty {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: prefixPath, isDirectory: &isDir), isDir.boolValue else {
                    return .failure("Wine prefix not found: \(prefixPath)")
                }
                let driveC = "\(prefixPath)/drive_c"
                guard FileManager.default.fileExists(atPath: driveC, isDirectory: &isDir), isDir.boolValue else {
                    return .failure("Wine prefix missing drive_c – prefix may be corrupted: \(prefixPath)")
                }
                let system32 = "\(driveC)/windows/system32"
                if !FileManager.default.fileExists(atPath: system32) {
                    return .warning("Wine prefix incomplete (no system32) – wineboot may be needed: \(prefixPath)")
                }
            }
        }

        if !game.installPath.isEmpty {
            guard FileManager.default.fileExists(atPath: game.installPath) else {
                return .failure("Game install path not found: \(game.installPath)")
            }
        }

        return .success
    }
}

// MARK: - HealthCheckResult

public enum HealthCheckResult {
    case success
    case warning(String)
    case failure(String)

    public var isOK: Bool {
        if case .failure = self { return false }
        return true
    }

    public var message: String? {
        switch self {
        case .success: return nil
        case .warning(let m): return m
        case .failure(let m): return m
        }
    }
}
