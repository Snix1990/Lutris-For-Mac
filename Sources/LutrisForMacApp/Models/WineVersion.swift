import Foundation

struct WineVersion: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var displayName: String
    var path: String
    var wineBinaryPath: String
    var wineServerPath: String
    var type: WineSource
    var created: Date

    enum WineSource: String, Codable, CaseIterable {
        case system       // /usr/local/bin/wine etc.
        case homebrew     // via Homebrew
        case downloaded   // selbst heruntergeladen (Gcenx etc.)
        case yaagl        // Yaagl-Wine-Builds (Media Foundation Patches)
        case crossover    // CrossOver.app
        case whisky       // Whisky.app (GPTK)
        case wineskin     // Wineskin.app
        case custom       // eigener Pfad
    }

    init(
        id: UUID = UUID(),
        name: String,
        displayName: String = "",
        path: String,
        wineBinaryPath: String = "",
        wineServerPath: String = "",
        type: WineSource = .system,
        created: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName.isEmpty ? name : displayName
        self.path = path
        self.wineBinaryPath = wineBinaryPath
        self.wineServerPath = wineServerPath
        self.type = type
        self.created = created
    }
}
