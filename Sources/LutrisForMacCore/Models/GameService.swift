import Foundation

public struct GameService: Identifiable, Hashable, Codable {
    public let id: UUID
    public var name: String
    public var displayName: String
    public var type: ServiceType
    public var installed: Bool
    public var installPath: String
    public var connected: Bool
    public var gameCount: Int
    public var iconSystemName: String

    public enum ServiceType: String, Codable, CaseIterable {
        case steam
        case heroic
        case itchio
        case battlenet
        case epic
        case gog
        case ryujinx
        case amazon
        case ubisoft
        case humble
        case custom
    }

    public init(
        id: UUID = UUID(),
        name: String,
        displayName: String = "",
        type: ServiceType,
        installed: Bool = false,
        installPath: String = "",
        connected: Bool = false,
        gameCount: Int = 0,
        iconSystemName: String = "square.stack.3d.up"
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName.isEmpty ? name : displayName
        self.type = type
        self.installed = installed
        self.installPath = installPath
        self.connected = connected
        self.gameCount = gameCount
        self.iconSystemName = iconSystemName
    }
}
