import Foundation

public struct RomFolderConfig: Identifiable, Codable, Equatable {
    public var id = UUID()
    public var platform: String
    public var path: String
}

@MainActor
public final class RomFolderManager: ObservableObject {
    public static let shared = RomFolderManager()

    @Published public var folders: [RomFolderConfig] = []

    private let fm = FileManager.default

    private var storageURL: URL {
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("LutrisForMac/rom_folders.json")
    }

    private init() {
        load()
    }

    public func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([RomFolderConfig].self, from: data) else {
            folders = []
            return
        }
        folders = decoded
    }

    public func save() {
        try? fm.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try? JSONEncoder().encode(folders)
        try? data?.write(to: storageURL)
    }

    public func addFolder(platform: String, path: String) {
        if !folders.contains(where: { $0.platform == platform && $0.path == path }) {
            folders.append(RomFolderConfig(platform: platform, path: path))
            save()
        }
    }

    public func removeFolder(_ id: UUID) {
        folders.removeAll { $0.id == id }
        save()
    }

    public func scanROMs(progress: @escaping (Double) -> Void = { _ in }) -> [String: [URL]] {
        var result: [String: [URL]] = [:]
        let romExtensions: Set<String> = [
            "3ds", "a26", "a52", "a78", "bin", "bs", "cgb", "chd", "cia", "col", "com",
            "cso", "cue", "dsk", "fds", "gba", "gbc", "gb", "gcm", "gdi", "gen", "gg",
            "gba", "gbc", "gb", "gdi", "gg", "gcm", "int", "ipf", "iso", "j64", "lnx",
            "m3u", "md", "mdf", "mds", "min", "msx", "n64", "nds", "nes", "nkit",
            "nps", "nsp", "pce", "pcf", "pco", "pkb", "pbp", "ps1", "psx", "psexe",
            "rp9", "rvz", "sg", "smc", "smd", "sms", "sfc", "sgb", "sgb2", "sl",
            "spa", "st", "st2", "stb", "swc", "tap", "t64", "tgc", "to8", "trs",
            "uae", "v64", "vb", "vec", "vfd", "wbfs", "wim", "wsc", "xci", "xdf",
            "z64", "z80", "zds", "zip"
        ]

        let total = Double(folders.count)
        for (idx, folder) in folders.enumerated() {
            progress(Double(idx) / total)
            let url = URL(fileURLWithPath: folder.path)
            guard fm.fileExists(atPath: url.path) else { continue }
            guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) else { continue }
            for case let fileURL as URL in enumerator {
                let ext = fileURL.pathExtension.lowercased()
                if romExtensions.contains(ext) {
                    result[folder.platform, default: []].append(fileURL)
                }
            }
        }
        progress(1)

        return result
    }

    public static var availablePlatforms: [String] {
        let allPlatforms = Emulator.all.flatMap(\.supportsPlatforms)
        return Array(Set(allPlatforms)).sorted()
    }
}
