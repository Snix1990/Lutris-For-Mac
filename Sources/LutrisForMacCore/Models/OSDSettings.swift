import Foundation

public enum OSDPosition: String, Codable, CaseIterable, Sendable {
    case topLeft = "Oben Links"
    case topRight = "Oben Rechts"
    case bottomLeft = "Unten Links"
    case bottomRight = "Unten Rechts"

    public var displayName: String { rawValue }
}

public struct OSDSettings: Codable, Equatable {
    public var enabled: Bool = false
    public var position: OSDPosition = .topRight
    public var attachToWindow: Bool = true
    public var showFPS: Bool = true
    public var showRAM: Bool = true
    public var showCPU: Bool = true
    public var showGPU: Bool = true
    public var showFrameTimes: Bool = true
    public var showMediaPlayer: Bool = true
    public var showLogging: Bool = true
    public var opacity: Double = 0.6
    public var fontSize: Double = 13
    public var verticalOffset: Double = 0
    public var isLocked: Bool = false

    public init() {}
}
