import Foundation

public enum ConsoleDataSource {
    public static var games: [Game] {
        get {
            withLock()
            let result = _games ?? Self.loadFromDiskAndCache()
            unlock()
            return result
        }
        set {
            withLock()
            _games = newValue
            unlock()
        }
    }

    private static var _games: [Game]? = nil
    private static var unfairLock = os_unfair_lock()

    private static func withLock() {
        os_unfair_lock_lock(&unfairLock)
    }

    private static func unlock() {
        os_unfair_lock_unlock(&unfairLock)
    }

    private static func loadFromDiskAndCache() -> [Game] {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = folder.appendingPathComponent("LutrisForMac/games.json")
        guard let data = try? Data(contentsOf: url),
              let games = try? JSONDecoder().decode([Game].self, from: data),
              !games.isEmpty
        else {
            let samples = Game.sampleData
            _games = samples
            return samples
        }
        _games = games
        return games
    }
}
