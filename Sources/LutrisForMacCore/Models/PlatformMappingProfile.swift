import Foundation

public enum ControllerPlatform: String, Codable, CaseIterable, Sendable {
    case xbox = "Xbox"
    case playstation = "PlayStation"
    case nintendo = "Nintendo"
    case steam = "Steam"
    case custom = "Custom"
}

public struct PlatformMappingProfile: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var platform: ControllerPlatform
    public var mappings: [ButtonRemapping]
    public var isBuiltIn: Bool

    public init(id: UUID = UUID(), name: String, platform: ControllerPlatform,
                mappings: [ButtonRemapping], isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.platform = platform
        self.mappings = mappings
        self.isBuiltIn = isBuiltIn
    }

    /// Convert a mapping so physical "source" is pressed → logical "target" fires.
    /// All presets map *physical Xbox layout → logical target layout*
    public func remappedSource(for physicalID: String) -> String? {
        mappings.first(where: { $0.sourceID == physicalID && $0.isActive })?.targetID
    }

    public func remappedTarget(for logicalID: String) -> String? {
        mappings.first(where: { $0.targetID == logicalID && $0.isActive })?.sourceID
    }

    public static func == (lhs: PlatformMappingProfile, rhs: PlatformMappingProfile) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Built-in Presets

    /// **Nintendo Switch** layout (A↔B, X↔Y)
    /// Physical Xbox A → Nintendo B, Xbox B → Nintendo A, Xbox X → Nintendo Y, Xbox Y → Nintendo X
    public static let nintendoPreset = PlatformMappingProfile(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        name: "Nintendo Switch",
        platform: .nintendo,
        mappings: [
            ButtonRemapping(sourceID: "buttonA", targetID: "buttonB"),
            ButtonRemapping(sourceID: "buttonB", targetID: "buttonA"),
            ButtonRemapping(sourceID: "buttonX", targetID: "buttonY"),
            ButtonRemapping(sourceID: "buttonY", targetID: "buttonX"),
        ],
        isBuiltIn: true
    )

    /// **PlayStation** layout (Cross/Circle/Square/Triangle)
    /// Physical Xbox A → PlayStation X (Cross), B → Circle, X → Square, Y → Triangle
    public static let playstationPreset = PlatformMappingProfile(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        name: "PlayStation",
        platform: .playstation,
        mappings: [
            ButtonRemapping(sourceID: "buttonA", targetID: "buttonX"),
            ButtonRemapping(sourceID: "buttonB", targetID: "buttonY"),
            ButtonRemapping(sourceID: "buttonX", targetID: "buttonA"),
            ButtonRemapping(sourceID: "buttonY", targetID: "buttonB"),
        ],
        isBuiltIn: true
    )

    /// **Xbox** layout (identity – no remapping)
    public static let xboxPreset = PlatformMappingProfile(
        id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        name: "Xbox",
        platform: .xbox,
        mappings: [],
        isBuiltIn: true
    )

    /// **Steam** layout (same as Xbox for extended gamepad)
    public static let steamPreset = PlatformMappingProfile(
        id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
        name: "Steam Default",
        platform: .steam,
        mappings: [],
        isBuiltIn: true
    )

    public static let builtInProfiles: [PlatformMappingProfile] = [
        .nintendoPreset,
        .playstationPreset,
        .xboxPreset,
        .steamPreset,
    ]
}
