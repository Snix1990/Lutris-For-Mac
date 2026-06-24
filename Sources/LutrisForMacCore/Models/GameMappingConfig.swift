import Foundation

/// Per-game mapping configuration.
/// Stores the assigned platform profile ID + optional extra overrides.
public struct GameMappingConfig: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let gameID: UUID
    public var profileID: UUID?
    public var customMappings: [ButtonRemapping]
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        gameID: UUID,
        profileID: UUID? = nil,
        customMappings: [ButtonRemapping] = [],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.gameID = gameID
        self.profileID = profileID
        self.customMappings = customMappings
        self.isEnabled = isEnabled
    }

    /// Merged mapping list: profile mappings + custom overrides.
    /// Custom overrides take precedence.
    public func effectiveMappings(profiles: [PlatformMappingProfile]) -> [ButtonRemapping] {
        guard isEnabled else { return [] }
        var merged: [String: ButtonRemapping] = [:]

        // Apply profile mappings first
        if let profileID, let profile = profiles.first(where: { $0.id == profileID }) {
            for mapping in profile.mappings {
                merged[mapping.sourceID] = mapping
            }
        }

        // Custom overrides on top
        for mapping in customMappings {
            merged[mapping.sourceID] = mapping
        }

        return Array(merged.values)
    }

    /// Determine the best platform label for display.
    public func displayPlatform(profiles: [PlatformMappingProfile]) -> String? {
        guard isEnabled else { return nil }
        if let profileID, let profile = profiles.first(where: { $0.id == profileID }) {
            return profile.name
        }
        if !customMappings.isEmpty {
            return "Custom"
        }
        return nil
    }
}
