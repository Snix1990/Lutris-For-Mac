import Foundation

struct GameService: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var displayName: String
    var type: ServiceType
    var installed: Bool
    var installPath: String
    var connected: Bool
    var gameCount: Int
    var iconSystemName: String

    enum ServiceType: String, Codable, CaseIterable {
        case steam
        case heroic
        case itchio
        case battlenet
        case epic
        case gog
        case ryujinx
        case custom
    }

    init(
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
