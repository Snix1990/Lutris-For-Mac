import Foundation

struct InstallerScript: Codable, Identifiable {
    let id: UUID
    var name: String
    var gameName: String
    var version: String
    var runner: String
    var platform: String
    var description: String
    var tasks: [InstallTask]
    var environmentVariables: [String: String]
    var requires: [String] // Benötigte Runner

    enum InstallTask: Codable {
        case mkdir(path: String, description: String?)
        case download(url: String, dest: String, description: String?)
        case extract(archive: String, dest: String, type: ExtractType?, description: String?)
        case execute(command: String, description: String?)
        case wineExecute(executable: String, args: String?, winePrefix: String?, winePath: String?, description: String?)
        case wineTricks(verbs: [String], prefixPath: String?, winePath: String?, description: String?)
        case wineCfg(description: String?)
        case createPrefix(name: String?, arch: String, prefixPath: String?, winePath: String?, description: String?)
        case setEnvironment(key: String, value: String, description: String?)
        case message(text: String, description: String?)
        case input(prompt: String, variable: String, default: String?, description: String?)

        enum CodingKeys: String, CodingKey {
            case type, path, dest, archive, url, executable, args, key, value
            case name, arch, command, text, prompt, variable, `default`
            case description, winePrefix, type_raw
            case prefixPath, winePath, verbs
        }

        enum ExtractType: String, Codable {
            case zip, tarGz = "tar.gz", tarBz2 = "tar.bz2", tarXz = "tar.xz", dmg, sevenZip = "7z", rar
        }

        enum TaskType: String, Codable {
            case mkdir, download, extract, execute, wineExecute, wineTricks, wineCfg, createPrefix, setEnvironment, message, input
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(TaskType.self, forKey: .type)
            let desc = try container.decodeIfPresent(String.self, forKey: .description)

