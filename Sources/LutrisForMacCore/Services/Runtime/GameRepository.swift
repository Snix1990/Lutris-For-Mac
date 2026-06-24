import Foundation

@MainActor
public enum GameRepository {
    public static var allGames: [Game] = []

    public static func game(for id: UUID) -> Game? {
        allGames.first { $0.id == id }
    }
}
