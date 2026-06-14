import Foundation
import AppKit

@MainActor
final class WineManager: ObservableObject {
    static let shared = WineManager()

    @Published var installedVersions: [WineVersion] = []
    @Published var prefixes: [WinePrefix] = []
    @Published var crossOverInstallations: [CrossOverInstallation] = []
    @Published var isDownloading = false
    @Published var downloadProgress: Double? = 0
    @Published var isDownloadingToCache = false
    @Published var cacheDownloadProgress: Double? = 0

    private let versionsFile: URL
    private let prefixesFile: URL
    private let crossOverFile: URL
    private let runnersDir: URL
    private let prefixesDir: URL
    private let wineCacheDir: URL

    static var allKnownDownloads: [WineDownloadInfo] {
        knownDownloads
    }

    private static let knownDownloads: [WineDownloadInfo] = {
        let pairs: [(name: String, displayName: String, urlString: String, type: WineVersion.WineSource)] = [
            ("Wine-Crossover 24.0.1", "Wine Crossover 24.0.1 (Apple Silicon)",
             "https://github.com/Gcenx/wine-on-mac/releases/download/24.0.1/wine-crossover-24.0.1-macos-arm64.tar.xz", .downloaded),
            ("Wine-Crossover 23.7.1", "Wine Crossover 23.7.1 (Intel)",
             "https://github.com/Gcenx/wine-on-mac/releases/download/23.7.1/wine-crossover-23.7.1-macos-x86_64.tar.xz", .downloaded),
            ("Wine-Devel 9.22", "Wine Devel 9.22 (Apple Silicon)",
             "https://github.com/Gcenx/wine-on-mac/releases/download/9.22/wine-devel-9.22-macos-arm64.tar.xz", .downloaded),
            ("Wine-Devel 9.22 (Intel)", "Wine Devel 9.22 (Intel)",
             "https://github.com/Gcenx/wine-on-mac/releases/download/9.22/wine-devel-9.22-macos-x86_64.tar.xz", .downloaded),
            ("Wine-Stable 9.0", "Wine Stable 9.0 (Apple Silicon)",
             "https://github.com/Gcenx/wine-on-mac/releases/download/9.0/wine-stable-9.0-macos-arm64.tar.xz", .downloaded),
            ("Wine-Stable 9.0 (Intel)", "Wine Stable 9.0 (Intel)",
             "https://github.com/Gcenx/wine-on-mac/releases/download/9.0/wine-stable-9.0-macos-x86_64.tar.xz", .downloaded),
            ("Wine-Crossover 11.0-1", "Wine Crossover 11.0-1 (Yaagl, signed, MF patches)",
             "https://github.com/yaagl/anime-game-wine/releases/download/wine-crossover-11.0-1-signed/wine-crossover-11.0-1-osx64-signed.tar.xz", .yaagl),
            ("Wine-Devel 11.8", "Wine Devel 11.8 (Yaagl, signed)",
             "https://github.com/yaagl/anime-game-wine/releases/download/wine-11.8-signed/wine-devel-11.8-osx64-signed.tar.xz", .yaagl),
        ]
        return pairs.compactMap { (name, displayName, urlString, type) in
            guard let url = URL(string: urlString) else {
                assertionFailure("Invalid Wine download URL: \(urlString)")
                return nil
            }
            return WineDownloadInfo(name: name, displayName: displayName, url: url, type: type)
        }
    }()

    var availableDownloads: [WineDownloadInfo] {
        Self.knownDownloads.filter { dl in
            !installedVersions.contains(where: { $0.name == dl.name })
        }
    }

