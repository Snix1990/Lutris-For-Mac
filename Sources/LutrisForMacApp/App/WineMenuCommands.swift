import SwiftUI

struct WineMenuCommands: Commands {
    @ObservedObject var wineManager: WineManager
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Wine") {
            Button {
                openWindow(id: "wine-settings")
            } label: {
                LText("Wine-Einstellungen")
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])

            Divider()

            Menu("Prefixes") {
                ForEach(wineManager.prefixes) { prefix in
                    Button("winecfg – \(prefix.name)") {
                        wineManager.runWinecfg(for: prefix)
                    }
                    Button("regedit – \(prefix.name)") {
                        wineManager.runRegedit(for: prefix)
                    }
                }
                if wineManager.prefixes.isEmpty {
                    LText("Keine Prefixes vorhanden")
                }
            }

            Divider()

            ForEach(wineManager.installedVersions) { v in
                Button("Info: \(v.displayName)") {
                    #if DEBUG
                    print("Wine-Version: \(v.displayName)")
                    print("  Pfad: \(v.path)")
                    print("  Binary: \(v.wineBinaryPath)")
                    #endif
                }
            }

            if wineManager.installedVersions.isEmpty {
                LText("Keine Wine-Versionen gefunden")
            }
        }
    }
}
