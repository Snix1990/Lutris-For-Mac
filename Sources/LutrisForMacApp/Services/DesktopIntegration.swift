import Foundation
import AppKit
import ServiceManagement

final class DesktopIntegrationManager: ObservableObject {
    static let shared = DesktopIntegrationManager()

    @Published var discordEnabled: Bool {
        didSet {
            UserDefaults.standard.set(discordEnabled, forKey: "discordRPCEnabled")
            if discordEnabled {
                startDiscordRPC()
            } else {
                stopDiscordRPC()
            }
        }
    }
    @Published var launchAtLogin: Bool {
        didSet { updateLoginItem() }
    }

    private var discordRPC: DiscordRPC?

    private init() {
        discordEnabled = UserDefaults.standard.bool(forKey: "discordRPCEnabled")
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if discordEnabled {
            startDiscordRPC()
        }
    }

    // MARK: - Shortcuts

    private var shortcutsDirectory: String {
        "\(NSHomeDirectory())/Applications/Lutris"
    }

    @MainActor
    func createShortcut(game: Game) -> Bool {
        let bundlePath = "\(shortcutsDirectory)/\(sanitizedFilename(game.name)).app"
        let fm = FileManager.default

        try? fm.createDirectory(atPath: shortcutsDirectory, withIntermediateDirectories: true)
        try? fm.removeItem(atPath: bundlePath)

        let contents = "\(bundlePath)/Contents"
        let macosDir = "\(contents)/MacOS"
        let resourcesDir = "\(contents)/Resources"
        try? fm.createDirectory(atPath: macosDir, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: resourcesDir, withIntermediateDirectories: true)

        let scriptContent = buildLauncherScript(for: game)
        let scriptPath = "\(macosDir)/launcher"
        try? scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)

        var infoPlist: [String: Any] = [
            "CFBundleExecutable": "launcher",
            "CFBundleIdentifier": "net.lutrisformac.shortcut.\(game.id.uuidString.prefix(8))",
            "CFBundleName": game.name,
            "CFBundleDisplayName": game.name,
            "CFBundlePackageType": "APPL",
            "LSUIElement": true,
        ]

        setIcon(for: game, bundlePath: bundlePath, resourcesDir: resourcesDir)
        if let iconName = iconName {
            infoPlist["CFBundleIconFile"] = iconName
        }

