import Foundation

public struct WineVersion: Identifiable, Hashable, Codable {
    public let id: UUID
    public var name: String
    public var displayName: String
    public var path: String
    public var wineBinaryPath: String
    public var wineServerPath: String
    public var type: WineSource
    public var created: Date

    public enum WineSource: String, Codable, CaseIterable {
        case system
        case homebrew
        case downloaded
        case yaagl
        case crossover
        case whisky
        case wineskin
        case custom
    }

    public init(
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
