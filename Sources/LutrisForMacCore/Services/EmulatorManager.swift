import Foundation
import AppKit

@MainActor
public final class EmulatorManager: ObservableObject {
    public static let shared = EmulatorManager()

    @Published public var emulators: [Emulator] = Emulator.all
    @Published public var isDownloading = false
    @Published public var downloadProgress: Double = 0
    @Published public var installStatus = ""
    @Published public var installError: String?

    private let fm = FileManager.default
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 120
        cfg.timeoutIntervalForResource = 300
        return URLSession(configuration: cfg)
    }()

    private init() {
        detectInstalled()
    }

    // MARK: - Erkennung

    public func detectInstalled() {
        for i in emulators.indices {
            let emu = emulators[i]
            let (installed, path) = detectEmulator(emu)
            emulators[i].installed = installed
            emulators[i].installPath = path
            emulators[i].installedVersion = installed ? readVersion(from: path) : ""
        }
    }

    public func checkForUpdates() async {
        for i in emulators.indices where emulators[i].githubOwner != nil && emulators[i].githubRepo != nil {
            let emu = emulators[i]
            if let latest = try? await latestGitHubVersion(owner: emu.githubOwner!, repo: emu.githubRepo!) {
                emulators[i].latestVersion = latest
            }
        }
    }

    private func readVersion(from path: String) -> String {
        if path.hasSuffix(".app") {
            let plistPath = "\(path)/Contents/Info.plist"
            guard let plist = NSDictionary(contentsOfFile: plistPath) else { return "" }
            return (plist["CFBundleShortVersionString"] as? String) ??
                   (plist["CFBundleVersion"] as? String) ?? ""
        }
        return ""
    }

    private func latestGitHubVersion(owner: String, repo: String) async throws -> String {
        let urlStr = "https://api.github.com/repos/\(owner)/\(repo)/releases/latest"
        guard let url = URL(string: urlStr) else { return "" }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return "" }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return "" }
        if let name = json["name"] as? String, !name.isEmpty, name != tag {
            let cleaned = name.replacingOccurrences(of: "^v", with: "", options: .regularExpression)
            if let range = cleaned.range(of: #"\d+(\.\d+)*"#, options: .regularExpression) {
                return String(cleaned[range])
            }
        }
        let cleaned = tag.replacingOccurrences(of: "^v", with: "", options: .regularExpression)
        guard let range = cleaned.range(of: #"\d+(\.\d+)*"#, options: .regularExpression) else { return cleaned }
        return String(cleaned[range])
    }

    private func detectEmulator(_ emu: Emulator) -> (Bool, String) {
        if let custom = emu.customInstallPath {
            let customPath = (custom as NSString).expandingTildeInPath
            if let appName = emu.appName {
                let appPath = "\(customPath)/\(appName)"
                if fm.fileExists(atPath: appPath) {
                    return (true, appPath)
                }
            }
            if let apps = try? fm.contentsOfDirectory(atPath: customPath) {
                for entry in apps where entry.hasSuffix(".app") {
                    return (true, "\(customPath)/\(entry)")
                }
            }
        }

        if let bundleID = emu.bundleID {
            if let appPath = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path {
                return (true, appPath)
            }
        }

        if let appName = emu.appName {
            let appPath = "/Applications/\(appName)"
            if fm.fileExists(atPath: appPath) {
                return (true, appPath)
            }
        }

        let appPrefix = emu.appName?.replacingOccurrences(of: ".app", with: "") ?? emu.name
        let lowerPrefix = appPrefix.lowercased()
        if let apps = try? fm.contentsOfDirectory(atPath: "/Applications") {
            for entry in apps where entry.hasSuffix(".app") {
                let entryName = entry.replacingOccurrences(of: ".app", with: "")
                let lowerEntry = entryName.lowercased()
                if lowerEntry == lowerPrefix || lowerEntry.hasPrefix(lowerPrefix + " ") || lowerEntry.hasPrefix(lowerPrefix + "-") {
                    return (true, "/Applications/\(entry)")
                }
            }
        }

        if let brewName = emu.brewName {
            let brewPaths = ["/opt/homebrew/bin/\(brewName)", "/usr/local/bin/\(brewName)"]
            for bp in brewPaths where fm.isExecutableFile(atPath: bp) {
                return (true, bp)
            }
            if let appName = emu.appName {
                let brewApp = "/Applications/\(appName)"
                if fm.fileExists(atPath: brewApp) {
                    return (true, brewApp)
                }
            }
        }

        return (false, "")
    }

    // MARK: - Download-URL ermitteln

    private func resolveDownloadURL(for emu: Emulator) async throws -> URL {
        if let owner = emu.githubOwner, let repo = emu.githubRepo {
            return try await latestGitHubRelease(owner: owner, repo: repo)
        }

        if let urlStr = emu.directDownloadURL, let url = URL(string: urlStr) {
            return url
        }

        throw EmuInstallError.noDownloadURL(emu.displayName)
    }

    private func latestGitHubRelease(owner: String, repo: String) async throws -> URL {
        let urlStr = "https://api.github.com/repos/\(owner)/\(repo)/releases/latest"
        guard let url = URL(string: urlStr) else {
            throw EmuInstallError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw EmuInstallError.downloadFailed("GitHub API: \(urlStr)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = json["assets"] as? [[String: Any]] else {
            throw EmuInstallError.downloadFailed("Keine GitHub-Assets gefunden")
        }

        let macKeywords = ["mac", "apple", "osx", "macos"]

        let sorted = assets.sorted { a, b in
            let nameA = (a["name"] as? String ?? "").lowercased()
            let nameB = (b["name"] as? String ?? "").lowercased()
            let scoreA = assetScore(nameA, macKeywords)
            let scoreB = assetScore(nameB, macKeywords)
            return scoreA > scoreB
        }

        guard let best = sorted.first,
              let browserURL = best["browser_download_url"] as? String,
              let downloadURL = URL(string: browserURL) else {
            throw EmuInstallError.downloadFailed("Kein passendes macOS-Asset gefunden")
        }

        return downloadURL
    }

    private func assetScore(_ name: String, _ keywords: [String]) -> Int {
        var score = 0

        if name.contains("windows") || name.contains("win-") { score -= 30 }
        if name.contains("linux") || name.contains("anylinux") { score -= 30 }
        if name.contains(".AppImage") || name.contains(".deb") || name.contains(".rpm") || name.contains(".ipa") { score -= 30 }

        if name.contains("libretro") { score -= 20 }

        if name.hasSuffix(".dmg") { score += 10 }
        if name.hasSuffix(".zip") { score += 5 }
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tar.xz") { score += 3 }

        for kw in keywords where name.contains(kw) { score += 20 }

        if name.contains("arm64") || name.contains("aarch64") || name.contains("apple-silicon") { score += 8 }
        if name.contains("x86_64") || name.contains("amd64") || name.contains("intel") { score += 4 }

        return score
    }

    // MARK: - Installation

    public func installEmulator(_ emu: Emulator) async throws {
        guard emulators.contains(where: { $0.id == emu.id }) else { return }
        isDownloading = true
        downloadProgress = 0
        installStatus = "Ermittle Download-URL…"
        installError = nil

        defer {
            isDownloading = false
            detectInstalled()
        }

        do {
            let downloadURL = try await resolveDownloadURL(for: emu)
            installStatus = "Lade \(emu.displayName) herunter…"

            let tmpDir = fm.temporaryDirectory.appendingPathComponent("emulator_install_\(emu.id.uuidString)")
            try? fm.removeItem(at: tmpDir)
            try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)

            let downloadedFile = try await downloadFile(url: downloadURL, to: tmpDir)

            installStatus = "Installiere \(emu.displayName)…"

            try await performInstall(emu, file: downloadedFile)

            try? fm.removeItem(at: tmpDir)
            if let idx = emulators.firstIndex(where: { $0.id == emu.id }), emulators[idx].installed {
                emulators[idx].installedVersion = readVersion(from: emulators[idx].installPath)
            }
            installStatus = "\(emu.displayName) installiert!"
            downloadProgress = 1
        } catch {
            installError = error.localizedDescription
            installStatus = "Fehler: \(error.localizedDescription)"
            throw error
        }
    }

    public func updateEmulator(_ emu: Emulator) async throws {
        try await installEmulator(emu)
    }

    // MARK: - Download

    private func downloadFile(url: URL, to directory: URL) async throws -> URL {
        let (tempURL, response) = try await session.download(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw EmuInstallError.downloadFailed(url.lastPathComponent)
        }

        let fileName = url.lastPathComponent
        let dest = directory.appendingPathComponent(fileName)
        try? fm.removeItem(at: dest)
        try fm.moveItem(at: tempURL, to: dest)
        return dest
    }

    // MARK: - Installationsmethoden

    private func installTargetDir(_ emu: Emulator) -> String {
        if let custom = emu.customInstallPath {
            return (custom as NSString).expandingTildeInPath
        }
        return "/Applications"
    }

    private func performInstall(_ emu: Emulator, file: URL) async throws {
        let targetDir = installTargetDir(emu)
        try? fm.createDirectory(atPath: targetDir, withIntermediateDirectories: true)

        switch emu.installType {
        case .dmg:
            try installDMG(file: file, appName: emu.appName, targetDir: targetDir)
        case .zip:
            try installZIP(file: file, appName: emu.appName, targetDir: targetDir)
        case .tarGz:
            try installTarGz(file: file, appName: emu.appName, targetDir: targetDir)
        case .pkg:
            try installPKG(file: file)
        case .homebrew:
            try installHomebrew(brewName: emu.brewName)
        case .sevenZ:
            try install7z(file: file, appName: emu.appName, targetDir: targetDir)
        }
    }

    private func installDMG(file: URL, appName: String?, targetDir: String = "/Applications") throws {
        let mountOutput = try shell("/usr/bin/hdiutil", ["attach", "-nobrowse", "-plist", file.path])
        guard let mountPath = parseMountPath(from: mountOutput) else {
            throw EmuInstallError.installFailed("Konnte DMG nicht mounten")
        }
        defer { _ = try? shell("/usr/bin/hdiutil", ["detach", mountPath, "-quiet"]) }

        let contents = try fm.contentsOfDirectory(atPath: mountPath)
        let apps = contents.filter { $0.hasSuffix(".app") }

        if let preferred = appName, apps.contains(preferred) {
            let src = "\(mountPath)/\(preferred)"
            let dest = "\(targetDir)/\(preferred)"
            try? fm.removeItem(atPath: dest)
            try fm.copyItem(atPath: src, toPath: dest)
        } else if let firstApp = apps.first {
            let dest = "\(targetDir)/\(firstApp)"
            try? fm.removeItem(atPath: dest)
            try fm.copyItem(atPath: "\(mountPath)/\(firstApp)", toPath: dest)
        } else {
            throw EmuInstallError.installFailed("Keine .app im DMG gefunden")
        }
    }

    private func installZIP(file: URL, appName: String?, targetDir: String = "/Applications") throws {
        let extractDir = file.deletingLastPathComponent().appendingPathComponent("extract")
        try? fm.removeItem(at: extractDir)
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try shell("/usr/bin/unzip", ["-o", file.path, "-d", extractDir.path])

        if let appPath = findApp(in: extractDir), let appName {
            let dest = "\(targetDir)/\(appName)"
            try? fm.removeItem(atPath: dest)
            try fm.copyItem(at: appPath, to: URL(fileURLWithPath: dest))
        } else if let appPath = findApp(in: extractDir) {
            let appName = appPath.lastPathComponent
            let dest = "\(targetDir)/\(appName)"
            try? fm.removeItem(atPath: dest)
            try fm.copyItem(at: appPath, to: URL(fileURLWithPath: dest))
        }

        try? fm.removeItem(at: extractDir)
    }

    private func installTarGz(file: URL, appName: String?, targetDir: String = "/Applications") throws {
        let extractDir = file.deletingLastPathComponent().appendingPathComponent("extract")
        try? fm.removeItem(at: extractDir)
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try shell("/usr/bin/tar", ["-xzf", file.path, "-C", extractDir.path])

        if let appPath = findApp(in: extractDir), let appName {
            let dest = "\(targetDir)/\(appName)"
            try? fm.removeItem(atPath: dest)
            try fm.copyItem(at: appPath, to: URL(fileURLWithPath: dest))
        } else if let appPath = findApp(in: extractDir) {
            let appName = appPath.lastPathComponent
            let dest = "\(targetDir)/\(appName)"
            try? fm.removeItem(atPath: dest)
            try fm.copyItem(at: appPath, to: URL(fileURLWithPath: dest))
        }

        try? fm.removeItem(at: extractDir)
    }

    private func installPKG(file: URL) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/installer")
        proc.arguments = ["-pkg", file.path, "-target", "/"]
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw EmuInstallError.installFailed("PKG-Installation fehlgeschlagen")
        }
    }

    private func installHomebrew(brewName: String?) throws {
        guard let name = brewName else {
            throw EmuInstallError.installFailed("Kein Homebrew-Name angegeben")
        }
        let result = try shell("/opt/homebrew/bin/brew", ["install", "--cask", name])
        guard !result.contains("Error") else {
            throw EmuInstallError.installFailed("Homebrew-Installation fehlgeschlagen: \(result)")
        }
    }

    private func install7z(file: URL, appName: String?, targetDir: String = "/Applications") throws {
        let tools = [
            "/usr/local/bin/7z",
            "/opt/homebrew/bin/7z",
            "/usr/local/bin/unar",
            "/opt/homebrew/bin/unar"
        ]
        var lastError: Error?
        for tool in tools {
            guard FileManager.default.isExecutableFile(atPath: tool) else { continue }
            let extractDir = file.deletingLastPathComponent().appendingPathComponent("extract")
            try? fm.removeItem(at: extractDir)
            try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
            let toolName = URL(fileURLWithPath: tool).lastPathComponent
            do {
                if toolName == "7z" {
                    try shell(tool, ["x", file.path, "-o\(extractDir.path)", "-y"])
                } else if toolName == "unar" {
                    try shell(tool, ["-o", extractDir.path, file.path])
                }

                if let appPath = findApp(in: extractDir), let appName {
                    let dest = "\(targetDir)/\(appName)"
                    try? fm.removeItem(atPath: dest)
                    try fm.copyItem(at: appPath, to: URL(fileURLWithPath: dest))
                    try? fm.removeItem(at: extractDir)
                    return
                } else if let appPath = findApp(in: extractDir) {
                    let appName = appPath.lastPathComponent
                    let dest = "\(targetDir)/\(appName)"
                    try? fm.removeItem(atPath: dest)
                    try fm.copyItem(at: appPath, to: URL(fileURLWithPath: dest))
                    try? fm.removeItem(at: extractDir)
                    return
                }
            } catch {
                lastError = error
                try? fm.removeItem(at: extractDir)
                continue
            }
        }
        throw lastError ?? EmuInstallError.installFailed("Kein 7z-Tool gefunden – installiere p7zip: brew install p7zip")
    }

    // MARK: - Hilfsfunktionen

    private func findApp(in directory: URL) -> URL? {
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: nil) else { return nil }
        for case let file as URL in enumerator {
            if file.pathExtension == "app" {
                return file
            }
        }
        return nil
    }

    private func parseMountPath(from plistOutput: String) -> String? {
        let lines = plistOutput.components(separatedBy: .newlines)
        var foundMount = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "<key>mount-point</key>" {
                foundMount = true
            } else if foundMount {
                if let start = trimmed.range(of: "<string>"),
                   let end = trimmed.range(of: "</string>") {
                    return String(trimmed[start.upperBound..<end.lowerBound])
                }
            }
        }
        return nil
    }

    @discardableResult
    private func shell(_ command: String, _ args: [String]) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: command)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        try proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output
    }
}

public enum EmuInstallError: LocalizedError {
    case noDownloadURL(String)
    case invalidURL
    case downloadFailed(String)
    case installFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noDownloadURL(let name): return "Keine Download-URL für \(name) verfügbar"
        case .invalidURL: return "Ungültige Download-URL"
        case .downloadFailed(let msg): return "Download fehlgeschlagen: \(msg)"
        case .installFailed(let msg): return "Installation fehlgeschlagen: \(msg)"
        }
    }
}