            switch type {
            case .mkdir:
                let path = try container.decode(String.self, forKey: .path)
                self = .mkdir(path: path, description: desc)
            case .download:
                let url = try container.decode(String.self, forKey: .url)
                let dest = try container.decode(String.self, forKey: .dest)
                self = .download(url: url, dest: dest, description: desc)
            case .extract:
                let archive = try container.decode(String.self, forKey: .archive)
                let dest = try container.decode(String.self, forKey: .dest)
                let type = try container.decodeIfPresent(ExtractType.self, forKey: .type_raw)
                self = .extract(archive: archive, dest: dest, type: type, description: desc)
            case .execute:
                let command = try container.decode(String.self, forKey: .command)
                self = .execute(command: command, description: desc)
            case .wineExecute:
                let executable = try container.decode(String.self, forKey: .executable)
                let args = try container.decodeIfPresent(String.self, forKey: .args)
                let prefix = try container.decodeIfPresent(String.self, forKey: .winePrefix)
                let winePath = try container.decodeIfPresent(String.self, forKey: .winePath)
                self = .wineExecute(executable: executable, args: args, winePrefix: prefix, winePath: winePath, description: desc)
            case .wineTricks:
                // verbs can be provided as single string (space separated) or as array
                var verbsArr: [String] = []
                if let v = try? container.decode([String].self, forKey: .verbs) {
                    verbsArr = v
                } else if let v = try? container.decodeIfPresent(String.self, forKey: .command) {
                    verbsArr = v.split(separator: " ").map { String($0) }
                } else if let _ = try? container.decodeIfPresent(String.self, forKey: .description) {
                    // fallback: no verbs
                    verbsArr = []
                }
                let prefixPath = try container.decodeIfPresent(String.self, forKey: .prefixPath)
                let winePath = try container.decodeIfPresent(String.self, forKey: .winePath)
                self = .wineTricks(verbs: verbsArr, prefixPath: prefixPath, winePath: winePath, description: desc)
            case .wineCfg:
                self = .wineCfg(description: desc)
            case .createPrefix:
                let name = try container.decodeIfPresent(String.self, forKey: .name)
                let arch = try container.decode(String.self, forKey: .arch)
                let prefixPath = try container.decodeIfPresent(String.self, forKey: .prefixPath)
                let winePath = try container.decodeIfPresent(String.self, forKey: .winePath)
                self = .createPrefix(name: name, arch: arch, prefixPath: prefixPath, winePath: winePath, description: desc)
            case .setEnvironment:
                let key = try container.decode(String.self, forKey: .key)
                let value = try container.decode(String.self, forKey: .value)
                self = .setEnvironment(key: key, value: value, description: desc)
            case .message:
                let text = try container.decode(String.self, forKey: .text)
                self = .message(text: text, description: desc)
            case .input:
                let prompt = try container.decode(String.self, forKey: .prompt)
                let variable = try container.decode(String.self, forKey: .variable)
                let def = try container.decodeIfPresent(String.self, forKey: .default)
                self = .input(prompt: prompt, variable: variable, default: def, description: desc)
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            switch self {
            case .mkdir(let path, let desc):
                try container.encode(TaskType.mkdir, forKey: .type)
                try container.encode(path, forKey: .path)
                try container.encodeIfPresent(desc, forKey: .description)
            case .download(let url, let dest, let desc):
                try container.encode(TaskType.download, forKey: .type)
                try container.encode(url, forKey: .url)
                try container.encode(dest, forKey: .dest)
                try container.encodeIfPresent(desc, forKey: .description)
            case .extract(let archive, let dest, let type, let desc):
                try container.encode(TaskType.extract, forKey: .type)
                try container.encode(archive, forKey: .archive)
                try container.encode(dest, forKey: .dest)
                try container.encodeIfPresent(type, forKey: .type_raw)
                try container.encodeIfPresent(desc, forKey: .description)
            case .execute(let command, let desc):
                try container.encode(TaskType.execute, forKey: .type)
                try container.encode(command, forKey: .command)
                try container.encodeIfPresent(desc, forKey: .description)
            case .wineExecute(let executable, let args, let prefix, let winePath, let desc):
                try container.encode(TaskType.wineExecute, forKey: .type)
                try container.encode(executable, forKey: .executable)
                try container.encodeIfPresent(args, forKey: .args)
                try container.encodeIfPresent(prefix, forKey: .winePrefix)
                try container.encodeIfPresent(winePath, forKey: .winePath)
                try container.encodeIfPresent(desc, forKey: .description)
            case .wineTricks(let verbs, let prefixPath, let winePath, let desc):
                try container.encode(TaskType.wineTricks, forKey: .type)
                try container.encodeIfPresent(verbs, forKey: .verbs)
                try container.encodeIfPresent(prefixPath, forKey: .prefixPath)
                try container.encodeIfPresent(winePath, forKey: .winePath)
                try container.encodeIfPresent(desc, forKey: .description)
            case .wineCfg(let desc):
                try container.encode(TaskType.wineCfg, forKey: .type)
                try container.encodeIfPresent(desc, forKey: .description)
            case .createPrefix(let name, let arch, let prefixPath, let winePath, let desc):
                try container.encode(TaskType.createPrefix, forKey: .type)
                try container.encodeIfPresent(name, forKey: .name)
                try container.encode(arch, forKey: .arch)
                try container.encodeIfPresent(prefixPath, forKey: .prefixPath)
                try container.encodeIfPresent(winePath, forKey: .winePath)
                try container.encodeIfPresent(desc, forKey: .description)
            case .setEnvironment(let key, let value, let desc):
                try container.encode(TaskType.setEnvironment, forKey: .type)
                try container.encode(key, forKey: .key)
                try container.encode(value, forKey: .value)
                try container.encodeIfPresent(desc, forKey: .description)
            case .message(let text, let desc):
                try container.encode(TaskType.message, forKey: .type)
                try container.encode(text, forKey: .text)
                try container.encodeIfPresent(desc, forKey: .description)
            case .input(let prompt, let variable, let def, let desc):
                try container.encode(TaskType.input, forKey: .type)
                try container.encode(prompt, forKey: .prompt)
                try container.encode(variable, forKey: .variable)
                try container.encodeIfPresent(def, forKey: .default)
                try container.encodeIfPresent(desc, forKey: .description)
            }
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        gameName: String = "",
        version: String = "1.0",
        runner: String = "Native",
        platform: String = "macOS",
        description: String = "",
        tasks: [InstallTask] = [],
        environmentVariables: [String: String] = [:],
        requires: [String] = []
    ) {
        self.id = id
        self.name = name
        self.gameName = gameName
        self.version = version
        self.runner = runner
        self.platform = platform
        self.description = description
        self.tasks = tasks
        self.environmentVariables = environmentVariables
        self.requires = requires
    }

