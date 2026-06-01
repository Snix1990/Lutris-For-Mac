import Foundation
import Combine

@MainActor
final class SteamEmulatorManager: ObservableObject {
    static let shared = SteamEmulatorManager()

    private let emuDir: URL
    private let steamlessURL: URL
    private let goldbergDir: URL
    private let sessionFile: URL
    private let fm = FileManager.default

    @Published var sessionAccountName: String?
    @Published var sessionSteamID: String?
    @Published var isDownloading = false
    @Published var downloadProgress: Double? = 0
    @Published var downloadStatusText = ""
    @Published var downloadError: String?
    @Published var downloadComplete = false
    @Published var applyWarning: String?
    private var sessionCookie: String?

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 120
        cfg.timeoutIntervalForResource = 300
        return URLSession(configuration: cfg)
    }()

    var isLoggedIn: Bool { sessionCookie != nil }

    private init() {
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LutrisForMac")
        emuDir = appSupport.appendingPathComponent("steam_emu")
        steamlessURL = emuDir.appendingPathComponent("Steamless.exe")
        goldbergDir = emuDir.appendingPathComponent("goldberg")
        sessionFile = emuDir.appendingPathComponent("session.json")
        try? fm.createDirectory(at: emuDir, withIntermediateDirectories: true)
        refreshDownloadedFlags()
        downloadComplete = isSteamlessDownloaded && isGoldbergDownloaded
        loadSession()
    }

    // MARK: - Session

    func saveSession(accountName: String, cookie: String) {
        sessionAccountName = accountName
        sessionCookie = cookie
        let steamID = cookie.components(separatedBy: "%7C").first ?? ""
        sessionSteamID = steamID
        persistSession()
    }

    func clearSession() {
        sessionAccountName = nil
        sessionCookie = nil
        sessionSteamID = nil
        try? fm.removeItem(at: sessionFile)
    }

    private func loadSession() {
        guard let data = try? Data(contentsOf: sessionFile),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        sessionAccountName = dict["accountName"]
        sessionCookie = dict["cookie"]
        sessionSteamID = dict["steamID"]
    }

    private func persistSession() {
        let dict = [
            "accountName": sessionAccountName ?? "",
            "cookie": sessionCookie ?? "",
            "steamID": sessionSteamID ?? "",
        ]
        if let data = try? JSONEncoder().encode(dict) {
            try? data.write(to: sessionFile, options: .atomic)
        }
    }

    @Published var isSteamlessDownloaded = false
    @Published var isGoldbergDownloaded = false

    func refreshDownloadedFlags() {
        isSteamlessDownloaded = fm.fileExists(atPath: steamlessURL.path)
        let goldbergDLL = goldbergDir.appendingPathComponent("steam_api64.dll")
        isGoldbergDownloaded = fm.fileExists(atPath: goldbergDLL.path)
        if isSteamlessDownloaded && isGoldbergDownloaded {
            downloadComplete = true
        }
    }

    func downloadTools() async throws {
        isDownloading = true
        downloadProgress = nil
        downloadError = nil
        downloadComplete = false
        defer {
            isDownloading = false
            refreshDownloadedFlags()
        }

        do {
            if !isSteamlessDownloaded {
                downloadStatusText = "Lade Steamless herunter…"
                guard let url = URL(string: "https://github.com/atom0s/Steamless/releases/download/v3.1.0.5/Steamless.v3.1.0.5.-.by.atom0s.zip") else {
                    throw SteamEmuError.invalidURL
                }
                let zipPath = emuDir.appendingPathComponent("steamless.zip")
                try await download(url: url, to: zipPath)
                downloadStatusText = "Entpacke Steamless…"
                let extractDir = emuDir.appendingPathComponent(".steamless_extract")
                try? fm.removeItem(at: extractDir)
                try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
                try await unzip(zipPath: zipPath, to: extractDir)
                try? fm.removeItem(at: zipPath)
                let found = findFiles(named: ["steamless.exe"], in: extractDir)
                guard let steamlessFile = found.first else {
                    try? fm.removeItem(at: extractDir)
                    throw SteamEmuError.setupFailed("Steamless.exe nicht im Archiv gefunden")
                }
                try? fm.createDirectory(at: emuDir, withIntermediateDirectories: true)
                try fm.copyItem(at: steamlessFile, to: steamlessURL)
                try? fm.removeItem(at: extractDir)
                refreshDownloadedFlags()
            }

            if !isGoldbergDownloaded {
                downloadStatusText = "Lade Goldberg Emulator herunter…"
                guard let url = URL(string: "https://gitlab.com/Mr_Goldberg/goldberg_emulator/uploads/b39dc2c76f98738b8f49563886ce292c/Goldberg_Lan_Steam_Emu_v0.2.4.zip") else {
                    throw SteamEmuError.invalidURL
                }
                let zipPath = emuDir.appendingPathComponent("goldberg.zip")
                try await download(url: url, to: zipPath)
                downloadStatusText = "Entpacke Goldberg Emulator…"
                let extractDir = emuDir.appendingPathComponent(".goldberg_extract")
                try? fm.removeItem(at: extractDir)
                try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
                try await unzip(zipPath: zipPath, to: extractDir)
                try? fm.removeItem(at: zipPath)
                let dlls = findFiles(named: ["steam_api.dll", "steam_api64.dll"], in: extractDir)
                guard !dlls.isEmpty else {
                    try? fm.removeItem(at: extractDir)
                    throw SteamEmuError.setupFailed("Keine Goldberg-DLLs im Archiv gefunden")
                }
                try? fm.createDirectory(at: goldbergDir, withIntermediateDirectories: true)
                for dll in dlls {
                    let dest = goldbergDir.appendingPathComponent(dll.lastPathComponent)
                    if fm.fileExists(atPath: dest.path) { continue }
                    try fm.copyItem(at: dll, to: dest)
                }
                try? fm.removeItem(at: extractDir)
                refreshDownloadedFlags()
            }

            downloadProgress = 1
            downloadStatusText = "Fertig!"
            downloadComplete = true
        } catch {
            downloadError = error.localizedDescription
            downloadStatusText = "Fehler: \(error.localizedDescription)"
            throw error
        }
    }

    /// Findet ein Wine-Binary – egal ob CrossOver, Whisky, Gcenx, Homebrew oder system
    private func wineBinary(for game: Game) -> String? {
        let mgr = WineManager.shared
        // 1. Spezifische Version aus game.wineVersionName
        if let versionName = game.wineVersionName,
           let version = mgr.installedVersions.first(where: { $0.name == versionName }),
           fm.isExecutableFile(atPath: version.wineBinaryPath) {
            return version.wineBinaryPath
        }
        // 2. Erste installierte Version (egal welcher Source)
        if let version = mgr.installedVersions.first(where: { fm.isExecutableFile(atPath: $0.wineBinaryPath) }) {
            return version.wineBinaryPath
        }
        // 3. Letzter Fallback: bekannte Pfade
        for path in ["/usr/local/bin/wine", "/opt/homebrew/bin/wine", "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine"] {
            if fm.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    /// Nur Goldberg DLLs + steam_settings deployen (ohne Steamless)
    func deployGoldbergOnly(game: Game) async throws {
        guard game.steamEmulatorEnabled == true,
              let steamID = game.steamAppID, !steamID.isEmpty else {
            throw SteamEmuError.setupFailed("Steam-App-ID nicht gesetzt")
        }
        guard isGoldbergDownloaded else {
            throw SteamEmuError.goldbergMissing
        }

        let exePath = game.installPath
        guard fm.fileExists(atPath: exePath) else {
            throw SteamEmuError.setupFailed("Exe nicht gefunden: \(exePath)")
        }

        let dir = (exePath as NSString).deletingLastPathComponent
        let backupPath = "\(exePath).lutrisbak"

        // Backup
        if !fm.fileExists(atPath: backupPath) {
            try fm.copyItem(atPath: exePath, toPath: backupPath)
        }

        // Goldberg DLLs deployen
        let is64Bit = exePath.lowercased().contains("_64") ||
                      detectPEArch(exePath: exePath) == "x64"
        let goldbergDlls: [(src: String, dst: String)]
        if is64Bit {
            goldbergDlls = [("\(goldbergDir.path)/steam_api64.dll", "\(dir)/steam_api64.dll")]
        } else {
            goldbergDlls = [("\(goldbergDir.path)/steam_api.dll", "\(dir)/steam_api.dll")]
        }

        var deployedAny = false
        for (src, dst) in goldbergDlls {
            guard fm.fileExists(atPath: src) else { continue }
            if fm.fileExists(atPath: dst) && !fm.fileExists(atPath: "\(dst).lutrisbak") {
                try fm.moveItem(atPath: dst, toPath: "\(dst).lutrisbak")
            }
            try? fm.removeItem(atPath: dst)
            try fm.copyItem(atPath: src, toPath: dst)
            deployedAny = true
        }
        guard deployedAny else {
            throw SteamEmuError.setupFailed("Goldberg DLL nicht gefunden: \(goldbergDlls.map(\.0).joined(separator: ", "))")
        }

        // steam_settings
        let settingsDir = "\(dir)/steam_settings"
        try fm.createDirectory(atPath: settingsDir, withIntermediateDirectories: true)
        let configPath = "\(settingsDir)/configs.main"
        if !fm.fileExists(atPath: configPath) {
            try steamID.write(toFile: configPath, atomically: true, encoding: .utf8)
        }
        if let accountName = sessionAccountName {
            try accountName.write(toFile: "\(settingsDir)/account_name.txt", atomically: true, encoding: .utf8)
        }
        if let cookie = sessionCookie {
            try cookie.write(toFile: "\(settingsDir)/session.txt", atomically: true, encoding: .utf8)
        }
        let ticketDir = "\(settingsDir)/ownership_tickets"
        try fm.createDirectory(atPath: ticketDir, withIntermediateDirectories: true)
        let ticketPath = "\(ticketDir)/\(steamID).bin"
        if !fm.fileExists(atPath: ticketPath) {
            if let ticket = try? await downloadOwnershipTicket(appID: steamID) {
                try ticket.write(to: URL(fileURLWithPath: ticketPath))
            }
        }
    }

    /// Wendet Steamless + Goldberg Emulator auf das Spiel an (vor dem Start)
    /// Gibt die modifizierte exe zurück (falls sich der Name geändert hat)
    func applyEmulator(game: Game) async throws -> String {
        guard game.steamEmulatorEnabled == true,
              let steamID = game.steamAppID, !steamID.isEmpty else {
            return game.installPath
        }

        let exePath = game.installPath
        guard fm.fileExists(atPath: exePath) else {
            throw SteamEmuError.setupFailed("Exe nicht gefunden: \(exePath)")
        }
        guard let wine = wineBinary(for: game) else {
            throw SteamEmuError.setupFailed("Kein Wine-Binary gefunden (CrossOver, Whisky, Homebrew oder Gcenx nötig)")
        }

        let dir = (exePath as NSString).deletingLastPathComponent
        let exeName = (exePath as NSString).lastPathComponent
        let backupPath = "\(exePath).lutrisbak"

        // 1. Backup original exe
        if !fm.fileExists(atPath: backupPath) {
            try fm.copyItem(atPath: exePath, toPath: backupPath)
        }

        // 2. Steamless ausführen (nicht zwingend nötig – Goldberg reicht oft)
        if isSteamlessDownloaded {
            let winePath = winePathToWindows(exePath)

            let mgr = WineManager.shared
            let prefix = mgr.prefixForGame(game)
            var wineEnv = mgr.wineEnvironment(for: game, prefix: prefix)
            wineEnv.merge(ProcessInfo.processInfo.environment) { current, _ in current }
            if let p = prefix {
                let bottleName = URL(fileURLWithPath: p.path).lastPathComponent
                wineEnv["CX_BOTTLE"] = bottleName
            }

            let steamlessCmd = "\(wine) \"\(steamlessURL.path)\" --keep-exe true \"\(winePath)\""
            if let steamlessResult = try? await ProcessRunner.run(command: steamlessCmd, currentDirectory: nil, environment: wineEnv),
               steamlessResult.contains("success") || steamlessResult.contains("Success") {
                let unpacked = "\(dir)/\(exeName).unpacked.exe"
                if fm.fileExists(atPath: unpacked) {
                    try fm.moveItem(atPath: exePath, toPath: "\(exePath).original")
                    try fm.moveItem(atPath: unpacked, toPath: exePath)
                }
            }
        }

        // 3. Goldberg Emulator DLLs deployen
        guard isGoldbergDownloaded else {
            throw SteamEmuError.goldbergMissing
        }

        let goldbergDlls: [(src: String, dst: String)]
        let is64Bit = exePath.lowercased().contains("_64") ||
                      detectPEArch(exePath: exePath) == "x64"
        if is64Bit {
            goldbergDlls = [
                ("\(goldbergDir.path)/steam_api64.dll", "\(dir)/steam_api64.dll"),
            ]
        } else {
            goldbergDlls = [
                ("\(goldbergDir.path)/steam_api.dll", "\(dir)/steam_api.dll"),
            ]
        }

        var deployedAny = false
        for (src, dst) in goldbergDlls {
            guard fm.fileExists(atPath: src) else { continue }
            if fm.fileExists(atPath: dst) && !fm.fileExists(atPath: "\(dst).lutrisbak") {
                try fm.moveItem(atPath: dst, toPath: "\(dst).lutrisbak")
            }
            try? fm.removeItem(atPath: dst)
            try fm.copyItem(atPath: src, toPath: dst)
            deployedAny = true
        }
        guard deployedAny else {
            throw SteamEmuError.setupFailed("Goldberg DLL nicht gefunden: \(goldbergDlls.map(\.0).joined(separator: ", "))")
        }

        // steam_settings anlegen
        let settingsDir = "\(dir)/steam_settings"
        try fm.createDirectory(atPath: settingsDir, withIntermediateDirectories: true)
        let configPath = "\(settingsDir)/configs.main"
        if !fm.fileExists(atPath: configPath) {
            try steamID.write(toFile: configPath, atomically: true, encoding: .utf8)
        }

        // Session-Dateien für Goldberg deployen (Account-Name + Cookie)
        if let accountName = sessionAccountName {
            try accountName.write(toFile: "\(settingsDir)/account_name.txt", atomically: true, encoding: .utf8)
        }
        if let cookie = sessionCookie {
            try cookie.write(toFile: "\(settingsDir)/session.txt", atomically: true, encoding: .utf8)
        }

        // Ownership-Ticket für diese AppID deployen (falls vorhanden)
        let ticketDir = "\(settingsDir)/ownership_tickets"
        try fm.createDirectory(atPath: ticketDir, withIntermediateDirectories: true)
        let ticketPath = "\(ticketDir)/\(steamID).bin"
        if !fm.fileExists(atPath: ticketPath) {
            if let ticket = try? await downloadOwnershipTicket(appID: steamID) {
                try ticket.write(to: URL(fileURLWithPath: ticketPath))
            }
        }

        return exePath
    }

    /// Entfernt nur den Injektor (Goldberg-DLLs + steam_settings) aus dem Spielverzeichnis.
    /// Die Spiel-Exe wird nicht angetastet – nur die injected-Dateien.
    func removeInjector(game: Game) {
        let exePath = game.installPath
        let dir = (exePath as NSString).deletingLastPathComponent

        // Goldberg-DLLs entfernen und Backup wiederherstellen
        for dll in ["steam_api.dll", "steam_api64.dll"] {
            let dllPath = "\(dir)/\(dll)"
            let dllBak = "\(dllPath).lutrisbak"
            try? fm.removeItem(atPath: dllPath)
            if fm.fileExists(atPath: dllBak) {
                try? fm.moveItem(atPath: dllBak, toPath: dllPath)
            }
        }

        // steam_settings entfernen
        try? fm.removeItem(atPath: "\(dir)/steam_settings")
    }

    /// Stellt den Original-Zustand nach dem Spielende wieder her
    func restoreBackup(game: Game) {
        let exePath = game.installPath
        let dir = (exePath as NSString).deletingLastPathComponent
        let backupPath = "\(exePath).lutrisbak"
        let originalPath = "\(exePath).original"

        // Goldberg-DLLs entfernen
        let dllFiles = ["steam_api.dll", "steam_api64.dll"]
        for dll in dllFiles {
            let dllPath = "\(dir)/\(dll)"
            let dllBak = "\(dllPath).lutrisbak"
            try? fm.removeItem(atPath: dllPath)
            if fm.fileExists(atPath: dllBak) {
                try? fm.moveItem(atPath: dllBak, toPath: dllPath)
            }
        }

        // steam_settings entfernen
        try? fm.removeItem(atPath: "\(dir)/steam_settings")

        // Original exe wiederherstellen
        try? fm.removeItem(atPath: originalPath)
        if fm.fileExists(atPath: backupPath) {
            try? fm.removeItem(atPath: exePath)
            try? fm.moveItem(atPath: backupPath, toPath: exePath)
        }
    }

    // MARK: - Hilfsfunktionen

    /// Lädt das Ownership-Ticket von Steam herunter (optional, nur für manche Spiele nötig)
    private func downloadOwnershipTicket(appID: String) async throws -> Data? {
        guard let cookie = sessionCookie,
              let steam64ID = sessionSteamID,
              let apiKey = UserDefaults.standard.string(forKey: "steamGridDBApiKey"),
              !apiKey.isEmpty else { return nil }

        let urlStr = "https://api.steampowered.com/ISteamClient/GetOwnershipTicket/v1/?key=\(apiKey)&appid=\(appID)&steamid=\(steam64ID)&tickettype=1"
        guard let url = URL(string: urlStr) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("steamLoginSecure=\(cookie)", forHTTPHeaderField: "Cookie")
        request.httpMethod = "POST"

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResp = response as? HTTPURLResponse,
              httpResp.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resp = json["response"] as? [String: Any],
              let ticketBase64 = resp["ticket"] as? String else { return nil }

        return Data(base64Encoded: ticketBase64)
    }

    private func download(url: URL, to destination: URL) async throws {
        let (data, _) = try await session.data(from: url)
        await MainActor.run { downloadProgress = nil }
        try data.write(to: destination, options: .atomic)
    }

    private func unzip(zipPath: URL, to destination: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipPath.path, "-d", destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SteamEmuError.unzipFailed
        }
    }

    /// Sucht rekursiv in einem Verzeichnis nach Dateien mit bestimmten Namen (synchron, nicht-async-safe)
    private func findFiles(named targets: Set<String>, in directory: URL) -> [URL] {
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: nil) else { return [] }
        var results: [URL] = []
        for case let file as URL in enumerator {
            if targets.contains(file.lastPathComponent) {
                results.append(file)
            }
        }
        return results
    }

    /// Wandelt macOS-Pfad in Wine-Z-Pfad um
    private func winePathToWindows(_ path: String) -> String {
        let components = path.components(separatedBy: "/").filter { !$0.isEmpty }
        guard let volume = components.first else { return "Z:\\" }
        let rest = components.dropFirst().joined(separator: "\\")
        return "\(volume.uppercased()):\\\(rest)"
    }

    /// Erkennt die PE-Architektur (vereinfacht)
    private func detectPEArch(exePath: String) -> String {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: exePath), options: .mappedIfSafe),
              data.count > 2 else { return "x86" }
        // PE-Offset bei 0x3C
        let peOffset: Int
        if data.count > 0x3C + 4 {
            peOffset = Int(data[0x3C]) | (Int(data[0x3D]) << 8) | (Int(data[0x3E]) << 16) | (Int(data[0x3F]) << 24)
        } else {
            return "x86"
        }
        guard data.count > peOffset + 6 else { return "x86" }
        let machine = Int(data[peOffset + 4]) | (Int(data[peOffset + 5]) << 8)
        // 0x8664 = AMD64, 0x14C = I386
        return machine == 0x8664 ? "x64" : "x86"
    }
}

enum SteamEmuError: LocalizedError {
    case invalidURL
    case setupFailed(String)
    case steamlessMissing
    case goldbergMissing
    case steamlessFailed(String)
    case unzipFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Ungültige Download-URL"
        case .setupFailed(let detail): return "Setup fehlgeschlagen – \(detail)"
        case .steamlessMissing: return "Steamless nicht gefunden – bitte Tools herunterladen"
        case .goldbergMissing: return "Goldberg Emulator nicht gefunden – bitte Tools herunterladen"
        case .steamlessFailed(let msg): return "Steamless fehlgeschlagen: \(msg)"
        case .unzipFailed: return "Entpacken fehlgeschlagen"
        }
    }
}
