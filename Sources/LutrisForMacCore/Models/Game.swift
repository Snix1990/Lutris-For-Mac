import Foundation
import SwiftUI

public struct Game: Identifiable, Hashable, Codable {
    public var id: UUID
    public var name: String
    public var platform: String
    public var installPath: String
    public var runner: String
    public var launcherCommand: String
    public var installScriptPath: String
    public var environmentVariables: String
    public var notes: String

    public var category: String
    public var isFavorite: Bool
    public var rating: Int
    public var playTime: TimeInterval
    public var lastPlayed: Date?

    public var wineVersionName: String?
    public var winePrefixName: String?
    public var winePrefixID: UUID?
    public var wineBinaryPath: String?
    public var winePrefixPath: String?
    public var wineArchitecture: String?
    public var wineDesktopMode: Bool
    public var wineDesktopResolution: String
    public var wineDXMT: Bool
    public var wineAudioDriver: String
    public var wineLaunchArguments: String
    public var wineRenderMode: WineRenderMode
    public var wineESync: Bool
    public var wineFSync: Bool
    public var wineMSync: Bool?
    public var wineShaderCache: Bool
    public var wineDebugString: String
    public var wineDxvkHud: Bool
    public var wineDLSS: Bool

    public var coverURL: String
    public var coverPath: String
    public var bannerURL: String
    public var iconURL: String

    public var steamAppID: String?
    public var launchViaSteam: Bool?
    public var steamEmulatorEnabled: Bool?

    public var serviceName: String?

    public var gameDescription: String
    public var screenshotPaths: [String]

    public var runnerConfig: [String: String]

    public var preLaunchScript: String
    public var postExitScript: String

    public var customSavePath: String
    public var runtimeSettings: RuntimeSettings

    public var playTimeFormatted: String {
        let hours = Int(playTime) / 3600
        let minutes = (Int(playTime) % 3600) / 60
        if hours > 0 { return "\(hours) Std. \(minutes) Min" }
        return "\(minutes) Min"
    }

    public var title: String { name }

