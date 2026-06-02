import SwiftUI

@main
struct LutrisForMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var lang = LanguageManager.shared
    @StateObject private var viewModel = GameLibraryViewModel()
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
        .windowStyle(.hiddenTitleBar)

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
