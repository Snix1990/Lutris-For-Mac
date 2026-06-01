import Foundation

struct WinePrefix: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var path: String
    var architecture: WineArch
    var windowsVersion: String
    var created: Date
    var lastUsed: Date?

    enum WineArch: String, Codable, CaseIterable {
        case win32 = "win32"
        case win64 = "win64"

        var displayName: String {
            switch self {
            case .win32: return "32-Bit (win32)"
            case .win64: return "64-Bit (win64)"
            }
        }
    }

    init(
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
