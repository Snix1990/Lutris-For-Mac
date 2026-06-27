import SwiftUI

@main
struct LutrisForMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var lang = LanguageManager.shared
    @StateObject private var viewModel = GameLibraryViewModel.shared
    @StateObject private var wineManager = WineManager.shared
    @StateObject private var runnerManager = RunnerManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel, wineManager: wineManager, runnerManager: runnerManager)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    _ = LanguageManager.shared
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .windowResizability(.contentMinSize)
            .commands {
                CommandMenu("Library") {
                    Button("Refresh Library") {
                        viewModel.refreshLibrary()
                    }
                    .keyboardShortcut(Keybinds.shortcut(for: .refreshLibrary).key, modifiers: Keybinds.shortcut(for: .refreshLibrary).modifiers)

                    Divider()

                    Button("Alle scannen") {
                        Task {
                            let folders = RomFolderManager.shared.folders
                            guard !folders.isEmpty else { return }
                            let results = RomFolderManager.shared.scanROMs()
                            let total = results.values.reduce(0) { $0 + $1.count }

                            let alert = NSAlert()
                            if total == 0 {
                                alert.messageText = tr("Keine ROMs gefunden")
                                alert.informativeText = tr("In den konfigurierten Ordnern wurden keine ROM-Dateien gefunden.")
                                alert.addButton(withTitle: tr("OK"))
                                alert.runModal()
                            } else {
                                let platforms = results.keys.sorted().joined(separator: ", ")
                                alert.messageText = tr("Scan abgeschlossen")
                                alert.informativeText = "\(total) ROMs gefunden"
                                if !platforms.isEmpty {
                                    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 380, height: 120))
                                    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 120))
                                    textView.isEditable = false
                                    textView.string = platforms
                                    scrollView.documentView = textView
                                    scrollView.hasVerticalScroller = true
                                    alert.accessoryView = scrollView
                                }
                                alert.addButton(withTitle: tr("Importieren"))
                                alert.addButton(withTitle: tr("Abbrechen"))

                                let response = alert.runModal()
                                guard response == .alertFirstButtonReturn else { return }

                                var imported = 0
                                for (platform, files) in results {
                                    for url in files {
                                        let name = url.deletingPathExtension().lastPathComponent
                                        let game = Game(
                                            name: name,
                                            platform: platform,
                                            installPath: url.path,
                                            runner: "RetroArch"
                                        )
                                        if !viewModel.games.contains(where: { $0.installPath == url.path }) {
                                            viewModel.games.append(game)
                                            imported += 1
                                        }
                                    }
                                }
                                if imported > 0 {
                                    viewModel.saveLibrary()
                                }
                            }
                        }
                    }
                    .keyboardShortcut(Keybinds.shortcut(for: .scanROMs).key, modifiers: Keybinds.shortcut(for: .scanROMs).modifiers)
                    .disabled(RomFolderManager.shared.folders.isEmpty)

                    Divider()

                    Button("OSD") {
                        OSDManager.shared.toggle()
                    }
                    .keyboardShortcut(Keybinds.shortcut(for: .toggleOSD).key, modifiers: Keybinds.shortcut(for: .toggleOSD).modifiers)

                    Button("Maus freigeben") {
                        OSDManager.shared.requestInteraction()
                    }
                    .keyboardShortcut(Keybinds.shortcut(for: .releaseMouse).key, modifiers: Keybinds.shortcut(for: .releaseMouse).modifiers)
                }

                WineMenuCommands(wineManager: wineManager)
                ConsoleMenuCommands()
                ControllerMenuCommands()
            }

        Settings {
            SettingsView()
        }

        WindowGroup(id: "add-game") {
            AddGameSelectionView(viewModel: viewModel)
                .id(lang.refreshID)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 520, height: 280)

        WindowGroup(id: "installer") {
            InstallerWindowView(viewModel: viewModel)
                .id(lang.refreshID)
        }
        .defaultSize(width: 460, height: 420)

        WindowGroup(id: "wine-settings") {
            WineSettingsView()
                .id(lang.refreshID)
        }
        .defaultSize(width: 760, height: 560)
        .windowResizability(.contentMinSize)
        .windowStyle(HiddenTitleBarWindowStyle())

        WindowGroup(id: "controller-settings") {
            ControllerSettingsView()
                .id(lang.refreshID)
        }
        .defaultSize(width: 620, height: 560)
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var idleTimer: Timer?
    private var observationTokens: [NSObjectProtocol] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--runtime") {
            NSApp.setActivationPolicy(.prohibited)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--runtime") {
            // Fenster schließen falls SwiftUI trotz .prohibited eines erstellt hat
            NSApp.windows.forEach { $0.close() }
            let logURL = URL(fileURLWithPath: "/tmp/lutris_runtime_app.log")
            try? "\(Date()) Runtime gestartet\n".write(to: logURL, atomically: true, encoding: .utf8)
            Task { @MainActor in
                startRuntimeSession()
            }
            OSDManager.installCarbonHandler()
            OSDManager.shared.registerGlobalHotkey()
            OSDManager.shared.touch()
            RuntimeManager.shared.startAll()
            startIdleTimer()
            #if DEBUG
            print("[Runtime] LutrisForMac läuft im Runtime-Modus (OSD + Hotkeys + Session)")
            #endif
            return
        }

        killOtherInstances(excluding: NSRunningApplication.current.processIdentifier)

        NSApplication.shared.setActivationPolicy(.regular)
        Task { await checkForUpdate() }
        OSDManager.installCarbonHandler()
        OSDManager.shared.registerGlobalHotkey()

    }


    private func runtimeLog(_ message: String) {
        let logURL = URL(fileURLWithPath: "/tmp/lutris_runtime_app.log")
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write("[\(Date())] \(message)\n".data(using: .utf8)!)
            try? handle.close()
        } else {
            try? "[\(Date())] \(message)\n".write(to: logURL, atomically: true, encoding: .utf8)
        }
    }

    @MainActor
    private func startRuntimeSession() {
        runtimeLog("startRuntimeSession() begin")
        let gameInfoURL = RuntimeGameInfo.tempFileURL
        guard let data = try? Data(contentsOf: gameInfoURL),
              let info = try? JSONDecoder().decode(RuntimeGameInfo.self, from: data) else {
            runtimeLog("FEHLER: Konnte RuntimeGameInfo nicht lesen/decoden")
            return
        }
        runtimeLog("Spiel: \(info.gameName), discordEnabled: \(info.discordEnabled)")
        try? FileManager.default.removeItem(at: gameInfoURL)

        // Discord RPC aus dem JSON aktivieren (UserDefaults des Hauptprozesses könnte noch stale sein)
        if info.discordEnabled && !DesktopIntegrationManager.shared.discordEnabled {
            runtimeLog("Setze discordEnabled=true vom JSON")
            DesktopIntegrationManager.shared.discordEnabled = true
        } else if !info.discordEnabled && DesktopIntegrationManager.shared.discordEnabled {
            runtimeLog("Setze discordEnabled=false vom JSON")
            DesktopIntegrationManager.shared.discordEnabled = false
        } else {
            runtimeLog("discordEnabled bereits korrekt: \(DesktopIntegrationManager.shared.discordEnabled)")
        }

        let gameID = UUID(uuidString: info.gameID) ?? UUID()
        let exeName = (info.installPath as NSString).lastPathComponent
        let installLower = info.installPath.lowercased()

        let names: [String] = {
            let isWine = info.runner == "Wine" || info.runner == "CrossOver" || info.runner == "Whisky" || info.runner == "Kegworks"
            if isWine {
                return [exeName, "wine", "wine64", "wine32on64"]
            }
            if installLower.hasSuffix(".app") {
                var result = [info.installPath]
                let appURL = URL(fileURLWithPath: info.installPath)
                let plistURLs = [
                    appURL.appendingPathComponent("Contents/Info.plist"),
                    appURL.appendingPathComponent("Info.plist")
                ]
                for plistURL in plistURLs {
                    if let plistData = try? Data(contentsOf: plistURL),
                       let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
                       let bundleExe = plist["CFBundleExecutable"] as? String {
                        result.append(bundleExe)
                        break
                    }
                }
                return result
            }
            if installLower.hasPrefix("steam://") {
                return ["steam", "Steam Helper"]
            }
            if installLower.contains("://") {
                return [exeName]
            }
            var result = [exeName]
            switch info.runner {
            case "Ryujinx": result.append("Ryujinx")
            case "Dolphin": result.append("Dolphin")
            case "PCSX2": result.append("PCSX2")
            case "RPCS3": result.append("RPCS3")
            case "Citra": result.append("Citra")
            case "MelonDS": result.append("melonDS")
            case "DuckStation": result.append("DuckStation")
            case "Flycast": result.append("Flycast")
            case "PPSSPP": result.append("PPSSPP")
            case "RetroArch": result.append("RetroArch")
            case "MAME": result.append("MAME")
            case "DOSBox", "DOSBox-X": result.append("DOSBox")
            default: break
            }
            return result
        }()

        runtimeLog("starte Session fuer '\(info.gameName)'...")
        let sid = GameSessionManager.shared.startSession(
            gameID: gameID,
            gameName: info.gameName,
            coverURL: info.coverURL,
            names: names,
            discordRPCEnabled: info.runtimeSettings.discordRPC
        )
        runtimeLog("Session gestartet: \(sid)")
        // Kurz warten, dann RPC-Status loggen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            let dim = DesktopIntegrationManager.shared
            self?.runtimeLog("RPC-Check – discordEnabled: \(dim.discordEnabled), discordRPC: \(dim.discordRPC != nil)")
        }

        // RuntimeSettings aus dem JSON respektieren
        let settings = info.runtimeSettings
        if settings.osdEnabled {
            OSDManager.shared.show()
        }
        // Health-Check (via Library-Lookup, weil checkHealth Game-Objekt braucht)
        if settings.healthCheck,
           let game = GameLibraryViewModel.shared.games.first(where: { $0.id == gameID }) {
            _ = RuntimeManager.shared.checkHealth(game: game)
        }

        observationTokens.append(
            NotificationCenter.default.addObserver(
                forName: .gameSessionEnded,
                object: nil,
                queue: .main
            ) { note in
                Task { @MainActor in
                    guard let userInfo = note.userInfo,
                          let endedGameID = userInfo["gameID"] as? UUID,
                          endedGameID == gameID else { return }
                    let playTime = userInfo["playTime"] as? TimeInterval ?? 0
                    if playTime > 10 {
                        GameLibraryViewModel.shared.recordPlaySession(gameID: gameID, duration: playTime)
                    }
                    NSApplication.shared.terminate(nil)
                }
            }
        )
    }

    private func startIdleTimer() {
        // Runtime läuft nur bis Session-Ende, kein Idle-Timeout
    }

    private func killOtherInstances(excluding currentPID: pid_t) {
        let exeName = Bundle.main.executableURL?.lastPathComponent ?? "LutrisForMac"
        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["-f", "\(exeName).*--runtime"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let pids = String(data: data, encoding: .utf8)?
            .split(separator: "\n")
            .compactMap { pid_t($0) }
            .filter { $0 != currentPID } ?? []

        for pid in pids {
            kill(pid, SIGTERM)
        }
    }

    private func checkForUpdate() async {
        guard let release = await UpdaterService.shared.checkForUpdate() else { return }

        await MainActor.run {
            let alert = NSAlert()
            alert.messageText = tr("Update verfügbar")
            alert.informativeText = String(format: tr("Version %@ ist verfügbar. Möchtest du es jetzt herunterladen?"), release.version)
            alert.addButton(withTitle: tr("Herunterladen"))
            alert.addButton(withTitle: tr("Später"))

            if let notes = release.releaseNotes, !notes.isEmpty {
                let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
                let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
                textView.isEditable = false
                textView.string = notes
                scrollView.documentView = textView
                scrollView.hasVerticalScroller = true
                alert.accessoryView = scrollView
            }

            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else { return }

            let repoURL = URL(string: "https://github.com/\(UpdaterService.shared.repoOwner)/\(UpdaterService.shared.repoName)/releases/latest")!

            if let downloadURL = release.downloadURL {
                Task {
                    do {
                        let fileURL = try await UpdaterService.shared.downloadAndInstall(at: downloadURL)
                        NSWorkspace.shared.open(fileURL)
                    } catch {
                        NSWorkspace.shared.open(repoURL)
                    }
                }
            } else {
                NSWorkspace.shared.open(repoURL)
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "lutrisformac", url.host == "launch" else { continue }
            let gameIDString = url.pathComponents.dropFirst().first ?? ""
            guard let gameID = UUID(uuidString: gameIDString) else { continue }
            NotificationCenter.default.post(name: .launchGame, object: gameID)
        }
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: tr("Einstellungen"), action: #selector(showSettingsWindow), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        return menu
    }

    @objc func showSettingsWindow() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        idleTimer?.invalidate()
    }
}