    public var isInstalled: Bool {
        guard !installPath.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: installPath)
    }

    public var winePrefix: String? {
        winePrefixName ?? winePrefixPath
    }

    public var coverColor: Color {
        let hash = abs(name.hashValue)
        let palette: [Color] = [
            .init(red: 0.95, green: 0.35, blue: 0.65),
            .init(red: 0.75, green: 0.25, blue: 0.80),
            .init(red: 0.50, green: 0.25, blue: 0.90),
            .init(red: 1.00, green: 0.60, blue: 0.30),
            .init(red: 0.30, green: 0.70, blue: 0.40),
            .init(red: 0.70, green: 0.40, blue: 0.20),
            .init(red: 0.60, green: 0.20, blue: 0.30),
            .init(red: 0.20, green: 0.40, blue: 0.80),
        ]
        return palette[hash % palette.count]
    }

    public static let sampleData: [Game] = [
        Game(name: "The Witcher 3", platform: "Windows", installPath: "", runner: "Wine",
             notes: "RPG", category: "RPG",
             isFavorite: false, playTime: 3600 * 12,
             lastPlayed: Date().addingTimeInterval(-3600 * 2),
             gameDescription: "Ein episches Fantasy-Rollenspiel."),
        Game(name: "Cyberpunk 2077", platform: "Steam", installPath: "", runner: "Native",
             isFavorite: false, playTime: 3600 * 4,
             lastPlayed: Date().addingTimeInterval(-86400),
             gameDescription: "Ein Open-World-Sci-Fi-RPG."),
        Game(name: "Diablo IV", platform: "Battle.net", installPath: "", runner: "Native",
             isFavorite: false, playTime: 3600 * 23,
             lastPlayed: Date().addingTimeInterval(-86400 * 3),
             gameDescription: "Ein düsteres Action-RPG."),
        Game(name: "Elden Ring", platform: "Steam", installPath: "", runner: "Native",
             isFavorite: false, playTime: 3600 * 8,
             gameDescription: "Ein anspruchsvolles Action-RPG."),
        Game(name: "Stardew Valley", platform: "GOG", installPath: "", runner: "Native",
             isFavorite: false, playTime: 3600 * 45),
        Game(name: "Baldur's Gate 3", platform: "Steam", installPath: "", runner: "Native",
             isFavorite: false, playTime: 0),
    ]

    public init(
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
        wineDebugString: String = "",
        wineDxvkHud: Bool = false,
        wineDLSS: Bool = false,
        coverURL: String = "",
        coverPath: String = "",
        bannerURL: String = "",
        iconURL: String = "",
         steamAppID: String? = nil,
         launchViaSteam: Bool? = nil,
         steamEmulatorEnabled: Bool? = nil,
         serviceName: String? = nil,
         gameDescription: String = "",
         screenshotPaths: [String] = [],
         runnerConfig: [String: String] = [:],
        preLaunchScript: String = "",
        postExitScript: String = "",
        customSavePath: String = "",
        runtimeSettings: RuntimeSettings = RuntimeSettings()
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
        self.wineDebugString = wineDebugString
        self.wineDxvkHud = wineDxvkHud
        self.wineDLSS = wineDLSS
         self.serviceName = serviceName
         self.gameDescription = gameDescription
         self.screenshotPaths = screenshotPaths
         self.preLaunchScript = preLaunchScript
        self.postExitScript = postExitScript
        self.customSavePath = customSavePath
        self.runtimeSettings = runtimeSettings
        self.runnerConfig = runnerConfig
    }

    public enum CodingKeys: String, CodingKey {
        case id, name, platform, installPath, runner, launcherCommand, installScriptPath
        case environmentVariables, notes, category, isFavorite, rating, playTime, lastPlayed
        case wineVersionName, winePrefixName, winePrefixID, wineArchitecture
        case wineBinaryPath, winePrefixPath
        case wineDesktopMode, wineDesktopResolution, wineDXMT, wineAudioDriver
        case wineLaunchArguments, wineRenderMode, wineESync, wineFSync, wineMSync, wineShaderCache
        case wineDebugString, wineDxvkHud, wineDLSS
        case coverURL, coverPath, bannerURL, iconURL
        case steamAppID, launchViaSteam, steamEmulatorEnabled, serviceName, gameDescription, screenshotPaths, runnerConfig
        case preLaunchScript, postExitScript, customSavePath, runtimeSettings
    }

    public init(from decoder: Decoder) throws {
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
        wineDebugString = try c.decodeIfPresent(String.self, forKey: .wineDebugString) ?? ""
        wineDxvkHud = try c.decodeIfPresent(Bool.self, forKey: .wineDxvkHud) ?? false
        wineDLSS = try c.decodeIfPresent(Bool.self, forKey: .wineDLSS) ?? false
        coverURL = try c.decodeIfPresent(String.self, forKey: .coverURL) ?? ""
        coverPath = try c.decodeIfPresent(String.self, forKey: .coverPath) ?? ""
        bannerURL = try c.decodeIfPresent(String.self, forKey: .bannerURL) ?? ""
        iconURL = try c.decodeIfPresent(String.self, forKey: .iconURL) ?? ""
        steamAppID = try c.decodeIfPresent(String.self, forKey: .steamAppID)
        launchViaSteam = try c.decodeIfPresent(Bool.self, forKey: .launchViaSteam)
        steamEmulatorEnabled = try c.decodeIfPresent(Bool.self, forKey: .steamEmulatorEnabled)
        serviceName = try c.decodeIfPresent(String.self, forKey: .serviceName)
        gameDescription = try c.decodeIfPresent(String.self, forKey: .gameDescription) ?? ""
        screenshotPaths = try c.decodeIfPresent([String].self, forKey: .screenshotPaths) ?? []
        runnerConfig = try c.decodeIfPresent([String: String].self, forKey: .runnerConfig) ?? [:]
        preLaunchScript = try c.decodeIfPresent(String.self, forKey: .preLaunchScript) ?? ""
        postExitScript = try c.decodeIfPresent(String.self, forKey: .postExitScript) ?? ""
        customSavePath = try c.decodeIfPresent(String.self, forKey: .customSavePath) ?? ""
        runtimeSettings = try c.decodeIfPresent(RuntimeSettings.self, forKey: .runtimeSettings) ?? RuntimeSettings()
    }
}
