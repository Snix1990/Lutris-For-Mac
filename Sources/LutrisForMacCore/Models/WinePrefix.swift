import Foundation

public struct WinePrefix: Identifiable, Hashable, Codable {
    public let id: UUID
    public var name: String
    public var path: String
    public var architecture: WineArch
    public var windowsVersion: String
    public var created: Date
    public var lastUsed: Date?

    public enum WineArch: String, Codable, CaseIterable {
        case win32 = "win32"
        case win64 = "win64"

        public var displayName: String {
            switch self {
            case .win32: return "32-Bit (win32)"
            case .win64: return "64-Bit (win64)"
            }
        }
    }

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        architecture: WineArch = .win64,
        windowsVersion: String = "win10",
        created: Date = Date(),
        lastUsed: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.architecture = architecture
        self.windowsVersion = windowsVersion
        self.created = created
        self.lastUsed = lastUsed
    }
}
