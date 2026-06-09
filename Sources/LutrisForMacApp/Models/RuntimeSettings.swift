import Foundation

struct RuntimeSettings: Codable, Equatable, Hashable {
    var cloudSync = true
    var discordRPC = true
    var webhook = true
    var healthCheck = true
    var osdEnabled = false
    var screenshotEnabled = false
    var recordingEnabled = false
    var autoSaveBeforeExit = false
    var overlayEnabled = false

    // Logging
    var processLogging = true
    var statsMonitoring = true
    var logFileRotation = true
    var wineDebugLogging = true
}
