import Foundation

struct RuntimeGameInfo: Codable {
    let gameID: String
    let gameName: String
    let coverURL: String
    let installPath: String
    let runner: String
    let runtimeSettings: RuntimeSettings

    static var tempFileURL: URL {
        URL(fileURLWithPath: "/tmp/lutris_runtime_game.json")
    }
}
