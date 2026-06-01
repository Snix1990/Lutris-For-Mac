import Foundation

struct CrossOverInstallation: Identifiable, Codable {
    let id: UUID
    var name: String
    var path: String
    var isCXPatch: Bool
    var version: String

    init(id: UUID = UUID(), name: String, path: String, isCXPatch: Bool = false, version: String = "") {
        self.id = id
        self.name = name
        self.path = path
        self.isCXPatch = isCXPatch
        self.version = version
    }

    var wineBinaryPath: String {
        "\(path)/Contents/SharedSupport/CrossOver/bin/wine"
    }

    var wineServerPath: String {
        "\(path)/Contents/SharedSupport/CrossOver/bin/wineserver"
    }

    var d3dMetalLibPath: String? {
        let support = "\(path)/Contents/SharedSupport/CrossOver"
        let candidates = [
            "\(support)/lib/libD3DMetal.dylib",
            "\(support)/lib64/libD3DMetal.dylib",
            "\(support)/lib/wine/libD3DMetal.dylib",
            "\(support)/lib64/wine/libD3DMetal.dylib",
            "\(path)/Contents/Frameworks/libD3DMetal.dylib",
            "\(path)/Contents/Frameworks/libD3DMetal.framework/libD3DMetal",
        ]
        if let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            return found
        }
        // Fallback: alle .dylib-Dateien im Framework-Verzeichnis scannen
        let fm = FileManager.default
        let libDirs = ["\(support)/lib", "\(support)/lib64", "\(path)/Contents/Frameworks"]
        for dir in libDirs {
            guard let files = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            if let match = files.first(where: { $0.lowercased().contains("d3dmetal") }) {
                return "\(dir)/\(match)"
            }
            // Auch Unterordner prüfen
            for file in files {
                var isDir: ObjCBool = false
                let filePath = "\(dir)/\(file)"
                guard fm.fileExists(atPath: filePath, isDirectory: &isDir), isDir.boolValue else { continue }
                guard let subfiles = try? fm.contentsOfDirectory(atPath: filePath) else { continue }
                if let match = subfiles.first(where: { $0.lowercased().contains("d3dmetal") }) {
                    return "\(filePath)/\(match)"
                }
            }
        }
        return nil
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: path) &&
        FileManager.default.isExecutableFile(atPath: wineBinaryPath)
    }

    static func detectVersion(from path: String) -> String {
        let plistPath = "\(path)/Contents/Info.plist"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: plistPath)),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let version = plist["CFBundleShortVersionString"] as? String else {
            return ""
        }
        return version
    }

    static func standardPaths() -> [String] {
        [
            "/Applications/CrossOver.app",
        ]
    }
}
