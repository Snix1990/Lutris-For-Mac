import Foundation
import Combine
import OSLog

// ================================================================
// RemappingService.swift
// ================================================================
// Central coordinator for button‑remapping profiles, per‑game
// configs, persistence and auto‑apply on game launch.
//
// Usage:
//   RemappingService.shared
//     .profiles          – user‑defined + built‑in profiles
//     .config(for:)      – per‑game config
//     .setProfile(...)   – assign profile to a game
//     .activate(for:)    – apply mapping when a game launches
// ================================================================

private let log = Logger(subsystem: "net.lutrisformac", category: "RemappingService")

@MainActor
public final class RemappingService: ObservableObject {
    public static let shared = RemappingService()

    // MARK: - Published State

    /// All known mapping profiles (built‑in + user‑defined)
    @Published public var profiles: [PlatformMappingProfile] = []

    /// Per‑game mapping configs
    @Published public var gameConfigs: [UUID: GameMappingConfig] = [:]

    /// Currently active profile (auto‑set on game launch, nil = passthrough)
    @Published public var activeProfile: PlatformMappingProfile?

    /// Which game ID the active profile belongs to (nil = global)
    @Published public var activeForGameID: UUID?

    // MARK: - Persistence

    private let profilesURL: URL
    private let gameConfigsURL: URL

    // MARK: - Init

    private init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LutrisForMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        profilesURL = folder.appendingPathComponent("mapping_profiles.json")
        gameConfigsURL = folder.appendingPathComponent("game_mappings.json")