    // MARK: - Beispiel-Scripte

    static let samples: [InstallerScript] = [
        InstallerScript(
            name: "Einfache .app installieren",
            gameName: "Mein Spiel",
            runner: "Native",
            platform: "macOS",
            description: "Lädt eine .app herunter und kopiert sie nach /Applications",
            tasks: [
                .input(prompt: "Download-URL (.app/.dmg)", variable: "appUrl", default: "", description: nil),
                .download(url: "{appUrl}", dest: "{tmp}/download", description: "Lade Spiel herunter"),
                .extract(archive: "{tmp}/download", dest: "{tmp}/extracted", type: nil, description: "Extrahiere Archiv"),
                .execute(command: "cp -R \"{tmp}/extracted/*.app\" /Applications/", description: "Kopiere nach /Applications"),
                .message(text: "Installation abgeschlossen!", description: nil)
            ]
        ),
        InstallerScript(
            name: "Wine-Spiel installieren",
            gameName: "Windows Spiel",
            runner: "Wine",
            platform: "Windows",
            description: "Erstellt Wineprefix, lädt Installer und führt ihn aus",
            tasks: [
                .input(prompt: "Setup.exe URL", variable: "setupUrl", default: nil, description: nil),
                .createPrefix(name: "{gameName}-prefix", arch: "win64", prefixPath: nil, winePath: nil, description: "Erstelle Wineprefix"),
                .download(url: "{setupUrl}", dest: "{tmp}/setup.exe", description: "Lade Installer herunter"),
                .wineExecute(executable: "{tmp}/setup.exe", args: "/SILENT", winePrefix: "{gameName}-prefix", winePath: nil, description: "Führe Installer aus"),
                .message(text: "Installation abgeschlossen! Spiel ist bereit.", description: nil)
            ],
            requires: ["Wine"]
        ),
        InstallerScript(
            name: "DOSBox-Spiel",
            gameName: "DOS Spiel",
            runner: "DOSBox",
            platform: "DOS",
            description: "Lädt ein DOS-Spiel herunter und konfiguriert DOSBox",
            tasks: [
                .input(prompt: "Download-URL", variable: "gameUrl", default: nil, description: nil),
                .download(url: "{gameUrl}", dest: "{tmp}/game.zip", description: "Lade Spiel herunter"),
                .extract(archive: "{tmp}/game.zip", dest: "{gamePath}", type: .zip, description: "Extrahiere Spiel"),
                .mkdir(path: "{gamePath}/dosbox_conf", description: "Erstelle DOSBox-Konfiguration"),
                .message(text: "Spiel bereit. Starte es mit DOSBox.", description: nil)
            ]
        ),
        InstallerScript(
            name: "RetroArch Core + ROM",
            gameName: "Retro Spiel",
            runner: "RetroArch",
            platform: "Multi",
            description: "Installiert ein ROM für RetroArch",
            tasks: [
                .input(prompt: "ROM-Datei-URL", variable: "romUrl", default: nil, description: nil),
                .input(prompt: "RetroArch-Core (z.B. genesis_plus_gx)", variable: "coreName", default: "genesis_plus_gx", description: nil),
                .download(url: "{romUrl}", dest: "{gamePath}/rom", description: "Lade ROM herunter"),
                .message(text: "ROM installiert. Starte es mit RetroArch + {coreName}.", description: nil)
            ],
            requires: ["RetroArch"]
        ),
    ]
}