        guard let plistData = try? PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0),
              let _ = try? plistData.write(to: URL(fileURLWithPath: "\(contents)/Info.plist")) else {
            return false
        }

        return fm.fileExists(atPath: bundlePath)
    }

    private var runtimeBinaryPath: String {
        Bundle.main.executableURL?.path ?? ""
    }

    @MainActor
    private func runtimeScriptBlock(for game: Game) -> String {
        let info = RuntimeGameInfo(
            gameID: game.id.uuidString,
            gameName: game.name,
            coverURL: game.coverURL,
            installPath: game.installPath,
            runner: game.runner,
            runtimeSettings: game.runtimeSettings
        )
        let jsonData = (try? JSONEncoder().encode(info)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return """
        # Starte LutrisForMac Runtime (OSD + Hotkeys)
        LOG=/tmp/lutris_runtime_debug.log
        echo "[$(date)] Starte Runtime" >> "$LOG"
        echo "[$(date)] Binary: \(runtimeBinaryPath)" >> "$LOG"
        if [ ! -x "\(runtimeBinaryPath)" ]; then
            echo "[$(date)] FEHLER: Binary nicht gefunden: \(runtimeBinaryPath)" >> "$LOG"
        fi
        cat > /tmp/lutris_runtime_game.json << 'LUTRIS_GAME_EOF'
        \(jsonData)
        LUTRIS_GAME_EOF
        nohup "\(runtimeBinaryPath)" --runtime >> "$LOG" 2>&1 &
        RUNTIME_PID=$!
        echo "[$(date)] Runtime PID: $RUNTIME_PID" >> "$LOG"
        disown $RUNTIME_PID 2>/dev/null
        sleep 0.3

        """
    }

    @MainActor
    private func buildLauncherScript(for game: Game) -> String {
        let isWine = game.runner == "Wine" || game.runner == "CrossOver" || game.runner == "Whisky" || game.runner == "Kegworks"
        let isNative = game.runner == "Native" || game.platform == "macOS"
        let isEmulator = !isWine && !isNative && RunnerManager.shared.runners.contains(where: { $0.name == game.runner && $0.installed })

        // === Native .app ===
        if isNative || game.installPath.hasSuffix(".app") {
            return """
            #!/bin/bash
            \(runtimeScriptBlock(for: game))open "\(game.installPath)"
            """
        }

        // === Emulator runners ===
        if isEmulator {
            let runner = RunnerManager.shared.runners.first(where: { $0.name == game.runner })
            let cmd = emulatorLaunchCommand(for: game, runner: runner)
            return """
            #!/bin/bash
            \(runtimeScriptBlock(for: game))\(cmd)
            """
        }

        // === URL schemes (steam://, etc.) ===
        if game.installPath.contains("://") {
            return """
            #!/bin/bash
            \(runtimeScriptBlock(for: game))open "\(game.installPath)"
            """
        }

        // === Wine / CrossOver / Whisky / Kegworks ===
        let wineManager = WineManager.shared
        let wineVersion = wineManager.resolveWineVersion(for: game.wineVersionName)
        let prefix = wineManager.prefixForGame(game)

        var envLines: [String] = []
        let gameEnv: [String: String]
        if game.runner == "CrossOver" {
            var env = wineManager.wineEnvironment(for: game, prefix: prefix, wineVersion: wineVersion)
            if let p = prefix {
                let bottleName = URL(fileURLWithPath: p.path).lastPathComponent
                env["CX_BOTTLE"] = bottleName
            }
            gameEnv = env
        } else {
            gameEnv = wineManager.wineEnvironment(for: game, prefix: prefix, wineVersion: wineVersion)
        }

        let customEnv = ProcessRunner.parseEnvironmentVariables(from: game.environmentVariables)
        let merged = gameEnv.merging(customEnv) { _, new in new }

        let sortedKeys = merged.keys.sorted()
        for key in sortedKeys {
            let val = merged[key]!
            if val.contains(" ") || val.contains("\"") || val.contains("'") || val.contains("$") || val.contains("`") || val.contains("\\") {
                envLines.append("export \(key)=\"\(val.replacingOccurrences(of: "\"", with: "\\\""))\"")
            } else {
                envLines.append("export \(key)=\(val)")
            }
        }

        let envBlock = envLines.joined(separator: "\n")

        let wineBinary = wineVersion?.wineBinaryPath ?? ""
        let prefixPath = prefix?.path ?? ""
        let installPath = game.installPath
        let launchArgs = game.wineLaunchArguments

        let steamID = game.steamAppID ?? ""
        let launchViaSteam = game.launchViaSteam == true && !steamID.isEmpty

        // Launcher command with template substitution
        let launcherCommand: String
        if game.launcherCommand.isEmpty {
            launcherCommand = ""
        } else {
            launcherCommand = game.launcherCommand
                .replacingOccurrences(of: "{gamePath}", with: installPath)
                .replacingOccurrences(of: "{wineBinary}", with: wineBinary)
        }

        // Wine binary nicht gefunden → Fehlermeldung statt Lutris-URL-Scheme
        guard !wineBinary.isEmpty, FileManager.default.isExecutableFile(atPath: wineBinary) else {
            return """
            #!/bin/bash
            echo "Fehler: Keine Wine-Version für '\(game.name)' gefunden."
            echo "Öffne LutrisForMac, lade eine Wine-Version herunter und erstelle den Shortcut neu."
            exit 1
            """
        }

        // Benutzerdefinierter Launcher-Befehl
        if !launcherCommand.isEmpty {
            return """
            #!/bin/bash
            # === LutrisForMac Launcher: '\(game.name)' ===
            \(runtimeScriptBlock(for: game))\(envBlock)

            exec \(launcherCommand)
            """
        }

        // Launch via Steam (-applaunch)
        if launchViaSteam {
            let steamBlock: String
            if !prefixPath.isEmpty {
                steamBlock = """
                STEAM_EXE=$(find "\(prefixPath)/drive_c" -maxdepth 4 -name "steam.exe" -type f 2>/dev/null | head -1)
                if [ -n "$STEAM_EXE" ]; then
                    exec "\(wineBinary)" \(launchArgs) "$STEAM_EXE" -applaunch \(steamID)
                else
                    exec "\(wineBinary)" \(launchArgs) -applaunch \(steamID)
                fi
                """
            } else {
                steamBlock = "exec \"\(wineBinary)\" \(launchArgs) -applaunch \(steamID)"
            }
            return """
            #!/bin/bash
            # === LutrisForMac Launcher: '\(game.name)' ===
            \(runtimeScriptBlock(for: game))\(envBlock)
            \(steamBlock)
            """
        }

        // Standard Wine launch mit exe-Autoerkennung
        let exeFallback: String
        if !prefixPath.isEmpty {
            exeFallback = """
            if [ ! -f "$INSTALL_PATH" ] && [ -d "\(prefixPath)/drive_c" ]; then
                FOUND=$(find "\(prefixPath)/drive_c" -type f -name "*.exe" 2>/dev/null \\
                    -not -iname "*unins*" -not -iname "*setup*" -not -iname "*redist*" \\
                    -not -iname "*dotnet*" -not -iname "*vc_redist*" \\
                    -exec ls -1S {} + 2>/dev/null | head -1)
                [ -n "$FOUND" ] && INSTALL_PATH="$FOUND"
            fi
            """
        } else {
            exeFallback = ""
        }

        return """
        #!/bin/bash
        # === LutrisForMac Launcher: '\(game.name)' ===
        \(runtimeScriptBlock(for: game))INSTALL_PATH="\(installPath)"
        \(envBlock)
        \(exeFallback)
        if [ ! -f "$INSTALL_PATH" ]; then
            echo "Fehler: Installationspfad nicht gefunden: $INSTALL_PATH"
            echo "Öffne LutrisForMac und aktualisiere den Pfad für '\(game.name)'."
            exit 1
        fi
        exec "\(wineBinary)" \(launchArgs) "$INSTALL_PATH"
        """
    }

    @MainActor
    private func emulatorLaunchCommand(for game: Game, runner: Runner?) -> String {
        guard let runner else {
            return "open \"\(game.installPath)\""
        }
        let installPath = game.installPath
        let binPath = runner.binaryPath.isEmpty ? runner.installPath : runner.binaryPath
        let config = game.runnerConfig

        switch runner.launchTemplate {
        case .cli(let template):
            return template
                .replacingOccurrences(of: "{gamePath}", with: installPath)
                .replacingOccurrences(of: "{runnerPath}", with: binPath)
                .replacingOccurrences(of: "{runnerDir}", with: runner.installPath)
        case .dosbox:
            let bin = runner.binaryPath.isEmpty ? "/Applications/DOSBox.app/Contents/MacOS/DOSBox" : runner.binaryPath
            let conf = config["dosbox_conf"] ?? ""
            return conf.isEmpty ? "\"\(bin)\" \"\(installPath)\"" : "\"\(bin)\" -conf \"\(conf)\" \"\(installPath)\""
        case .scummvm:
            let bin = runner.binaryPath.isEmpty ? "/Applications/ScummVM.app/Contents/MacOS/scummvm" : runner.binaryPath
            let gameID = config["scummvm_game_id"] ?? ""
            return gameID.isEmpty ? "\"\(bin)\" \"\(installPath)\"" : "\"\(bin)\" --path=\"\(installPath)\" \"\(gameID)\""
        case .mame:
            let bin = runner.binaryPath.isEmpty ? "/Applications/MAME.app/Contents/MacOS/mame" : runner.binaryPath
            let rom = config["mame_rom"] ?? installPath
            return "\"\(bin)\" \"\(rom)\""
        case .retroarch:
            let bin = runner.binaryPath.isEmpty ? "/Applications/RetroArch.app/Contents/MacOS/RetroArch" : runner.binaryPath
            let core = config["retroarch_core"] ?? ""
            return core.isEmpty ? "\"\(bin)\" \"\(installPath)\"" : "\"\(bin)\" -L \"\(core)\" \"\(installPath)\""
        case .wine(let binary):
            let wineBin = runner.binaryPath.isEmpty ? binary : runner.binaryPath
            return "\"\(wineBin)\" \"\(installPath)\""
        case .nativeApp:
            return "open \"\(installPath)\""
        case .custom:
            return "\"\(binPath)\" \"\(installPath)\""
        }
    }

    private var iconName: String?

    @MainActor
    private func setIcon(for game: Game, bundlePath: String, resourcesDir: String) {
        let media = MediaStore.shared
        let gameID = game.id.uuidString
        guard let image = media.cachedImage(for: gameID, type: .icon)
                ?? media.cachedImage(for: gameID, type: .cover)
                ?? media.cachedImage(for: gameID, type: .banner) else { return }

        // .icns im Resources-Ordner anlegen
        let icnsPath = "\(resourcesDir)/gameicon.icns"
        if createICNS(from: image, at: icnsPath) {
            iconName = "gameicon"
            return
        }

        // Fallback: NSWorkspace.setIcon auf das .app-Bundle
        NSWorkspace.shared.setIcon(image, forFile: bundlePath, options: [])
    }

    private func createICNS(from image: NSImage, at path: String) -> Bool {
        let tmpDir = "\(NSTemporaryDirectory())gameicon_\(UUID().uuidString).iconset"
        let fm = FileManager.default
        try? fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)

        let sizes: [(name: String, size: CGFloat)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32),
            ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256),
            ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512),
        ]

        for (name, size) in sizes {
            guard let rep = image.bestRepresentation(for: NSRect(x: 0, y: 0, width: size, height: size), context: nil, hints: nil),
                  let cgImage = rep.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let bitmap = NSImage(size: NSSize(width: size, height: size))
            bitmap.lockFocus()
            guard let ctx = NSGraphicsContext.current else { bitmap.unlockFocus(); continue }
            ctx.cgContext.interpolationQuality = .high
            ctx.cgContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
            bitmap.unlockFocus()
            guard let tiffData = bitmap.tiffRepresentation,
                  let rep2 = NSBitmapImageRep(data: tiffData),
                  let pngData = rep2.representation(using: .png, properties: [:]) else { continue }
            try? pngData.write(to: URL(fileURLWithPath: "\(tmpDir)/\(name).png"))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", tmpDir, "-o", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        process.waitUntilExit()

        try? fm.removeItem(atPath: tmpDir)
        return process.terminationStatus == 0 && fm.fileExists(atPath: path)
    }

    func removeShortcut(game: Game) {
        let bundlePath = "\(shortcutsDirectory)/\(sanitizedFilename(game.name)).app"
        try? FileManager.default.removeItem(atPath: bundlePath)
    }

    func shortcutExists(game: Game) -> Bool {
        FileManager.default.fileExists(atPath: "\(shortcutsDirectory)/\(sanitizedFilename(game.name)).app")
    }

    private func sanitizedFilename(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: ".-_()[] "))
        return name.unicodeScalars.filter { allowed.contains($0) }.map(String.init).joined().trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Login Item

    private func updateLoginItem() {
        if launchAtLogin {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }

    // MARK: - Discord RPC

    func startDiscordRPC() {
        guard discordEnabled else { return }
        discordRPC = DiscordRPC()
        discordRPC?.connect()
    }

    func stopDiscordRPC() {
        discordRPC?.disconnect()
        discordRPC = nil
    }

    func updateDiscordPresence(gameName: String, state: String = "Spielt", coverURL: String = "") {
        guard discordEnabled, let rpc = discordRPC else { return }
        rpc.setActivity(
            details: gameName,
            state: state,
            coverURL: coverURL
        )
        NotificationManager.info(
            title: "Discord RPC",
            message: "Now playing: \(gameName)",
            duration: 3
        )
    }

    func clearDiscordPresence() {
        guard discordEnabled, discordRPC != nil else { return }
        discordRPC?.clearActivity()
        NotificationManager.info(
            title: "Discord RPC",
            message: "Stopped playing",
            duration: 3
        )
    }

    // MARK: - Game Process Monitoring (deprecated – use GameSessionManager instead)

    /// Old-style single-process wait (kept for backward compat). Redirects to GameSessionManager.
    /// For new code use `launchSession()` from the GameSessionManager extension.
    static func waitForGameProcess(exePath: String) async {
        let exeName = (exePath as NSString).lastPathComponent
        guard !exeName.isEmpty else { return }

        await MainActor.run {
            _ = GameSessionManager.shared.startSession(
                gameID: UUID(),
                gameName: exeName,
                coverURL: "",
                names: [exeName]
            )
        }

        // Block until session ends (polling every 2s, max 2 hours)
        let deadline = Date().addingTimeInterval(7200)
        while Date() < deadline {
            let active = await MainActor.run {
                GameSessionManager.shared.activeSessions.contains(where: {
                    $0.watchedNames.contains(exeName) || $0.watchedPIDs.contains(where: { kill($0, 0) == 0 })
                })
            }
            guard active else { break }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        await MainActor.run {
            GameSessionManager.shared.endAllSessions()
            DesktopIntegrationManager.shared.clearDiscordPresence()
        }
    }
}

// MARK: - Discord RCP (einfacher IPC-Client)

final class DiscordRPC {
    private var socket: Int32 = -1
    private var connected = false
    private let clientID = "1510094522833703003"
    private let queue = DispatchQueue(label: "discord-rpc")

    func connect() {
        let possiblePaths = possibleSocketPaths()
        guard let socketPath = possiblePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            #if DEBUG
            print("Discord RPC-Socket nicht gefunden. Geprüft: \(possiblePaths)")
            #endif
            return
        }

        socketPath.withCString { path in
            socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard socket >= 0 else { return }

            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            strcpy(&addr.sun_path, path)

            let len = socklen_t(MemoryLayout<sockaddr_un>.size)
            let result = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(socket, $0, len)
                }
            }

            if result == 0 {
                connected = true
                #if DEBUG
                print("Discord RPC verbunden (\(socketPath))")
                #endif
                // Handshake mit client_id
                let handshake: [String: Any] = [
                    "v": 1,
                    "client_id": clientID,
                ]
                send(frame: .handshake, json: handshake)
                // Read loop
                queue.async { [weak self] in self?.readLoop() }
            } else {
                #if DEBUG
                print("Discord RPC connect fehlgeschlagen: \(String(cString: strerror(errno)))")
                #endif
            }
        }
    }

    private func possibleSocketPaths() -> [String] {
        var paths: [String] = []
        let candidates = [
            ProcessInfo.processInfo.environment["XDG_RUNTIME_DIR"],
            ProcessInfo.processInfo.environment["TMPDIR"],
            ProcessInfo.processInfo.environment["TMP"],
            ProcessInfo.processInfo.environment["TEMP"],
        ]
        for candidate in candidates {
            if let dir = candidate {
                for i in 0..<10 {
                    paths.append("\(dir)/discord-ipc-\(i)")
                }
            }
        }
        for i in 0..<10 {
            paths.append("/tmp/discord-ipc-\(i)")
        }
        // Legacy path
        for i in 0..<10 {
            paths.append("\(NSHomeDirectory())/Library/Application Support/discord/rpc/discord-ipc-\(i)")
        }
        return paths
    }

    func disconnect() {
        connected = false
        if socket >= 0 {
            close(socket)
            socket = -1
        }
    }

    func setActivity(details: String, state: String, coverURL: String = "") {
        var assets: [String: String]?
        if coverURL.hasPrefix("http"), let url = URL(string: coverURL) {
            assets = ["large_image": url.absoluteString, "large_text": details]
        }

        var activity: [String: Any] = [
            "name": details,
            "details": "via LutrisForMac",
            "state": state,
            "timestamps": [
                "start": Int(Date().timeIntervalSince1970 * 1000)
            ],
            "instance": false,
        ]
        if let assets {
            activity["assets"] = assets
        }

        let payload: [String: Any] = [
            "cmd": "SET_ACTIVITY",
            "args": [
                "pid": ProcessInfo.processInfo.processIdentifier,
                "activity": activity,
            ] as [String: Any],
            "nonce": UUID().uuidString,
        ] as [String: Any]
        send(json: payload)
    }

    func clearActivity() {
        let clear: [String: Any] = [
            "cmd": "SET_ACTIVITY",
            "args": [
                "pid": ProcessInfo.processInfo.processIdentifier,
                "activity": NSNull(),
            ],
            "nonce": UUID().uuidString,
        ]
        send(json: clear)
    }

    // MARK: - IPC

    private enum Opcode: UInt32 {
        case handshake = 0
        case frame = 1
        case close = 2
        case ping = 3
        case pong = 4
    }

    private struct IPCFrame {
        let opcode: UInt32
        let length: UInt32
    }

    private func send(frame opcode: Opcode, json: [String: Any]? = nil) {
        guard socket >= 0 else { return }

        var data = Data()
        if let json {
            data = try! JSONSerialization.data(withJSONObject: json)
        }

        var header = IPCFrame(opcode: opcode.rawValue, length: UInt32(data.count))
        let headerData = Data(bytes: &header, count: MemoryLayout<IPCFrame>.size)

        var combined = Data()
        combined.append(headerData)
        combined.append(data)

        _ = combined.withUnsafeBytes { ptr in
            Darwin.write(socket, ptr.baseAddress, combined.count)
        }
    }

    private func send(json: [String: Any]) {
        send(frame: .frame, json: json)
    }

    private func readLoop() {
        var header = IPCFrame(opcode: 0, length: 0)
        while connected {
            let headerSize = MemoryLayout<IPCFrame>.size
            let n = read(socket, &header, headerSize)
            guard n == headerSize else { break }

            if header.length > 0 {
                var jsonData = Data(count: Int(header.length))
                jsonData.withUnsafeMutableBytes { ptr in
                    _ = read(socket, ptr.baseAddress, Int(header.length))
                }
                if let response = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    DispatchQueue.main.async {
                        self.handleResponse(response)
                    }
                }
            }
        }
    }

    private func handleResponse(_ response: [String: Any]) {
        if let cmd = response["cmd"] as? String {
            switch cmd {
            case "DISPATCH":
                if let evt = response["evt"] as? String, evt == "READY" {
                    #if DEBUG
                    print("Discord RPC bereit")
                    #endif
                }
            case "PING":
                send(frame: .pong, json: response)
            default:
                break
            }
        }
    }
}
