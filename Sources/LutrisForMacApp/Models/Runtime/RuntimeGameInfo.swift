import Foundation

struct RuntimeGameInfo: Codable {
    let gameID: String
    let gameName: String
    let coverURL: String
    let installPath: String
    let runner: String
    let runtimeSettings: RuntimeSettings
    let discordEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case gameID, gameName, coverURL, installPath, runner, runtimeSettings, discordEnabled
    }

    init(gameID: String, gameName: String, coverURL: String, installPath: String, runner: String, runtimeSettings: RuntimeSettings, discordEnabled: Bool) {
        self.gameID = gameID
        self.gameName = gameName
        self.coverURL = coverURL
        self.installPath = installPath
        self.runner = runner
        self.runtimeSettings = runtimeSettings
        self.discordEnabled = discordEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gameID = try container.decode(String.self, forKey: .gameID)
        gameName = try container.decode(String.self, forKey: .gameName)
        coverURL = try container.decode(String.self, forKey: .coverURL)
        installPath = try container.decode(String.self, forKey: .installPath)
        runner = try container.decode(String.self, forKey: .runner)
        runtimeSettings = try container.decode(RuntimeSettings.self, forKey: .runtimeSettings)
        discordEnabled = try container.decodeIfPresent(Bool.self, forKey: .discordEnabled) ?? false
    }

    static var tempFileURL: URL {
        URL(fileURLWithPath: "/tmp/lutris_runtime_game.json")
    }
}