    var cachedDownloadNames: [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: wineCacheDir.path)) ?? []
        return files.compactMap { name -> String? in
            guard name.hasSuffix(".tar.xz") else { return nil }
            let key = String(name.dropLast(7))
            return key.removingPercentEncoding ?? key
        }
    }

    func isCached(_ name: String) -> Bool {
        let safeName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        return FileManager.default.fileExists(atPath: wineCacheDir.appendingPathComponent("\(safeName).tar.xz").path)
    }

    func archivePathInCache(_ name: String) -> URL {
        let safeName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        return wineCacheDir.appendingPathComponent("\(safeName).tar.xz")
    }

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LutrisForMac", isDirectory: true)
        runnersDir = support.appendingPathComponent("runners/wine", isDirectory: true)
        prefixesDir = support.appendingPathComponent("prefixes", isDirectory: true)
        wineCacheDir = support.appendingPathComponent("wine-cache", isDirectory: true)
        versionsFile = support.appendingPathComponent("wine_versions.json")
        prefixesFile = support.appendingPathComponent("wine_prefixes.json")
        crossOverFile = support.appendingPathComponent("crossover_installations.json")

        try? FileManager.default.createDirectory(at: runnersDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: prefixesDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: wineCacheDir, withIntermediateDirectories: true)

        loadVersions()
        loadPrefixes()
        loadCrossOverInstallations()
        importCrossOverBottles()
        detectSystemWine()
    }

    // MARK: - Wine-Versionen erkennen

    func refresh() {
        loadVersions()
        loadPrefixes()
        loadCrossOverInstallations()
        importCrossOverBottles()
        detectSystemWine()
    }

    private func loadVersions() {
        guard let data = try? Data(contentsOf: versionsFile),
              let versions = try? JSONDecoder().decode([WineVersion].self, from: data) else { return }
        installedVersions = versions
    }

    private func saveVersions() {
        guard let data = try? JSONEncoder().encode(installedVersions) else { return }
        try? data.write(to: versionsFile, options: .atomic)
    }

    private func loadPrefixes() {
        guard let data = try? Data(contentsOf: prefixesFile),
              let loaded = try? JSONDecoder().decode([WinePrefix].self, from: data) else { return }
        prefixes = loaded
    }

    func savePrefixes() {
        guard let data = try? JSONEncoder().encode(prefixes) else { return }
        try? data.write(to: prefixesFile, options: .atomic)
    }

    // MARK: - CrossOver-Bottles importieren

    func importCrossOverBottles() {
        let bottlesDirs = [
            "\(NSHomeDirectory())/Library/Application Support/CrossOver/Bottles",
        ]

        prefixes.removeAll { $0.name.hasPrefix("CrossOver: ") && !FileManager.default.fileExists(atPath: $0.path) }

        for bottlesDir in bottlesDirs {
            guard FileManager.default.fileExists(atPath: bottlesDir),
                  let entries = try? FileManager.default.contentsOfDirectory(atPath: bottlesDir) else { continue }

            for bottleName in entries {
                let bottlePath = "\(bottlesDir)/\(bottleName)"
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: bottlePath, isDirectory: &isDir), isDir.boolValue,
                      FileManager.default.fileExists(atPath: "\(bottlePath)/drive_c") else { continue }

                let prefixName = "CrossOver: \(bottleName)"
                guard !prefixes.contains(where: { $0.path == bottlePath }) else { continue }

                let arch = detectCrossOverArch(from: bottlePath)
                let windowsVersion = detectCrossOverWinVersion(from: bottlePath)

                let attributes = try? FileManager.default.attributesOfItem(atPath: bottlePath)
                let created = attributes?[.creationDate] as? Date ?? Date()

                let prefix = WinePrefix(
                    name: prefixName,
                    path: bottlePath,
                    architecture: arch,
                    windowsVersion: windowsVersion,
                    created: created
                )
                prefixes.append(prefix)
            }
        }
        savePrefixes()
    }

    private func detectCrossOverArch(from bottlePath: String) -> WinePrefix.WineArch {
        guard let reg = try? String(contentsOfFile: "\(bottlePath)/system.reg", encoding: .utf8) else {
            return .win64
        }
        if reg.contains("#arch=win32") { return .win32 }
        return .win64
    }

    private func detectCrossOverWinVersion(from bottlePath: String) -> String {
        guard let reg = try? String(contentsOfFile: "\(bottlePath)/system.reg", encoding: .utf8) else {
            return "win10"
        }
        if reg.contains("\"ProductName\"=\"Windows 11\"") || reg.contains("\"CurrentVersion\"=\"10.0\"") {
            return "win11"
        }
        if reg.contains("\"ProductName\"=\"Windows 10\"") {
            return "win10"
        }
        if reg.contains("\"ProductName\"=\"Windows 8") {
            return "win8"
        }
        if reg.contains("\"ProductName\"=\"Windows 7\"") {
            return "win7"
        }
        return "win10"
    }

    // MARK: - Spiele aus CrossOver-Bottles scannen (via Registry)

    struct CrossOverGameCandidate {
        let name: String
        let exePath: String?
        let bottleName: String
    }

    func scanCrossOverBottlesForGames() -> [CrossOverGameCandidate] {
        var candidates: [CrossOverGameCandidate] = []

        // Vollständige Filterliste basierend auf Winetricks-Verben (556 Einträge)
        // Alle Komponenten, die Winetricks installieren kann, sind keine Spiele.
        // Die Liste enthält sowohl die verb-Namen als auch typische DisplayName-Fragmente.
        let knownNonGame: Set<String> = [
            // MARK: - Winetricks-DLLs (328)
            "allcodecs", "amstream", "art2kmin", "art2k7min", "atmlib", "avifil32",
            "binkw32",
            "cabinet", "cinepak", "cnc_ddraw", "comctl32", "comctl32ocx", "comdlg32ocx",
            "crypt32", "crypt32_winxp",
            "d2gl", "d3dcompiler_42", "d3dcompiler_43", "d3dcompiler_46", "d3dcompiler_47",
            "d3drm", "d3dx9", "d3dx9_24", "d3dx9_25", "d3dx9_26", "d3dx9_27", "d3dx9_28",
            "d3dx9_29", "d3dx9_30", "d3dx9_31", "d3dx9_32", "d3dx9_33", "d3dx9_34", "d3dx9_35",
            "d3dx9_36", "d3dx9_37", "d3dx9_38", "d3dx9_39", "d3dx9_40", "d3dx9_41", "d3dx9_42",
            "d3dx9_43", "d3dx10", "d3dx10_43", "d3dx11_42", "d3dx11_43", "d3dxof",
            "dbghelp", "devenum", "dinput", "dinput8", "dinputto8", "dirac",
            "directmusic", "directplay", "directshow", "directx9",
            "dmband", "dmcompos", "dmime", "dmloader", "dmscript", "dmstyle", "dmsynth",
            "dmusic", "dmusic32", "dswave",
            "dotnet10", "dotnet11", "dotnet11sp1", "dotnet20", "dotnet20sp1", "dotnet20sp2",
            "dotnet30", "dotnet30sp1", "dotnet35", "dotnet35sp1", "dotnet40",
            "dotnet40_kb2468871", "dotnet45", "dotnet452", "dotnet46", "dotnet461", "dotnet462",
            "dotnet471", "dotnet472", "dotnet48",
            "dotnet6", "dotnet7", "dotnet8", "dotnet9",
            "dotnetdesktop6", "dotnetdesktop7", "dotnetdesktop8", "dotnetdesktop9", "dotnetdesktop10",
            "dotnetcore2", "dotnetcore3", "dotnetcoredesktop3",
            "dotnet_verifier", "dpvoice", "dsdmo", "dsoal", "dsound", "dx8vb",
            "dxdiag", "dxdiagn", "dxdiagn_feb2010", "dxtrans",
            "dxvk", "dxvk_async", "dxvk_nvapi", "dxvk_nvapi0061", "dxvk_nvapi009",
            "dxvk1000", "dxvk1001", "dxvk1002", "dxvk1003", "dxvk1011",
            "dxvk1020", "dxvk1021", "dxvk1022", "dxvk1023",
            "dxvk1030", "dxvk1031", "dxvk1032", "dxvk1033", "dxvk1034",
            "dxvk1040", "dxvk1041", "dxvk1042", "dxvk1043", "dxvk1044", "dxvk1045", "dxvk1046",
            "dxvk1050", "dxvk1051", "dxvk1052", "dxvk1053", "dxvk1054", "dxvk1055",
            "dxvk1060", "dxvk1061", "dxvk1070", "dxvk1071", "dxvk1072", "dxvk1073",
            "dxvk1080", "dxvk1081", "dxvk1090", "dxvk1091", "dxvk1092", "dxvk1093", "dxvk1094",
            "dxvk1100", "dxvk1101", "dxvk1102", "dxvk1103",
            "dxvk2000", "dxvk2010", "dxvk2020", "dxvk2030", "dxvk2040", "dxvk2041",
            "dxvk2050", "dxvk2051", "dxvk2052", "dxvk2053",
            "dxvk2060", "dxvk2061", "dxvk2062", "dxvk2070", "dxvk2071",
            "esent",
            "faudio", "faudio1901", "faudio1902", "faudio1903", "faudio1904", "faudio1905", "faudio1906", "faudio190607",
            "ffdshow", "filever",
            "galliumnine", "galliumnine02", "galliumnine03", "galliumnine04", "galliumnine05",
            "galliumnine06", "galliumnine07", "galliumnine08", "galliumnine09", "galliumnine010",
            "gdiplus", "gdiplus_winxp", "gfw", "glidewrapper", "glut", "gmdls",
            "hid",
            "icodecs", "ie6", "ie7", "ie8", "ie8_kb2936068", "ie8_tls12",
            "iertutil", "itircl", "itss",
            "jet40",
            "l3codecx", "lavfilters", "lavfilters702",
            "mdac27", "mdac28", "mdx", "mf",
            "mfc40", "mfc42", "mfc70", "mfc71", "mfc80", "mfc90",
            "mfc100", "mfc110", "mfc120", "mfc140",
            "msaa", "msacm32", "msasn1", "msctf", "msdelta", "msdxmocx", "msflxgrd",
            "msftedit", "mshflxgd", "msls31", "msls31_nt4", "msmask", "mspatcha", "msscript",
            "msvcirt", "msvcrt40", "msxml3", "msxml4", "msxml6",
            "nuget",
            "ogg", "ole32", "oleaut32", "openal", "otvdm", "otvdm090",
            "pdh", "pdh_nt4", "peverify", "physx", "pngfilt", "powershell", "powershell_core", "prntvpt",
            "python26", "python27",
            "qasf", "qcap", "qdvd", "qedit", "quartz", "quartz_feb2010",
            "quicktime72", "quicktime76",
            "riched20", "riched30", "richtx32",
            "sapi", "sdl", "secur32", "setupapi", "shockwave", "speechsdk",
            "tabctl32",
            "uiribbon", "updspapi", "urlmon", "usp10",
            "vb2run", "vb3run", "vb4run", "vb5run", "vb6run",
            "vcrun6", "vcrun6sp6",
            "vcrun2003", "vcrun2005", "vcrun2008", "vcrun2010", "vcrun2012", "vcrun2013",
            "vcrun2015", "vcrun2017", "vcrun2019", "vcrun2022", "vcrun2026",
            "ucrtbase2019",
            "vjrun20",
            "vkd3d",
            "webio", "webview2", "windowscodecs", "winhttp", "wininet", "wininet_win2k",
            "wmi", "wmv9vcm", "wsh57",
            "xact", "xact_x64", "xaudio29", "xinput", "xmllite", "xna31", "xna40", "xvid",

            // MARK: - Winetricks-Fonts (42)
            "allfonts", "andale", "baekmuk", "calibri", "cambria", "candara",
            "cjkfonts", "comicsans", "consolas", "constantia", "corbel", "corefonts",
            "droid", "eufonts",
            "fakechinese", "fakejapanese", "fakejapanese_ipamona", "fakejapanese_vlgothic", "fakekorean",
            "georgia", "impact", "ipamona",
            "liberation", "lucida", "meiryo", "micross",
            "opensymbol", "pptfonts", "sourcehansans",
            "tahoma", "takao", "times", "trebuchet",
            "uff", "unifont", "verdana", "vlgothic", "webdings", "wenquanyi", "wenquanyizenhei",

            // MARK: - Winetricks-Apps (58) – keine Spiele
            "3m_library", "7zip",
            "adobe_diged", "adobe_diged4", "autohotkey",
            "busybox",
            "cmake", "colorprofile", "controlpad", "controlspy",
            "dbgview", "depends", "dxsdk_aug2006", "dxsdk_jun2010", "dxwnd",
            "emu8086",
            "firefox", "fontxplorer", "foobar2000",
            "hhw",
            "iceweasel", "irfanview",
            "kindle", "kobo",
            "mingw", "mozillabuild", "mpc", "mspaint", "mt4",
            "njcwp_trial", "njjwp_trial", "nook", "npp",
            "ollydbg110", "ollydbg200", "ollydbg201", "openwatcom",
            "procexp", "protectionid", "psdk2003", "psdkwin71",
            "safari", "sketchup", "steam",
            "ubisoftconnect", "utorrent", "utorrent3",
            "vc2005express", "vc2005expresssp1", "vc2005trial", "vc2008express", "vc2010express",
            "vlc",
            "winamp", "winrar", "wme9", "wmp9", "wmp10", "wmp11",
            "vstools2019",

            // MARK: - Winetricks-Benchmarks (8)
            "3dmark2000", "3dmark2001", "3dmark03", "3dmark05", "3dmark06",
            "stalker_pripyat_bench",
            "unigine_heaven", "wglgears",

            // MARK: - Winetricks-Settings (120)
            "alldlls", "autostart_winedbg",
            "cfc", "csmt",
            "fontfix", "fontsmooth", "forcemono",
            "grabfullscreen", "graphics", "gsm",
            "heapcheck", "hidewineexports", "hosts", "isolate_home",
            "mackeyremap", "mimeassoc", "mwo",
            "native_mdac", "native_oleaut32", "nocrashdialog",
            "npm=repack", "nt351", "nt40",
            "orm", "psm", "remove_mono",
            "renderer", "rtlm", "sandbox",
            "set_mididevice", "set_userpath",
            "shader_backend", "showdotfiles",
            "sound", "ssm",
            "theme", "useegl", "usetakefocus",
            "vd", "videomemorysize",
            "vista", "vsm", "win10", "win11", "win20", "win2k", "win2k3", "win2k8", "win2k8r2",
            "win30", "win31", "win7", "win8", "win81",
            "win95", "win98", "winme", "winver=", "winxp",
            "windowmanagerdecorated", "windowmanagermanaged",

            // MARK: - DisplayName-Fragmente (Registry Uninstall)
            "microsoft visual c++", "visual c++", "vc++", "vcredist",
            "microsoft .net", ".net framework", "dotnet",
            "microsoft directx", "directx 9", "directx 10", "directx 11", "directx 12",
            "d3dx", "xna framework", "xna redistributable",
            "microsoft xna", "xna fx",
            "microsoft games for windows", "games for windows -",
            "msxml", "microsoft xml",
            "windows sdk", "windows kits", "windows driver",
            "microsoft sql server", "microsoft sync framework",
            "microsoft report viewer", "microsoft system clr",
            "microsoft silverlight", "microsoft office",
            "microsoft edge", "microsoft onecore",
            "adobe flash", "adobe air", "adobe shockwave",
            "google update", "google chrome", "chromium",
            "mozilla maintenance", "mozilla firefox",
            "java", "python", "perl", "ruby",
            "nvidia", "amd", "intel",
            "update for windows", "security update", "hotfix for",
            "service pack", "cumulative update",
            "ie10", "ie11", "internet explorer",
            "windows malicious", "windows defender",
            "windows live", "windows mail", "windows media",
            "windows portable", "windows print",
            "power shell", "powershell",
            "c++ runtime", "c++ redistributable",
            "redistributable", "redist",
            "crossover html engine", "html engine",
            "vc_redist", "vc_redist.x64", "vc_redist.x86", "vcredist",
            "gameinput", "gaming services", "gaming runtime",
            "xbox app", "xbox game", "xbox identity",
            "xbox live", "xbox one", "xbox series",
            "xbox tcui", "xboxspeech", "xboxgip",
            "speech platform", "speech sdk",
            "visual studio", "vsto", "vstools",
            "debugging tools", "application verifier",
            "cmake", "nuget", "node.js", "npm",
            "side-by-side", "sxs",
            "openal", "physx",
            "quicktime", "itunes",
            "webview2", "edge webview2",
            "microsoft core", "onecore",
            "microsoft update", "windows update",
            "windows app", "microsoft app",
            "help viewer",
        ]

        for prefix in prefixes where prefix.name.hasPrefix("CrossOver: ") {
            let bottleName = String(prefix.name.dropFirst("CrossOver: ".count))

            let regPaths = [
                "\(prefix.path)/system.reg",
                "\(prefix.path)/user.reg",
            ]

            for regPath in regPaths {
                guard let content = try? String(contentsOfFile: regPath, encoding: .utf8) else { continue }
                let lines = content.components(separatedBy: "\n")

                var isUninstall = false
                var displayName = ""
                var displayIcon = ""
                var installLocation = ""

                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)

                    if trimmed.hasPrefix("[") {
                        // Vorherige Sektion auswerten
                        if isUninstall && !displayName.isEmpty {
                            addCandidate(name: displayName, icon: displayIcon, installLocation: installLocation, bottleName: bottleName, candidates: &candidates, knownNonGame: knownNonGame, prefixPath: prefix.path)
                        }
                        isUninstall = trimmed.localizedCaseInsensitiveContains("Uninstall")
                        displayName = ""
                        displayIcon = ""
                        installLocation = ""

                    } else if isUninstall && trimmed.hasPrefix("\"DisplayName\"=") {
                        displayName = extractRegString(trimmed)

                    } else if isUninstall && trimmed.hasPrefix("\"DisplayIcon\"=") {
                        displayIcon = extractRegString(trimmed)

                    } else if isUninstall && trimmed.hasPrefix("\"InstallLocation\"=") {
                        installLocation = extractRegString(trimmed)
                    }
                }

                if isUninstall && !displayName.isEmpty {
                    addCandidate(name: displayName, icon: displayIcon, installLocation: installLocation, bottleName: bottleName, candidates: &candidates, knownNonGame: knownNonGame, prefixPath: prefix.path)
                }
            }
        }

        return candidates
    }

    /// Wandelt einen Windows-Pfad (C:\...) in einen macOS-Pfad zum Bottle um.
    private func winePathToMac(_ winePath: String, prefixPath: String) -> String? {
        let path = winePath.replacingOccurrences(of: "\\", with: "/")
        guard let cRange = path.range(of: "C:", options: .caseInsensitive) else { return nil }
        let relative = String(path[cRange.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let fullPath = "\(prefixPath)/drive_c/\(relative)"
        return fullPath
    }

    /// Sucht nach .exe-Dateien in einem Installationsverzeichnis.
    private func findExeInDir(_ dir: String) -> String? {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return nil }
        let exeFiles = files.filter { $0.lowercased().hasSuffix(".exe") }
            .filter {
                let low = $0.lowercased()
                return !low.contains("unins") && !low.contains("setup") && !low.contains("redist")
                    && !low.contains("vcredist") && !low.contains("dotnet") && !low.contains("vc_redist")
            }
            .sorted { a, b in
                let sa = (try? fm.attributesOfItem(atPath: "\(dir)/\(a)")[.size] as? UInt64) ?? 0
                let sb = (try? fm.attributesOfItem(atPath: "\(dir)/\(b)")[.size] as? UInt64) ?? 0
                return sa > sb
            }
        if let found = exeFiles.first {
            return "\(dir)/\(found)"
        }
        // Rekursiv einen Level tiefer suchen (Program Files, Program Files (x86), etc.)
        for file in files {
            var isDir: ObjCBool = false
            let subPath = "\(dir)/\(file)"
            guard fm.fileExists(atPath: subPath, isDirectory: &isDir), isDir.boolValue else { continue }
            let subFiles = (try? fm.contentsOfDirectory(atPath: subPath)) ?? []
            let subExe = subFiles.filter { $0.lowercased().hasSuffix(".exe") }
                .filter { !$0.lowercased().contains("unins") }
                .sorted { a, b in
                    let sa = (try? fm.attributesOfItem(atPath: "\(subPath)/\(a)")[.size] as? UInt64) ?? 0
                    let sb = (try? fm.attributesOfItem(atPath: "\(subPath)/\(b)")[.size] as? UInt64) ?? 0
                    return sa > sb
                }
            if let found = subExe.first {
                return "\(subPath)/\(found)"
            }
        }
        return nil
    }

    private func findSteamExe(in prefixPath: String) -> String? {
        let candidates = [
            "\(prefixPath)/drive_c/Program Files (x86)/Steam/steam.exe",
            "\(prefixPath)/drive_c/Program Files/Steam/steam.exe",
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    private func addCandidate(name: String, icon: String, installLocation: String, bottleName: String, candidates: inout [CrossOverGameCandidate], knownNonGame: Set<String>, prefixPath: String) {
        let lower = name.lowercased()
        if knownNonGame.contains(where: { lower.contains($0) }) { return }
        if lower.hasPrefix("microsoft ") || lower == "update" || lower == "patch" { return }
        if name.count < 2 { return }
        do {
            let pattern = try Regex("^\\{[A-F0-9-]{36}\\}$").ignoresCase()
            if try pattern.firstMatch(in: name.trimmingCharacters(in: .whitespaces)) != nil { return }
        } catch {}

        // Doppelte pro Bottle vermeiden
        if candidates.contains(where: { $0.name == name && $0.bottleName == bottleName }) { return }

        // exe-Pfad ermitteln
        var exePath: String? = nil

        // 1. DisplayIcon versuchen
        if !icon.isEmpty {
            let clean = icon.replacingOccurrences(of: ",0", with: "").replacingOccurrences(of: ",1", with: "")
                .replacingOccurrences(of: ",-", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let path = winePathToMac(clean, prefixPath: prefixPath),
               FileManager.default.fileExists(atPath: path) {
                exePath = path
            }
        }

        // 2. InstallLocation versuchen (nach .exe suchen)
        if exePath == nil && !installLocation.isEmpty {
            if let dir = winePathToMac(installLocation, prefixPath: prefixPath),
               FileManager.default.fileExists(atPath: dir) {
                exePath = findExeInDir(dir)
            }
        }

        candidates.append(CrossOverGameCandidate(name: name, exePath: exePath, bottleName: bottleName))
    }

    private func extractRegString(_ line: String) -> String {
        guard let eqRange = line.range(of: "=") else { return "" }
        var raw = String(line[eqRange.upperBound...])
        if raw.hasPrefix("\"") && raw.hasSuffix("\"") {
            raw = String(raw.dropFirst().dropLast())
        }
        // Escape-Sequenzen auflösen
        raw = raw.replacingOccurrences(of: "\\\\", with: "\\")
        raw = raw.replacingOccurrences(of: "\\\"", with: "\"")
        return raw
    }

    // MARK: - CrossOver-Installationen

    private func loadCrossOverInstallations() {
        var detected: [CrossOverInstallation] = []

        for coPath in CrossOverInstallation.standardPaths() {
            guard FileManager.default.fileExists(atPath: coPath) else { continue }
            let name = URL(fileURLWithPath: coPath).lastPathComponent.replacingOccurrences(of: ".app", with: "")
            let version = CrossOverInstallation.detectVersion(from: coPath)
            let installation = CrossOverInstallation(
                name: name,
                path: coPath,
                isCXPatch: coPath.lowercased().contains("cxpatch"),
                version: version
            )
            detected.append(installation)
        }

        if let data = try? Data(contentsOf: crossOverFile),
           let saved = try? JSONDecoder().decode([CrossOverInstallation].self, from: data) {
            for userCo in saved {
                if !detected.contains(where: { $0.path == userCo.path }) {
                    detected.append(userCo)
                }
            }
        }

        crossOverInstallations = detected
    }

    private func saveCrossOverInstallations() {
        guard let data = try? JSONEncoder().encode(crossOverInstallations) else { return }
        try? data.write(to: crossOverFile, options: .atomic)
    }

    func addCrossOverInstallation(path: String) {
        guard FileManager.default.fileExists(atPath: path),
              !crossOverInstallations.contains(where: { $0.path == path }) else { return }
        let name = URL(fileURLWithPath: path).lastPathComponent.replacingOccurrences(of: ".app", with: "")
        let isCXPatch = name.lowercased().contains("cxpatch")
        let version = CrossOverInstallation.detectVersion(from: path)
        let installation = CrossOverInstallation(
            name: name,
            path: path,
            isCXPatch: isCXPatch,
            version: version
        )
        crossOverInstallations.append(installation)
        saveCrossOverInstallations()
        detectSystemWine()
    }

    func removeCrossOverInstallation(_ installation: CrossOverInstallation) {
        crossOverInstallations.removeAll { $0.id == installation.id }
        saveCrossOverInstallations()
        detectSystemWine()
    }

    func updateCrossOverInstallation(_ installation: CrossOverInstallation) {
        guard let idx = crossOverInstallations.firstIndex(where: { $0.id == installation.id }) else { return }
        crossOverInstallations[idx] = installation
        saveCrossOverInstallations()
        detectSystemWine()
    }

    private func detectSystemWine() {
        var checks: [(name: String, binaryPath: String, type: WineVersion.WineSource)] = [
            ("Homebrew (Intel)", "/usr/local/bin/wine", .homebrew),
            ("Homebrew (Apple Silicon)", "/opt/homebrew/bin/wine", .homebrew),
            ("Whisky", "\(NSHomeDirectory())/Applications/Whisky.app/Contents/Resources/wine/bin/wine", .whisky),
            ("Kegworks", "/Applications/Kegworks.app/Contents/SharedSupport/bin/wine", .wineskin),
            ("Heroic (GPTK)", "\(NSHomeDirectory())/Library/Application Support/heroic/tools/game-porting-toolkit/Game-Porting-Toolkit-latest/Contents/Resources/wine/bin/wine64", .system),
        ]

        for co in crossOverInstallations {
            guard FileManager.default.isExecutableFile(atPath: co.wineBinaryPath) else { continue }
            let displayName = co.isCXPatch ? "\(co.name) (CXPatch)" : co.name
            checks.append((displayName, co.wineBinaryPath, .crossover))
        }

        for check in checks {
            if installedVersions.contains(where: { $0.path == URL(fileURLWithPath: check.binaryPath).deletingLastPathComponent().deletingLastPathComponent().path }) {
                continue
            }
            let url = URL(fileURLWithPath: check.binaryPath)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                let wineDir = url.deletingLastPathComponent().deletingLastPathComponent()
                let version = WineVersion(
                    name: check.name.replacingOccurrences(of: " ", with: ""),
                    displayName: check.name,
                    path: wineDir.path,
                    wineBinaryPath: url.path,
                    wineServerPath: wineDir.appendingPathComponent("bin/wineserver").path,
                    type: check.type
                )
                installedVersions.append(version)
            }
        }

        // Wine im PATH suchen
        if !installedVersions.contains(where: { $0.type == .system }) {
            if let path = findWineInPath() {
                let url = URL(fileURLWithPath: path)
                let wineDir = url.deletingLastPathComponent().deletingLastPathComponent()
                installedVersions.append(WineVersion(
                    name: "SystemWine",
                    displayName: "System Wine (PATH)",
                    path: wineDir.path,
                    wineBinaryPath: url.path,
                    wineServerPath: wineDir.appendingPathComponent("bin/wineserver").path,
                    type: .system
                ))
            }
        }

        saveVersions()
    }

    private func findWineInPath() -> String? {
        let task = Process()
        task.launchPath = "/usr/bin/which"
        task.arguments = ["wine"]
        let out = Pipe()
        task.standardOutput = out
        try? task.run()
        task.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty || !FileManager.default.isExecutableFile(atPath: path) ? nil : path
    }

    // MARK: - Wine-Versionen herunterladen

    struct WineDownloadInfo: Identifiable {
        let id = UUID()
        let name: String
        let displayName: String
        let url: URL
        let type: WineVersion.WineSource
    }

    func downloadWine(_ info: WineDownloadInfo) async throws {
        isDownloading = true
        downloadProgress = 0
        defer { isDownloading = false }

        // 1. Prüfen ob Archiv bereits im Cache liegt, sonst downloaden
        let cachePath = archivePathInCache(info.name)
        if !FileManager.default.fileExists(atPath: cachePath.path) {
            let session = URLSession.shared
            let (data, _) = try await session.data(from: info.url)
            await MainActor.run { downloadProgress = 0.5 }
            try data.write(to: cachePath, options: .atomic)
        }
        await MainActor.run { downloadProgress = 0.7 }

        // 2. Aus Cache entpacken
        let destDir = runnersDir.appendingPathComponent(info.name, isDirectory: true)
        try? FileManager.default.removeItem(at: destDir)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let tarTask = Process()
        tarTask.launchPath = "/usr/bin/tar"
        tarTask.arguments = ["-xJf", cachePath.path, "-C", destDir.path, "--strip-components=1"]
        try tarTask.run()
        tarTask.waitUntilExit()

        await MainActor.run { downloadProgress = 0.9 }

        let wineBin = destDir.appendingPathComponent("bin/wine").path
        let wineServer = destDir.appendingPathComponent("bin/wineserver").path

        let version = WineVersion(
            name: info.name,
            displayName: info.displayName,
            path: destDir.path,
            wineBinaryPath: FileManager.default.isExecutableFile(atPath: wineBin) ? wineBin : "",
            wineServerPath: FileManager.default.isExecutableFile(atPath: wineServer) ? wineServer : "",
            type: .downloaded
        )
        installedVersions.append(version)
        saveVersions()
    }

    /// Lädt nur ins Cache – ohne zu entpacken. Für Vorab-Download.
    func downloadToCacheOnly(_ info: WineDownloadInfo) async throws {
        isDownloadingToCache = true
        cacheDownloadProgress = 0
        defer { isDownloadingToCache = false }

        let cachePath = archivePathInCache(info.name)
        if FileManager.default.fileExists(atPath: cachePath.path) {
            await MainActor.run { cacheDownloadProgress = 1 }
            return
        }

        let session = URLSession.shared
        let (data, _) = try await session.data(from: info.url)
        try data.write(to: cachePath, options: .atomic)
        await MainActor.run { cacheDownloadProgress = 1 }
    }

    func removeVersion(_ version: WineVersion) {
        if version.type == .downloaded {
            try? FileManager.default.removeItem(atPath: version.path)
        }
        installedVersions.removeAll { $0.id == version.id }
        saveVersions()
    }

    func removeCachedArchive(_ name: String) {
        let path = archivePathInCache(name)
        try? FileManager.default.removeItem(at: path)
    }

    // MARK: - Wineprefix-Verwaltung

    func createPrefix(name: String, architecture: WinePrefix.WineArch, wineVersion: WineVersion? = nil) async throws {
        let prefixDir = prefixesDir.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.removeItem(at: prefixDir)
        try FileManager.default.createDirectory(at: prefixDir, withIntermediateDirectories: true)

        let wine = wineVersion ?? installedVersions.first ?? installedVersions.first(where: { $0.wineBinaryPath != "" })
        guard let wine else { throw WineError.noWineVersion }
        guard FileManager.default.isExecutableFile(atPath: wine.wineBinaryPath) else {
            throw WineError.wineNotExecutable(wine.displayName)
        }

        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = prefixDir.path
        env["WINEARCH"] = architecture.rawValue
        env["WINEDLLOVERRIDES"] = "winemenubuilder.exe=d"

        let task = Process()
        task.launchPath = wine.wineBinaryPath
        task.arguments = ["wineboot", "-i"]
        task.environment = env

        try task.run()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            throw WineError.prefixCreationFailed
        }

        let prefix = WinePrefix(
            name: name,
            path: prefixDir.path,
            architecture: architecture,
            windowsVersion: "win10",
            created: Date()
        )
        prefixes.append(prefix)
        savePrefixes()
    }

    func deletePrefix(_ prefix: WinePrefix) {
        try? FileManager.default.removeItem(atPath: prefix.path)
        prefixes.removeAll { $0.id == prefix.id }
        savePrefixes()
    }

    func runWinecfg(for prefix: WinePrefix, wineVersion: WineVersion? = nil) {
        runWineTool(arguments: ["winecfg"], prefix: prefix, wineVersion: wineVersion)
    }

    func runRegedit(for prefix: WinePrefix, wineVersion: WineVersion? = nil) {
        runWineTool(arguments: ["regedit"], prefix: prefix, wineVersion: wineVersion)
    }

    func runWineTool(arguments: [String], prefix: WinePrefix, wineVersion: WineVersion? = nil) {
        let wine = wineVersion ?? installedVersions.first ?? installedVersions.first(where: { $0.wineBinaryPath != "" })
        guard let wine, FileManager.default.isExecutableFile(atPath: wine.wineBinaryPath) else { return }

        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = prefix.path
        env["WINEARCH"] = prefix.architecture.rawValue

        if wine.type == .crossover {
            let bottleName = URL(fileURLWithPath: prefix.path).lastPathComponent
            env["CX_BOTTLE"] = bottleName
        }

        let task = Process()
        task.launchPath = wine.wineBinaryPath
        task.arguments = arguments
        task.environment = env

        try? task.run()
    }

    func runWinecfg(prefixPath: String, wineVersion: WineVersion? = nil) {
        let tempPrefix = WinePrefix(name: "temp", path: prefixPath, architecture: .win64)
        runWineTool(arguments: ["winecfg"], prefix: tempPrefix, wineVersion: wineVersion)
    }

    func runWinecfg(wineBinaryPath: String, prefixPath: String) {
        let version = WineVersion(name: "custom", path: wineBinaryPath, wineBinaryPath: wineBinaryPath, type: .custom)
        let tempPrefix = WinePrefix(name: "temp", path: prefixPath, architecture: .win64)
        runWineTool(arguments: ["winecfg"], prefix: tempPrefix, wineVersion: version)
    }

    func runRegedit(prefixPath: String, wineVersion: WineVersion? = nil) {
        let tempPrefix = WinePrefix(name: "temp", path: prefixPath, architecture: .win64)
        runWineTool(arguments: ["regedit"], prefix: tempPrefix, wineVersion: wineVersion)
    }

    func runRegedit(wineBinaryPath: String, prefixPath: String) {
        let version = WineVersion(name: "custom", path: wineBinaryPath, wineBinaryPath: wineBinaryPath, type: .custom)
        let tempPrefix = WinePrefix(name: "temp", path: prefixPath, architecture: .win64)
        runWineTool(arguments: ["regedit"], prefix: tempPrefix, wineVersion: version)
    }

    // MARK: - D3DMetal / GPTK

    func detectD3DMetal() -> String? {
        var candidates = [
            "\(NSHomeDirectory())/Applications/Whisky.app/Contents/Resources/libD3DMetal.dylib",
            "/Applications/Whisky.app/Contents/Resources/libD3DMetal.dylib",
            "/usr/local/lib/libD3DMetal.dylib",
            "/opt/homebrew/lib/libD3DMetal.dylib",
            "\(NSHomeDirectory())/Library/Application Support/CrossOver/libD3DMetal.dylib",
            "\(NSHomeDirectory())/.wine/lib/libD3DMetal.dylib",
            "\(NSHomeDirectory())/Library/Application Support/heroic/tools/game-porting-toolkit/Game-Porting-Toolkit-latest/Contents/Resources/wine/lib/external/D3DMetal.framework/Versions/A/D3DMetal",
        ]
        for co in crossOverInstallations {
            if let path = co.d3dMetalLibPath {
                candidates.append(path)
            }
        }
        // Check ob einer der Kandidaten existiert
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            print("[WineManager] D3DMetal found at: \(path)")
            return path
        }
        // Fallback: global Spotlight-Suche
        if !candidates.contains(where: { FileManager.default.fileExists(atPath: $0) }) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
            task.arguments = ["-name", "libD3DMetal.dylib", "-onlyin", "/Applications", "-onlyin", NSHomeDirectory()]
            let pipe = Pipe()
            task.standardOutput = pipe
            try? task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
                if let first = lines.first, FileManager.default.fileExists(atPath: first) {
                    print("[WineManager] D3DMetal found via Spotlight: \(first)")
                    return first
                }
            }
        }
        print("[WineManager] D3DMetal NOT found. Candidates checked: \(candidates)")
        return nil
    }

    func gptkDLLDirectory() -> String? {
        let candidates: [String] = {
            var dirs: [String] = []
            // CrossOver
            for co in crossOverInstallations {
                let support = "\(co.path)/Contents/SharedSupport/CrossOver"
                dirs.append("\(support)/lib/wine/x86_64-windows")
                dirs.append("\(support)/lib64/wine/x86_64-windows")
            }
            // Heroic GPTK
            dirs.append("\(NSHomeDirectory())/Library/Application Support/heroic/tools/game-porting-toolkit/Game-Porting-Toolkit-latest/Contents/Resources/wine/lib/wine/x86_64-windows")
            // Whisky
            dirs.append("\(NSHomeDirectory())/Applications/Whisky.app/Contents/Resources/lib/wine/x86_64-windows")
            dirs.append("/Applications/Whisky.app/Contents/Resources/lib/wine/x86_64-windows")
            // Homebrew GPTK
            dirs.append("/opt/homebrew/lib/wine/x86_64-windows")
            // Spotlight-Fallback
            return dirs
        }()
        for dir in candidates {
            let fm = FileManager.default
            guard fm.fileExists(atPath: dir) else { continue }
            let files = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
            if files.contains(where: { $0.lowercased() == "nvngx.dll" || $0.lowercased() == "nvngx-on-metalfx.dll" }) {
                return dir
            }
        }
        return nil
    }

    func deployDLSSDLLs(for game: Game) throws {
        guard let srcDir = gptkDLLDirectory() else {
            throw WineError.gptkNotFound
        }
        guard let prefixPath = game.winePrefixPath, !prefixPath.isEmpty else {
            return
        }
        let system32 = "\(prefixPath)/drive_c/windows/system32"
        guard FileManager.default.fileExists(atPath: system32) else { return }
        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(atPath: srcDir)
        let copy: (String, String) throws -> Void = { src, dst in
            if fm.fileExists(atPath: dst) { try fm.removeItem(atPath: dst) }
            try fm.copyItem(atPath: src, toPath: dst)
        }
        if let nvngx = files.first(where: { $0.lowercased() == "nvngx.dll" }) {
            try copy("\(srcDir)/\(nvngx)", "\(system32)/nvngx.dll")
        } else if let nvngxOnMetalFX = files.first(where: { $0.lowercased() == "nvngx-on-metalfx.dll" }) {
            try copy("\(srcDir)/\(nvngxOnMetalFX)", "\(system32)/nvngx.dll")
        }
        if let nvapi = files.first(where: { $0.lowercased() == "nvapi64.dll" }) {
            try copy("\(srcDir)/\(nvapi)", "\(system32)/nvapi64.dll")
        }
    }

    func removeDLSSDLLs(for game: Game) {
        guard let prefixPath = game.winePrefixPath, !prefixPath.isEmpty else { return }
        let system32 = "\(prefixPath)/drive_c/windows/system32"
        let fm = FileManager.default
        for dll in ["nvngx.dll", "nvapi64.dll"] {
            let path = "\(system32)/\(dll)"
            if fm.fileExists(atPath: path) {
                try? fm.removeItem(atPath: path)
            }
        }
    }

    func prefixForGame(_ game: Game) -> WinePrefix? {
        if let id = game.winePrefixID {
            return prefixes.first(where: { $0.id == id })
        }
        if let name = game.winePrefixName {
            return prefixes.first(where: { $0.name == name })
        }
        if let path = game.winePrefixPath, !path.isEmpty {
            return prefixes.first(where: { $0.path == path })
        }
        return nil
    }

    // MARK: - Wine-Umgebung bauen

    func wineEnvironment(for game: Game, prefix: WinePrefix? = nil, wineVersion: WineVersion? = nil) -> [String: String] {
        var env: [String: String] = [:]

        if let p = prefix ?? prefixForGame(game) {
            env["WINEPREFIX"] = p.path
            env["WINEARCH"] = p.architecture.rawValue
        } else if let prefixPath = game.winePrefixPath, !prefixPath.isEmpty {
            env["WINEPREFIX"] = prefixPath
        }
        if let arch = game.wineArchitecture, env["WINEARCH"] == nil {
            env["WINEARCH"] = arch
        }

        var overrides = "winemenubuilder.exe=d"

        let renderMode: WineRenderMode
        if game.wineRenderMode == .auto {
            renderMode = detectD3DMetal() != nil ? .d3dMetal : .dxvkMoltenVK
        } else {
            renderMode = game.wineRenderMode
        }

        switch renderMode {
        case .d3dMetal:
            overrides += ";d3d10,d3d10_1,d3d10core,d3d11,d3d12=n,b"
            if let d3dmetalPath = detectD3DMetal() {
                env["D3DMETAL_LIB"] = d3dmetalPath
                // GPTK d3d12.so sucht D3DMetal.framework via dlopen() – DYLD_FRAMEWORK_PATH setzen
                let frameworkDir = URL(fileURLWithPath: d3dmetalPath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                let currentFw = env["DYLD_FRAMEWORK_PATH"] ?? ""
                let fwPath = frameworkDir.path
                if !currentFw.contains(fwPath) {
                    env["DYLD_FRAMEWORK_PATH"] = currentFw.isEmpty ? fwPath : "\(fwPath):\(currentFw)"
                }

            }
            env["D3DMETAL_SHADER_CACHE"] = game.wineShaderCache ? "1" : "0"
            env["D3DMETAL_LOG"] = "0"

        case .dxvkMoltenVK:
            overrides += ";d3d9,d3d10,d3d10_1,d3d10core,d3d11=n,b"
            env["DXVK_HUD"] = "0"
            env["MVK_CONFIG_LOG_LEVEL"] = "0"
            env["MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS"] = "1"
            if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let shaderDir = appSupport.appendingPathComponent("LutrisForMac/dxvk_shader_cache")
                try? FileManager.default.createDirectory(at: shaderDir, withIntermediateDirectories: true)
                env["DXVK_STATE_CACHE_PATH"] = shaderDir.path
            }

        case .auto:
            break
        }

        env["WINEDLLOVERRIDES"] = overrides

        if !game.wineAudioDriver.isEmpty {
            env["WINEAUDIO"] = game.wineAudioDriver
        }

        if let msync = game.wineMSync, msync {
            env["WINE_MSYNC_DISABLE"] = "0"
        } else {
            if game.wineESync { env["WINEESYNC"] = "1" }
            if game.wineFSync { env["WINEFSYNC"] = "1" }
        }

        // CX_BOTTLE für CrossOver wine binary (Perl-Wrapper benötigt Bottle-Name)
        if wineVersion?.type == .crossover, let p = prefix ?? prefixForGame(game) {
            let bottleName = URL(fileURLWithPath: p.path).lastPathComponent
            env["CX_BOTTLE"] = bottleName
        }

        if game.wineDesktopMode && !game.wineDesktopResolution.isEmpty {
            env["WINEVIRTUALDESKTOP"] = game.wineDesktopResolution
        }

        // WINEDEBUG (per game runtimeSettings)
        if game.runtimeSettings.wineDebugLogging {
            let debugString: String
            if !game.wineDebugString.isEmpty {
                debugString = game.wineDebugString
            } else {
                debugString = WineDebugManager.shared.resolvedDebugString()
            }
            if !debugString.isEmpty {
                env["WINEDEBUG"] = debugString
            }
        }

        // DXVK HUD
        if game.wineDxvkHud && game.wineRenderMode == .dxvkMoltenVK {
            env["DXVK_HUD"] = "fps,frametimes,devinfo,api,version"
        }

        if game.wineDLSS {
            env["D3DM_ENABLE_METALFX"] = "1"
        }

        return env
    }

    // MARK: - Game starten

    func launchGame(game: Game) async throws -> String {
        let useEmulator = game.steamEmulatorEnabled == true &&
                          (game.steamAppID?.isEmpty == false) &&
                          !game.installPath.hasPrefix("steam://")

        // Steam Emulator anwenden (überschreibt launchViaSteam)
        if useEmulator {
            SteamEmulatorManager.shared.applyWarning = nil
            do {
                _ = try await SteamEmulatorManager.shared.applyEmulator(game: game)
            } catch {
                SteamEmulatorManager.shared.applyWarning = error.localizedDescription
            }
        }

        defer {
            if useEmulator {
                SteamEmulatorManager.shared.restoreBackup(game: game)
            }
        }

        // CrossOver-Spiele über CrossOver.app starten (nicht direkt wine binary)
        if game.runner == "CrossOver" {
            return try await launchCrossOverGame(game: game)
        }

        // D3DMetal-Render-Mode: bevorzugt Heroic GPTK wine64, falls verfügbar
        let wantsD3DMetal: Bool = {
            let mode = game.wineRenderMode
            let d3d = detectD3DMetal()
            print("[WineManager] wantsD3DMetal check: wineRenderMode=\(mode.rawValue) detectD3DMetal=\(d3d != nil ? "found" : "nil")")
            if mode == .d3dMetal { return true }
            if mode == .auto, d3d != nil { return true }
            return false
        }()

        var wine: WineVersion?
        if wantsD3DMetal {
            // Direkte Prüfung auf Heroic GPTK wine64
            let heroicPath = "\(NSHomeDirectory())/Library/Application Support/heroic/tools/game-porting-toolkit/Game-Porting-Toolkit-latest/Contents/Resources/wine/bin/wine64"
            if FileManager.default.isExecutableFile(atPath: heroicPath) {
                let heroicDir = URL(fileURLWithPath: heroicPath).deletingLastPathComponent().deletingLastPathComponent()
                wine = WineVersion(name: "HeroicGPTK", displayName: "Heroic (GPTK)", path: heroicDir.path, wineBinaryPath: heroicPath, wineServerPath: heroicDir.appendingPathComponent("bin/wineserver").path, type: .system)
                print("[WineManager] Using Heroic GPTK wine64 for D3DMetal")
            } else {
                wine = resolveWineVersion(for: game.wineVersionName)
            }
        } else {
            wine = resolveWineVersion(for: game.wineVersionName)
        }
        guard let wine, FileManager.default.isExecutableFile(atPath: wine.wineBinaryPath) else {
            throw WineError.noWineVersion
        }

        let prefix = prefixForGame(game)
        var env = ProcessInfo.processInfo.environment
        let gameEnv = wineEnvironment(for: game, prefix: prefix, wineVersion: wine)
        env.merge(gameEnv) { _, new in new }

        // CrossOver wine binary braucht CX_BOTTLE, auch wenn runner="Wine" ist
        if wine.type == .crossover, let p = prefix {
            let bottleName = URL(fileURLWithPath: p.path).lastPathComponent
            env["CX_BOTTLE"] = bottleName
        }

        if !game.wineLaunchArguments.isEmpty {
            for arg in game.wineLaunchArguments.components(separatedBy: .whitespaces).filter({ !$0.isEmpty }) {
                env["WINE_ARGUMENT_\(arg)"] = arg
            }
        }

        var installPath = game.installPath

        // Steam-App via -applaunch starten (überspringen wenn Emulator aktiv)
        if !useEmulator && game.launchViaSteam == true, let steamID = game.steamAppID, !steamID.isEmpty, let prefix {
            if let steamExe = findSteamExe(in: prefix.path) {
                installPath = steamExe
            }
        }

        if !FileManager.default.fileExists(atPath: installPath) {
            if let p = prefix, FileManager.default.fileExists(atPath: p.path) {
                let driveC = "\(p.path)/drive_c"
                if let found = findExeInDir(driveC) {
                    installPath = found
                }
            }
        }

        guard FileManager.default.fileExists(atPath: installPath) else {
            throw WineError.installPathNotFound(installPath)
        }

        let gameDir = URL(fileURLWithPath: installPath).deletingLastPathComponent()

        var cmd = "\"\(wine.wineBinaryPath)\""
        if !game.wineLaunchArguments.isEmpty {
            cmd += " " + game.wineLaunchArguments
        }
        if !useEmulator && game.launchViaSteam == true, let steamID = game.steamAppID, !steamID.isEmpty {
            cmd += " -applaunch \(steamID)"
        } else {
            cmd += " \"\(installPath)\""
        }

        let capture = game.runtimeSettings.processLogging
        let logFile = game.runtimeSettings.logFileRotation
        print("[WineManager] Launching: cmd=\(cmd)")
        print("[WineManager] gameDir=\(gameDir.path)")
        print("[WineManager] WINEPREFIX=\(env["WINEPREFIX"] ?? "nil")")
        print("[WineManager] WINEARCH=\(env["WINEARCH"] ?? "nil")")
        print("[WineManager] D3DMETAL_LIB=\(env["D3DMETAL_LIB"] ?? "nil")")
        print("[WineManager] DYLD_FRAMEWORK_PATH=\(env["DYLD_FRAMEWORK_PATH"] ?? "nil")")
        print("[WineManager] DYLD_LIBRARY_PATH=\(env["DYLD_LIBRARY_PATH"] ?? "nil")")
        print("[WineManager] WINEDLLOVERRIDES=\(env["WINEDLLOVERRIDES"] ?? "nil")")
        print("[WineManager] CX_BOTTLE=\(env["CX_BOTTLE"] ?? "nil")")
        let result = try await ProcessRunner.run(command: cmd, currentDirectory: gameDir, environment: env, captureOutput: capture)
        if logFile, !result.isEmpty {
            ProcessRunner.writeOutputToLogFile(gameID: game.id, gameName: game.name, output: result)
        }
        return result
    }

    private func launchCrossOverGame(game: Game) async throws -> String {
        let useEmulator = game.steamEmulatorEnabled == true &&
                          (game.steamAppID?.isEmpty == false) &&
                          !game.installPath.hasPrefix("steam://")
        var prefix = prefixForGame(game)
        let selectedVersion = installedVersions.first(where: { $0.type == .crossover && $0.name == game.wineVersionName })
        let crossover = selectedVersion ?? installedVersions.first(where: { $0.type == .crossover })
        guard let crossover, FileManager.default.isExecutableFile(atPath: crossover.wineBinaryPath) else {
            throw WineError.crossOverNotFound
        }

        // Wenn kein Prefix konfiguriert ist: automatisch aus installPath oder ersten verfügbaren Bottle ermitteln
        // Wenn kein Prefix konfiguriert ist: automatisch aus installPath oder ersten verfügbaren Bottle ermitteln
        if prefix == nil {
            let bottlesDir = "\(NSHomeDirectory())/Library/Application Support/CrossOver/Bottles"
            let knownPrefixes = prefixes.filter { $0.path.hasPrefix(bottlesDir) }
            if !knownPrefixes.isEmpty {
                if let matched = knownPrefixes.first(where: { game.installPath.hasPrefix("\($0.path)/drive_c") }) {
                    prefix = matched
                } else {
                    prefix = knownPrefixes.first
                }
            }
        }

        // CrossOver's wine binary ist ein Perl-Skript, das CX_BOTTLE für die Bottle-Auswahl verwendet
        // Der Bottle-Name ist der letzte Pfadbestandteil (Ordnername), nicht der ganze Pfad
        let crossoverBottleName = prefix.flatMap { URL(fileURLWithPath: $0.path).lastPathComponent }

        let gameEnv = wineEnvironment(for: game, prefix: prefix, wineVersion: crossover)
        var env = ProcessInfo.processInfo.environment
        env.merge(gameEnv) { _, new in new }
        if let crossoverBottleName {
            env["CX_BOTTLE"] = crossoverBottleName
        }

        // Steam-Spiel via CrossOver: steam.exe -applaunch {appid}
        if !useEmulator && game.launchViaSteam == true, let steamID = game.steamAppID, !steamID.isEmpty, let prefix {
            if let steamExe = findSteamExe(in: prefix.path) {
                let cmd = "\"\(crossover.wineBinaryPath)\" \"\(steamExe)\" -applaunch \(steamID)"
                let steamResult: String
                do {
                    steamResult = try await ProcessRunner.run(command: cmd, currentDirectory: nil, environment: env, captureOutput: game.runtimeSettings.processLogging)
                } catch let error as ProcessError {
                    steamResult = error.output
                }
                if game.runtimeSettings.logFileRotation, !steamResult.isEmpty {
                    ProcessRunner.writeOutputToLogFile(gameID: game.id, gameName: game.name, output: steamResult)
                }
                return steamResult
            }
        }

        // 1. CrossOver-Shortcut in ~/Applications/CrossOver/ oder ~/Programme/CrossOver/ suchen
        // Nur wenn kein expliziter Prefix gesetzt ist – sonst direkt via wine binary starten
        if prefix == nil {
            let crossoverShortcutsDirs = [
                "\(NSHomeDirectory())/Applications/CrossOver",
                "\(NSHomeDirectory())/Programme/CrossOver",
            ]
            for crossoverShortcutsDir in crossoverShortcutsDirs {
                guard FileManager.default.fileExists(atPath: crossoverShortcutsDir),
                      let apps = try? FileManager.default.contentsOfDirectory(atPath: crossoverShortcutsDir) else { continue }
                for app in apps where app.hasSuffix(".app") {
                    let appName = app.replacingOccurrences(of: ".app", with: "")
                    if appName.lowercased() == game.name.lowercased() {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "\(crossoverShortcutsDir)/\(app)"))
                        return "CrossOver-Shortcut: \(app)"
                    }
                }
            }
        }

        // 2. Fallback: .exe via wine binary + WINEPREFIX/CX_BOTTLE starten
        var installPath = game.installPath
        if !FileManager.default.fileExists(atPath: installPath) {
            if let p = prefix, FileManager.default.fileExists(atPath: p.path) {
                let driveC = "\(p.path)/drive_c"
                if let found = findExeInDir(driveC) {
                    installPath = found
                }
            }
        }

        guard FileManager.default.fileExists(atPath: installPath) else {
            throw WineError.installPathNotFound(installPath)
        }

        var cmd = "\"\(crossover.wineBinaryPath)\""
        if !useEmulator && game.launchViaSteam == true, let steamID = game.steamAppID, !steamID.isEmpty {
            cmd += " -applaunch \(steamID)"
        } else {
            cmd += " \"\(installPath)\""
        }

        let result: String
        do {
            result = try await ProcessRunner.run(command: cmd, currentDirectory: nil, environment: env, captureOutput: game.runtimeSettings.processLogging)
        } catch let error as ProcessError {
            result = error.output
        } catch {
            throw error
        }
        if game.runtimeSettings.logFileRotation, !result.isEmpty {
            ProcessRunner.writeOutputToLogFile(gameID: game.id, gameName: game.name, output: result)
        }
        return result
    }

    // MARK: - Alte runGame (für InstallerEngine etc.)

    func runGame(installPath: String, arguments: String = "", prefix: WinePrefix? = nil, wineVersion: WineVersion? = nil, environment: [String: String] = [:], captureOutput: Bool = true) async throws -> String {
        let wine = wineVersion ?? installedVersions.first ?? installedVersions.first(where: { $0.wineBinaryPath != "" })
        guard let wine, FileManager.default.isExecutableFile(atPath: wine.wineBinaryPath) else {
            throw WineError.noWineVersion
        }

        var env = ProcessInfo.processInfo.environment
        if let prefix {
            env["WINEPREFIX"] = prefix.path
            env["WINEARCH"] = prefix.architecture.rawValue
        }
        env.merge(environment) { _, new in new }

        var cmd = wine.wineBinaryPath
        if !arguments.isEmpty {
            cmd += " " + arguments
        }
        cmd += " " + installPath

        return try await ProcessRunner.run(command: cmd, currentDirectory: nil, environment: env, captureOutput: captureOutput)
    }

    // MARK: - Version für Game

    func resolveWineVersion(for wineVersionName: String?) -> WineVersion? {
        guard let name = wineVersionName, !name.isEmpty else {
            return installedVersions.first
        }
        return installedVersions.first(where: { $0.name == name }) ?? installedVersions.first
    }
}

