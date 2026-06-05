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
                .keyboardShortcut("r", modifiers: [.command])

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
                            alert.informativeText = "\(total) ROMs gefunden in: \(platforms)"
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
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(RomFolderManager.shared.folders.isEmpty)
            }

            WineMenuCommands(wineManager: wineManager)
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
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        Task { await checkForUpdate() }
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
}

extension Notification.Name {
    static let launchGame = Notification.Name("launchGame")
    static let importGameConfig = Notification.Name("importGameConfig")
}
