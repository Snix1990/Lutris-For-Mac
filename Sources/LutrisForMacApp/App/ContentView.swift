import SwiftUI
import AppKit

// MARK: - LaunchError

enum LaunchError: Error, LocalizedError {
    case steamLaunchDisabled
    var errorDescription: String? {
        switch self {
        case .steamLaunchDisabled: tr("Spiel wird nicht via Steam gestartet (launchViaSteam deaktiviert). Setze 'Über Steam starten' in den Spiel-Einstellungen oder ändere den Installationspfad.")
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @ObservedObject var viewModel: GameLibraryViewModel
    @ObservedObject var wineManager: WineManager
    @ObservedObject var runnerManager: RunnerManager
    @StateObject var lang = LanguageManager.shared
    @State private var selectedGameID: UUID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage("viewMode") private var viewMode: LibraryView.ViewMode = .list
    @State private var launchError: String?
    @State private var saveLibraryTask: Task<Void, Never>?
    @Environment(\.openWindow) private var openWindow

    // MARK: - Empty Game Sentinel

    private let emptyGame = Game(name: "", platform: "", installPath: "", runner: "", bannerURL: "", iconURL: "")

    private var selectedGameBinding: Binding<Game> {
        Binding(
            get: {
                if let id = selectedGameID, let idx = viewModel.games.firstIndex(where: { $0.id == id }) {
                    return viewModel.games[idx]
                }
                return emptyGame
            },
            set: { newGame in
                if let id = selectedGameID, let idx = viewModel.games.firstIndex(where: { $0.id == id }) {
                    viewModel.games[idx] = newGame
                    saveLibraryTask?.cancel()
                    saveLibraryTask = Task {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        guard !Task.isCancelled else { return }
                        viewModel.saveLibrary()
                    }
                }
            }
        )
    }

    // MARK: - Body

    var body: some View {
        Group {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(viewModel: viewModel, selectedGameID: $selectedGameID)
            } detail: {
            ZStack(alignment: .trailing) {
                LibraryView(
                    viewModel: viewModel,
                    selectedGameID: $selectedGameID,
                    viewMode: $viewMode,
                    onLaunch: { game in
                        selectedGameID = game.id
                        launch(game: game)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                GameDetailView(
                    game: selectedGameBinding,
                    onDelete: deleteGame,
                    onLaunch: launchSelectedGame,
                    onCommitPending: commitPendingChanges
                )
                .frame(width: 570)
                .background(.background)
                .compositingGroup()
                .offset(x: selectedGameID != nil ? 0 : 600)
                .shadow(color: .black.opacity(0.15), radius: 8, x: -4, y: 0)
            }
            .onChange(of: viewModel.pendingManualGameID) { _, newID in
                if let id = newID {
                    selectedGameID = id
                    viewModel.pendingManualGameID = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .launchGame)) { notification in
                if let gameID = notification.object as? UUID {
                    launchGameByID(gameID)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .importGameConfig)) { notification in
                if let game = notification.object as? Game {
                    var imported = game
                    imported.id = UUID()
                    imported.playTime = 0
                    imported.lastPlayed = nil
                    viewModel.games.append(imported)
                    viewModel.saveLibrary()
                    selectedGameID = imported.id
                }
            }
            .animation(.easeInOut(duration: 0.25), value: selectedGameID)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation {
                            columnVisibility = columnVisibility == .all ? .detailOnly : .all
                        }
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .helpLText("Seitenleiste ein-/ausblenden")
                }
                ToolbarItem(placement: .automatic) {
                    Picker(selection: $viewMode) {
                        Image(systemName: "list.bullet").tag(LibraryView.ViewMode.list)
                        Image(systemName: "square.grid.2x2").tag(LibraryView.ViewMode.grid)
                    } label: {
                        LText("Ansicht")
                    }
                    .pickerStyle(.segmented)
                    .helpLText("Ansicht umschalten")
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        openWindow(id: "add-game")
                    } label: {
                        Label { LText("Spiel hinzufügen") } icon: { Image(systemName: "plus") }
                    }
                    .keyboardShortcut(Keybinds.shortcut(for: .newGame).key, modifiers: Keybinds.shortcut(for: .newGame).modifiers)
                }
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button {
                            if let id = selectedGameID, let game = viewModel.games.first(where: { $0.id == id }) {
                                _ = viewModel.exportGameConfig(game)
                            }
                        } label: {
                            Label { LText("Spielkonfiguration exportieren") } icon: { Image(systemName: "square.and.arrow.up") }
                        }
                        Button {
                            if let _ = viewModel.importGameConfig() {
                                viewModel.saveLibrary()
                            }
                        } label: {
                            Label { LText("Spielkonfiguration importieren") } icon: { Image(systemName: "square.and.arrow.down") }
                        }
                        Divider()
                        Button {
                            _ = viewModel.exportLibraryBackup()
                        } label: {
                            Label { LText("Bibliothek sichern...") } icon: { Image(systemName: "externaldrive.badge.checkmark") }
                        }
                        Button {
                            if viewModel.importLibraryBackup() {
                                viewModel.refreshLibrary()
                            }
                        } label: {
                            Label { LText("Bibliothek wiederherstellen...") } icon: { Image(systemName: "externaldrive.badge.arrow.clockwise") }
                        }
                    } label: {
                        Label { LText("Extras") } icon: { Image(systemName: "ellipsis.circle") }
                    }
                    .helpLText("Bibliothek sichern/wiederherstellen")
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        openWindow(id: "wine-settings")
                    } label: {
                        Label { LText("Wine") } icon: { Image(systemName: "wineglass") }
                    }
                    .helpLText("Wine-Einstellungen")
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task {
                            let games = viewModel.games
                            try? await CloudSaveManager.shared.syncAll(games: games)
                        }
                    } label: {
                        Label {
                            HStack(spacing: 4) {
                                if CloudSaveManager.shared.isSyncing {
                                    ProgressView().controlSize(.small).scaleEffect(0.6)
                                }
                                LText("Cloud")
                            }
                        } icon: { Image(systemName: CloudSaveManager.shared.isSyncing
                            ? "icloud.and.arrow.up" : "icloud") }
                    }
                    .helpLText("Cloud-Speicherstände synchronisieren")
                    .disabled(CloudSaveManager.shared.isSyncing)
                }
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            removeNativeSidebarToggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            removeNativeSidebarToggle()
        }
        }
        .id(lang.refreshID)
        .environment(\.locale, lang.locale)
        .sheet(isPresented: .init(get: { launchError != nil }, set: { if !$0 { launchError = nil } })) {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundColor(.red)
                        .font(.title2)
                    Text(verbatim: tr("Fehler beim Starten"))
                        .font(.title2).bold()
                }
                .padding(.top)

                ScrollView(.vertical) {
                    if let error = launchError {
                        Text(error)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxHeight: 300)

                Button(tr("Schliessen")) {
                    launchError = nil
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .frame(width: 480, height: 400)
        }
    }

    // MARK: - Sidebar Toggle

    private func removeNativeSidebarToggle() {
        guard let window = NSApp.windows.first(where: { $0.isVisible }),
              let toolbar = window.toolbar else { return }
        let nativeIDs = [
            "com.apple.SwiftUI.navigationSplitView.toggleSidebar",
            "com.apple.toolbar.sidebar",
        ]
        for id in nativeIDs {
            while let idx = toolbar.items.firstIndex(where: { $0.itemIdentifier.rawValue == id }) {
                toolbar.removeItem(at: idx)
            }
        }
    }

    // MARK: - Helpers

    private func deleteGame() {
        if let id = selectedGameID, let idx = viewModel.games.firstIndex(where: { $0.id == id }) {
            let game = viewModel.games[idx]
            viewModel.deleteGame(game)
            selectedGameID = nil
        }
    }

    private func commitPendingChanges(id: UUID, pending: PendingGameChanges) {
        if let idx = viewModel.games.firstIndex(where: { $0.id == id }) {
            if viewModel.games[idx].name != pending.name { viewModel.games[idx].name = pending.name }
            if viewModel.games[idx].installPath != pending.installPath { viewModel.games[idx].installPath = pending.installPath }
            if viewModel.games[idx].launcherCommand != pending.launcherCommand { viewModel.games[idx].launcherCommand = pending.launcherCommand }
            if viewModel.games[idx].steamAppID != pending.steamAppID { viewModel.games[idx].steamAppID = pending.steamAppID }
            if viewModel.games[idx].coverURL != pending.coverURL { viewModel.games[idx].coverURL = pending.coverURL }
            if viewModel.games[idx].bannerURL != pending.bannerURL { viewModel.games[idx].bannerURL = pending.bannerURL }
            if viewModel.games[idx].iconURL != pending.iconURL { viewModel.games[idx].iconURL = pending.iconURL }
            if viewModel.games[idx].category != pending.category { viewModel.games[idx].category = pending.category }
            viewModel.saveLibrary()
        }
    }

    private func launchSelectedGame() {
        if let id = selectedGameID, let idx = viewModel.games.firstIndex(where: { $0.id == id }) {
            launch(game: viewModel.games[idx])
        }
    }

    // MARK: - Launch

    func launchGameByID(_ gameID: UUID) {
        if let idx = viewModel.games.firstIndex(where: { $0.id == gameID }) {
            selectedGameID = gameID
            launch(game: viewModel.games[idx])
        }
    }

    private func launch(game: Game) {
        guard !GameSessionManager.shared.isGameRunning(game.id) else {
            launchError = "\(game.name) läuft bereits"
            return
        }
        let isWineRunner = game.runner == "Wine" || game.runner == "CrossOver" || game.runner == "Whisky" || game.runner == "Kegworks"
        let isNative = game.runner == "Native" || game.platform == "macOS"
        let startTime = Date()

        Task {
            do {
                // --- Steam Emulator path (sets RPC + launches via wine/runner) ---
                if game.installPath.hasPrefix("steam://"), game.steamEmulatorEnabled == true {
                    let sid = GameSessionManager.shared.startSession(
                        gameID: game.id,
                        gameName: game.name,
                        coverURL: game.coverURL,
                        names: [(game.installPath as NSString).lastPathComponent]
                    )
                    _ = try await launchViaSteamEmulator(game: game, startTime: startTime, sessionID: sid)
                    let duration = Date().timeIntervalSince(startTime)
                    if duration > 10 { viewModel.recordPlaySession(gameID: game.id, duration: duration) }
                    return
                }

                // --- Wine / CrossOver ---
                if isWineRunner {
                    let exeName = (game.installPath as NSString).lastPathComponent
                    let sid = GameSessionManager.shared.startSession(
                        gameID: game.id,
                        gameName: game.name,
                        coverURL: game.coverURL,
                        names: exeName.contains(".") ? [exeName] : []
                    )
                    let wineVersion = wineManager.resolveWineVersion(for: game.wineVersionName)
                    if wineVersion != nil || game.wineBinaryPath?.isEmpty == false {
                        _ = try await wineManager.launchGame(game: game)
                        // For CrossOver shortcuts (.app), watch the running app
                        if game.runner == "CrossOver", game.installPath.hasSuffix(".app") {
                            GameSessionManager.shared.monitorApp(named: exeName, sessionID: sid)
                        }
                        let duration = Date().timeIntervalSince(startTime)
                        if duration > 10 { viewModel.recordPlaySession(gameID: game.id, duration: duration) }
                    } else {
                        launchError = "Keine Wine-Version gefunden. Stelle sicher, dass CrossOver installiert ist oder lade eine Wine-Version herunter."
                    }
                    return
                }

                // --- URL schemes (steam://, etc.) — no process tracking possible ---
                if game.installPath.contains("://") {
                    if game.installPath.hasPrefix("steam://"), game.launchViaSteam != true {
                        throw LaunchError.steamLaunchDisabled
                    }
                    if let url = URL(string: game.installPath) {
                        _ = GameSessionManager.shared.startSession(gameID: game.id, gameName: game.name, coverURL: game.coverURL)
                        NSWorkspace.shared.open(url)
                        let duration = Date().timeIntervalSince(startTime)
                        if duration > 10 { viewModel.recordPlaySession(gameID: game.id, duration: duration) }
                        return
                    } else {
                        launchError = "Ungültige URL: \(game.installPath)"
                        return
                    }
                }

                let env = ProcessRunner.parseEnvironmentVariables(from: game.environmentVariables)
                let config = game.runnerConfig

                // --- Native macOS .app ---
                if isNative || !runnerManager.runners.contains(where: { $0.name == game.runner }) {
                    let url = URL(fileURLWithPath: game.installPath)
                    guard FileManager.default.fileExists(atPath: url.path) else {
                        launchError = "Installationspfad existiert nicht: \(game.installPath)"
                        return
                    }
                    if url.pathExtension == "app" {
                        let sid = GameSessionManager.shared.startSession(gameID: game.id, gameName: game.name, coverURL: game.coverURL)
                        let openConfig = NSWorkspace.OpenConfiguration()
                        openConfig.activates = true
                        openConfig.createsNewApplicationInstance = false
                        let runningApp = try await NSWorkspace.shared.openApplication(at: url, configuration: openConfig)
                        let pid = runningApp.processIdentifier
                        if pid > 0 {
                            GameSessionManager.shared.addPID(pid, sessionID: sid)
                        } else {
                            GameSessionManager.shared.addName(url.lastPathComponent, sessionID: sid)
                        }
                    } else {
                        _ = GameSessionManager.shared.startSession(gameID: game.id, gameName: game.name, coverURL: game.coverURL)
                        NSWorkspace.shared.open(url)
                    }
                    let duration = Date().timeIntervalSince(startTime)
                    if duration > 10 { viewModel.recordPlaySession(gameID: game.id, duration: duration) }
                    return
                }

                // --- Emulator / other runners ---
                let sid = GameSessionManager.shared.startSession(
                    gameID: game.id,
                    gameName: game.name,
                    coverURL: game.coverURL
                )
                // Watch the runner binary for process monitoring
                if let runner = runnerManager.runners.first(where: { $0.name == game.runner }) {
                    let runnerExe = runner.binaryPath.isEmpty ? runner.name : (runner.binaryPath as NSString).lastPathComponent
                    GameSessionManager.shared.addName(runnerExe, sessionID: sid)
                }
                try await runnerManager.launchGame(
                    installPath: game.installPath,
                    runnerName: game.runner,
                    runnerConfig: config,
                    environment: env
                )
                let duration = Date().timeIntervalSince(startTime)
                if duration > 10 { viewModel.recordPlaySession(gameID: game.id, duration: duration) }
            } catch {
                launchError = error.localizedDescription
            }
        }
    }

    private func launchViaSteamEmulator(game: Game, startTime: Date, sessionID: UUID) async throws -> String {
        guard let steamID = game.steamAppID, !steamID.isEmpty else {
            throw LaunchError.steamLaunchDisabled
        }

        let steamLibraries = [
            "\(NSHomeDirectory())/Library/Application Support/Steam/steamapps",
            "/Library/Application Support/Steam/steamapps",
        ]
        var installDir: String?
        for lib in steamLibraries {
            guard FileManager.default.fileExists(atPath: lib) else { continue }
            let manifestPath = "\(lib)/appmanifest_\(steamID).acf"
            guard let manifest = try? String(contentsOfFile: manifestPath, encoding: .utf8) else { continue }
            for line in manifest.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("\"installdir\"") {
                    let parts = trimmed.components(separatedBy: "\"")
                    if parts.count >= 4 { installDir = "\(lib)/common/\(parts[3])" }
                    break
                }
            }
            break
        }

        guard let dir = installDir else {
            throw LaunchError.steamLaunchDisabled
        }

        guard let exePath = findExe(directory: dir) else {
            throw LaunchError.steamLaunchDisabled
        }

        var modifiedGame = game
        modifiedGame.installPath = exePath
        modifiedGame.launchViaSteam = false

        let isWine = game.runner == "CrossOver" || game.runner == "Wine" || game.runner == "Whisky" || game.runner == "Kegworks"
        if isWine {
            let output = try await wineManager.launchGame(game: modifiedGame)
            GameSessionManager.shared.addName((exePath as NSString).lastPathComponent, sessionID: sessionID)
            return output
        } else {
            try await runnerManager.launchGame(
                installPath: exePath,
                runnerName: game.runner,
                runnerConfig: game.runnerConfig,
                environment: ProcessRunner.parseEnvironmentVariables(from: game.environmentVariables)
            )
            GameSessionManager.shared.addName((exePath as NSString).lastPathComponent, sessionID: sessionID)
            return "Emulator: \(exePath)"
        }
    }

    private func findExe(directory: String) -> String? {
        guard let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: directory), includingPropertiesForKeys: nil) else { return nil }
        for case let file as URL in enumerator {
            let name = file.lastPathComponent.lowercased()
            if name.hasSuffix(".exe") && !name.hasSuffix("_unpacked.exe") && !name.hasSuffix(".lutrisbak") {
                return file.path
            }
        }
        return nil
    }
}
