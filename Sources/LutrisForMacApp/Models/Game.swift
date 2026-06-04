import Foundation

struct Game: Identifiable, Hashable, Codable {
    var id: UUID
    var name: String
    var platform: String
    var installPath: String
    var runner: String
    var launcherCommand: String
    var installScriptPath: String
    var environmentVariables: String
    var notes: String

    // Organisation
    var category: String
    var isFavorite: Bool
    var rating: Int
    var playTime: TimeInterval
    var lastPlayed: Date?

    // Wine-spezifische Felder
    var wineVersionName: String?
    var winePrefixName: String?
    var winePrefixID: UUID?
    var wineBinaryPath: String?
    var winePrefixPath: String?
    var wineArchitecture: String?
    var wineDesktopMode: Bool
    var wineDesktopResolution: String
    var wineDXMT: Bool // deprecated – wird nicht mehr ausgewertet
    var wineAudioDriver: String
    var wineLaunchArguments: String
    var wineRenderMode: WineRenderMode
    var wineESync: Bool
    var wineFSync: Bool
    var wineMSync: Bool?
    var wineShaderCache: Bool

    // Media / Artwork
    var coverURL: String
    var coverPath: String
    var bannerURL: String
    var iconURL: String

    // Steam
    var steamAppID: String?
    var launchViaSteam: Bool?
    var steamEmulatorEnabled: Bool?

    // Service-Zuordnung (Steam, Heroic, itch.io, Battle.net, etc.)
    var serviceName: String?

    // Runner-Konfiguration (pro Runner-ID -> Wert)
    var runnerConfig: [String: String]

    var playTimeFormatted: String {
        let hours = Int(playTime) / 3600
        let minutes = (Int(playTime) % 3600) / 60
        if hours > 0 { return "\(hours) Std. \(minutes) Min" }
        return "\(minutes) Min"
    }

    init(
        id: UUID = UUID(),
        name: String,
        platform: String,
        installPath: String,
        runner: String,
        launcherCommand: String = "",
        installScriptPath: String = "",
        environmentVariables: String = "",
        notes: String = "",
        category: String = "",
        isFavorite: Bool = false,
        rating: Int = 0,
        playTime: TimeInterval = 0,
        lastPlayed: Date? = nil,
        wineVersionName: String? = nil,
        winePrefixName: String? = nil,
        winePrefixID: UUID? = nil,
        wineBinaryPath: String? = nil,
        winePrefixPath: String? = nil,
        wineArchitecture: String? = nil,
        wineDesktopMode: Bool = false,
        wineDesktopResolution: String = "1024x768",
        wineDXMT: Bool = false,
        wineAudioDriver: String = "coreaudio",
        wineLaunchArguments: String = "",
        wineRenderMode: WineRenderMode = .auto,
        wineESync: Bool = false,
        wineFSync: Bool = false,
        wineMSync: Bool? = nil,
        wineShaderCache: Bool = true,
        coverURL: String = "",
        coverPath: String = "",
        bannerURL: String = "",
        iconURL: String = "",
        steamAppID: String? = nil,
        launchViaSteam: Bool? = nil,
        steamEmulatorEnabled: Bool? = nil,
        serviceName: String? = nil,
        runnerConfig: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.platform = platform
        self.installPath = installPath
        self.runner = runner
        self.launcherCommand = launcherCommand
        self.installScriptPath = installScriptPath
        self.environmentVariables = environmentVariables
        self.notes = notes
        self.category = category
        self.isFavorite = isFavorite
        self.rating = rating
        self.playTime = playTime
        self.lastPlayed = lastPlayed
        self.coverURL = coverURL
        self.coverPath = coverPath
        self.bannerURL = bannerURL
        self.iconURL = iconURL
        self.steamAppID = steamAppID
        self.launchViaSteam = launchViaSteam
        self.steamEmulatorEnabled = steamEmulatorEnabled
        self.wineVersionName = wineVersionName
        self.winePrefixName = winePrefixName
        self.winePrefixID = winePrefixID
        self.wineBinaryPath = wineBinaryPath
        self.winePrefixPath = winePrefixPath
        self.wineArchitecture = wineArchitecture
        self.wineDesktopMode = wineDesktopMode
        self.wineDesktopResolution = wineDesktopResolution
        self.wineDXMT = wineDXMT
        self.wineAudioDriver = wineAudioDriver
        self.wineLaunchArguments = wineLaunchArguments
        self.wineRenderMode = wineRenderMode
        self.wineESync = wineESync
        self.wineFSync = wineFSync
        self.wineMSync = wineMSync
        self.wineShaderCache = wineShaderCache
        self.serviceName = serviceName
        self.runnerConfig = runnerConfig
    }

