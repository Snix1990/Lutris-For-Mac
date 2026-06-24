import Foundation

public struct RuntimeSettings: Codable, Equatable, Hashable {
    public var cloudSync = true
    public var discordRPC = true
    public var webhook = true
    public var healthCheck = true
    public var osdEnabled = false
    public var screenshotEnabled = false
    public var recordingEnabled = false
    public var autoSaveBeforeExit = false
    public var overlayEnabled = false

    public var processLogging = true
    public var statsMonitoring = true
    public var logFileRotation = true
    public var wineDebugLogging = true

    public init() {}
}