        loadAll()
    }

    // MARK: - Profile Management

    /// Add a new user profile.
    public func addProfile(_ profile: PlatformMappingProfile) {
        profiles.append(profile)
        saveProfiles()
    }

    /// Update an existing profile.
    public func updateProfile(_ profile: PlatformMappingProfile) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[idx] = profile
        saveProfiles()
    }

    /// Remove a user profile (built‑in profiles cannot be removed).
    public func removeProfile(id: UUID) {
        guard let profile = profiles.first(where: { $0.id == id }), !profile.isBuiltIn else { return }
        profiles.removeAll { $0.id == id }
        gameConfigs = gameConfigs.mapValues { config in
            var c = config
            if c.profileID == id { c.profileID = nil }
            return c
        }
        saveProfiles()
        saveGameConfigs()
    }

    /// Duplicate a profile as a user‑editable copy.
    public func duplicateProfile(_ profile: PlatformMappingProfile) -> PlatformMappingProfile {
        let copy = PlatformMappingProfile(
            name: "\(profile.name) (Kopie)",
            platform: profile.platform,
            mappings: profile.mappings,
            isBuiltIn: false
        )
        addProfile(copy)
        return copy
    }

    // MARK: - Per‑Game Config

    /// Get the mapping config for a game (creates default if missing).
    public func config(for gameID: UUID) -> GameMappingConfig {
        if let existing = gameConfigs[gameID] {
            return existing
        }
        let config = GameMappingConfig(gameID: gameID)
        gameConfigs[gameID] = config
        return config
    }

    /// Assign a profile to a game.
    public func setProfile(_ profileID: UUID?, for gameID: UUID) {
        var config = self.config(for: gameID)
        config.profileID = profileID
        gameConfigs[gameID] = config
        saveGameConfigs()
    }

    /// Add a custom mapping override for a game.
    public func addCustomMapping(_ mapping: ButtonRemapping, for gameID: UUID) {
        var config = self.config(for: gameID)
        config.customMappings.append(mapping)
        gameConfigs[gameID] = config
        saveGameConfigs()
    }

    /// Remove a custom mapping override.
    public func removeCustomMapping(id: UUID, for gameID: UUID) {
        guard var config = gameConfigs[gameID] else { return }
        config.customMappings.removeAll { $0.id == id }
        gameConfigs[gameID] = config
        saveGameConfigs()
    }

    /// Enable/disable mapping for a game.
    public func setEnabled(_ enabled: Bool, for gameID: UUID) {
        guard var config = gameConfigs[gameID] else { return }
        config.isEnabled = enabled
        gameConfigs[gameID] = config
        saveGameConfigs()
    }

    /// Remove all config for a game.
    public func removeConfig(for gameID: UUID) {
        gameConfigs.removeValue(forKey: gameID)
        saveGameConfigs()
    }

    // MARK: - Activation (called on game launch)

    /// Activate the mapping profile for a specific game.
    /// Automatically looks up the game's config and applies it.
    /// Call this just before launching the game process.
    public func activate(for gameID: UUID) {
        let config = self.config(for: gameID)
        guard config.isEnabled else {
            deactivate()
            return
        }

        let effective = config.effectiveMappings(profiles: profiles)
        HIDRemapper.shared.apply(mappings: effective)

        if let profileID = config.profileID,
           let profile = profiles.first(where: { $0.id == profileID }) {
            activeProfile = profile
        } else {
            activeProfile = nil
        }
        activeForGameID = gameID

        log.info("Activated mapping for game \(gameID): \(effective.count) remappings")
    }

    /// Activate mapping for a specific runner (used for per-runner HID profiles).
    /// Falls back to game-specific config if no runner profile is set.
    public func activate(runnerName: String, gameID: UUID?) {
        let runnerProfileID = Self.loadRunnerProfileID(for: runnerName)
        if let profileID = runnerProfileID,
           let profile = profiles.first(where: { $0.id == profileID }) {
            HIDRemapper.shared.apply(profile: profile)
            activeProfile = profile
            activeForGameID = gameID
            log.info("Activated runner profile '\(profile.name)' for runner '\(runnerName)'")
        } else if let gameID {
            // Fallback to game-specific config
            activate(for: gameID)
        } else {
            deactivate()
        }
    }

    /// Load the saved HID profile ID for a specific runner.
    private static func loadRunnerProfileID(for runnerName: String) -> UUID? {
        guard let data = UserDefaults.standard.data(forKey: "runnerHIDProfileIDs"),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return nil }
        guard let idString = dict[runnerName] else { return nil }
        return UUID(uuidString: idString)
    }

    /// Deactivate all mappings (restore passthrough).
    public func deactivate() {
        HIDRemapper.shared.clear()
        activeProfile = nil
        activeForGameID = nil
        log.info("Deactivated all mappings")
    }

    // MARK: - Convenience: Platform‑Based Auto‑Apply

    /// Suffix‑based auto‑detection of the target platform.
    /// Examples: "(Switch)" → Nintendo, "(PS4)" → PlayStation, "(PS5)" → PlayStation,
    ///           "(PC)" → Xbox, "(Steam)" → Steam
    public func suggestProfile(for game: Game) -> PlatformMappingProfile? {
        let lowerName = game.name.lowercased()
        let lowerPlatform = game.platform.lowercased()
        let combined = lowerName + " " + lowerPlatform

        if combined.contains("switch") || combined.contains("nintendo") {
            return profiles.first(where: { $0.id == PlatformMappingProfile.nintendoPreset.id })
        }
        if combined.contains("ps4") || combined.contains("ps5") || combined.contains("playstation") || combined.contains("psp") {
            return profiles.first(where: { $0.id == PlatformMappingProfile.playstationPreset.id })
        }
        if combined.contains("steam") {
            return profiles.first(where: { $0.id == PlatformMappingProfile.steamPreset.id })
        }
        // Default to Xbox for Windows / PC games
        if lowerPlatform == "windows" || lowerPlatform == "pc" || combined.contains("xbox") {
            return profiles.first(where: { $0.id == PlatformMappingProfile.xboxPreset.id })
        }
        return nil
    }

    // MARK: - Persistence

    private func loadAll() {
        // Load built‑ins
        let builtIn = PlatformMappingProfile.builtInProfiles

        // Load user profiles
        var userProfiles: [PlatformMappingProfile] = []
        if let data = try? Data(contentsOf: profilesURL),
           let loaded = try? JSONDecoder().decode([PlatformMappingProfile].self, from: data) {
            userProfiles = loaded
        }

        // Merge: built‑ins take precedence by ID
        var merged = builtIn
        for user in userProfiles {
            if let idx = merged.firstIndex(where: { $0.id == user.id }) {
                merged[idx] = user
            } else {
                merged.append(user)
            }
        }
        profiles = merged

        // Load game configs
        if let data = try? Data(contentsOf: gameConfigsURL),
           let loaded = try? JSONDecoder().decode([String: GameMappingConfig].self, from: data) {
            gameConfigs = Dictionary(uniqueKeysWithValues: loaded.map { (UUID(uuidString: $0.key) ?? UUID(), $0.value) })
        }
    }

    private func saveProfiles() {
        let userProfiles = profiles.filter { !$0.isBuiltIn }
        guard let data = try? JSONEncoder().encode(userProfiles) else { return }
        try? data.write(to: profilesURL, options: .atomic)
    }

    private func saveGameConfigs() {
        let dict = Dictionary(uniqueKeysWithValues: gameConfigs.map { ($0.key.uuidString, $0.value) })
        guard let data = try? JSONEncoder().encode(dict) else { return }
        try? data.write(to: gameConfigsURL, options: .atomic)
    }
}