    enum CodingKeys: String, CodingKey {
        case id, name, platform, installPath, runner, launcherCommand, installScriptPath
        case environmentVariables, notes, category, isFavorite, rating, playTime, lastPlayed
        case wineVersionName, winePrefixName, winePrefixID, wineArchitecture
        case wineBinaryPath, winePrefixPath
        case wineDesktopMode, wineDesktopResolution, wineDXMT, wineAudioDriver
        case wineLaunchArguments, wineRenderMode, wineESync, wineFSync, wineMSync, wineShaderCache
        case coverURL, coverPath, bannerURL, iconURL
        case steamAppID, launchViaSteam, steamEmulatorEnabled, serviceName, runnerConfig
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        platform = try c.decode(String.self, forKey: .platform)
        installPath = try c.decode(String.self, forKey: .installPath)
        runner = try c.decode(String.self, forKey: .runner)
        launcherCommand = try c.decodeIfPresent(String.self, forKey: .launcherCommand) ?? ""
        installScriptPath = try c.decodeIfPresent(String.self, forKey: .installScriptPath) ?? ""
        environmentVariables = try c.decodeIfPresent(String.self, forKey: .environmentVariables) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        rating = try c.decodeIfPresent(Int.self, forKey: .rating) ?? 0
        playTime = try c.decodeIfPresent(TimeInterval.self, forKey: .playTime) ?? 0
        lastPlayed = try c.decodeIfPresent(Date.self, forKey: .lastPlayed)
        wineVersionName = try c.decodeIfPresent(String.self, forKey: .wineVersionName)
        winePrefixName = try c.decodeIfPresent(String.self, forKey: .winePrefixName)
        winePrefixID = try c.decodeIfPresent(UUID.self, forKey: .winePrefixID)
        wineBinaryPath = try c.decodeIfPresent(String.self, forKey: .wineBinaryPath)
        winePrefixPath = try c.decodeIfPresent(String.self, forKey: .winePrefixPath)
        wineArchitecture = try c.decodeIfPresent(String.self, forKey: .wineArchitecture)
        wineDesktopMode = try c.decodeIfPresent(Bool.self, forKey: .wineDesktopMode) ?? false
        wineDesktopResolution = try c.decodeIfPresent(String.self, forKey: .wineDesktopResolution) ?? "1024x768"
        wineDXMT = try c.decodeIfPresent(Bool.self, forKey: .wineDXMT) ?? false
        wineAudioDriver = try c.decodeIfPresent(String.self, forKey: .wineAudioDriver) ?? "coreaudio"
        wineLaunchArguments = try c.decodeIfPresent(String.self, forKey: .wineLaunchArguments) ?? ""
        wineRenderMode = try c.decodeIfPresent(WineRenderMode.self, forKey: .wineRenderMode) ?? .auto
        wineESync = try c.decodeIfPresent(Bool.self, forKey: .wineESync) ?? false
        wineFSync = try c.decodeIfPresent(Bool.self, forKey: .wineFSync) ?? false
        wineMSync = try c.decodeIfPresent(Bool.self, forKey: .wineMSync)
        wineShaderCache = try c.decodeIfPresent(Bool.self, forKey: .wineShaderCache) ?? true
        coverURL = try c.decodeIfPresent(String.self, forKey: .coverURL) ?? ""
        coverPath = try c.decodeIfPresent(String.self, forKey: .coverPath) ?? ""
        bannerURL = try c.decodeIfPresent(String.self, forKey: .bannerURL) ?? ""
        iconURL = try c.decodeIfPresent(String.self, forKey: .iconURL) ?? ""
        steamAppID = try c.decodeIfPresent(String.self, forKey: .steamAppID)
        launchViaSteam = try c.decodeIfPresent(Bool.self, forKey: .launchViaSteam)
        steamEmulatorEnabled = try c.decodeIfPresent(Bool.self, forKey: .steamEmulatorEnabled)
        serviceName = try c.decodeIfPresent(String.self, forKey: .serviceName)
        runnerConfig = try c.decodeIfPresent([String: String].self, forKey: .runnerConfig) ?? [:]
    }
}