enum WineError: LocalizedError {
    case noWineVersion
    case wineNotExecutable(String)
    case prefixCreationFailed
    case downloadFailed(String)
    case installPathNotFound(String)
    case crossOverNotFound
    case crossOverLaunchFailed(String)
    case gptkNotFound

    var errorDescription: String? {
        switch self {
        case .noWineVersion:
            return "Keine Wine-Version gefunden. Lade zuerst eine Wine-Version herunter."
        case .wineNotExecutable(let name):
            return "Wine-Binary ist nicht ausführbar: \(name)"
        case .prefixCreationFailed:
            return "Wineprefix konnte nicht erstellt werden."
        case .downloadFailed(let msg):
            return "Download fehlgeschlagen: \(msg)"
        case .installPathNotFound(let path):
            return "Installationspfad nicht gefunden: \(path)\n\nSetze den Pfad zur .exe-Datei im Spieleditor (z.B. /Users/.../CrossOver/Bottles/.../drive_c/.../game.exe)"
        case .crossOverNotFound:
            return "CrossOver.app nicht gefunden. Stelle sicher, dass CrossOver installiert ist."
        case .crossOverLaunchFailed(let detail):
            return "Fehler beim Starten über CrossOver.app: \(detail)"
        case .gptkNotFound:
            return "GPTK/D3DMetal nicht gefunden – DLSS (MetalFX) benötigt eine CrossOver- oder GPTK-Installation."
        }
    }
}
