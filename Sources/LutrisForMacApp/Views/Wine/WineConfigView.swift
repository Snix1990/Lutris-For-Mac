import SwiftUI

struct WineConfigView: View {
    @Binding var game: Game
    private let wineManager = WineManager.shared
    @State private var showWinetricks = false
    @State private var winetricksPrefix: WinePrefix?
    @State private var winetricksWineBinaryPath: String? = nil
    @State private var showCrossOverTricks = false
    @State private var crossOverTricksPrefix: WinePrefix?
    @State private var d3dMetalAvailable = false

    @State private var editWineBinaryPath: String = ""
    @State private var editWinePrefixPath: String = ""
    @State private var editDesktopResolution: String = ""
    @FocusState private var isWineBinaryFocused: Bool
    @FocusState private var isWinePrefixFocused: Bool
    @FocusState private var isDesktopResFocused: Bool

    private var selectedPrefix: WinePrefix? {
        if let id = game.winePrefixID {
            return wineManager.prefixes.first(where: { $0.id == id })
        }
        if let name = game.winePrefixName {
            return wineManager.prefixes.first(where: { $0.name == name })
        }
        return nil
    }

    private var prefixBinding: Binding<UUID?> {
        Binding(
            get: {
                if let id = game.winePrefixID { return id }
                if let name = game.winePrefixName {
                    return wineManager.prefixes.first(where: { $0.name == name })?.id
                }
                return nil
            },
            set: { newID in
                game.winePrefixID = newID
                if let id = newID, let prefix = wineManager.prefixes.first(where: { $0.id == id }) {
                    game.winePrefixName = prefix.name
                } else if newID == nil {
                    game.winePrefixName = nil
                }
            }
        )
    }

    private var isWineRunner: Bool {
        let wineRunners = ["Wine", "CrossOver", "Whisky", "Kegworks", "Crossover Wine", "WineSikarugir"]
        return wineRunners.contains(game.runner) || game.runner == "Custom"
    }

    private var isCrossOver24OrNewer: Bool {
        guard game.runner == "CrossOver",
              let versionName = game.wineVersionName,
              let version = wineManager.installedVersions.first(where: { $0.name == versionName }),
              version.type == .crossover else { return false }
        let displayName = version.displayName
        if let versionStr = displayName.split(separator: " ").last(where: { $0.hasPrefix("2") || $0.hasPrefix("3") }),
           let major = Int(versionStr.split(separator: ".").first ?? "") {
            return major >= 24
        }
        if let co = wineManager.crossOverInstallations.first(where: { $0.wineBinaryPath == version.wineBinaryPath }),
           let major = Int(co.version.split(separator: ".").first ?? "") {
            return major >= 24
        }
        return false
    }

    var body: some View {
        Group {
            if isWineRunner {
                wineConfigContent
            }
        }
        .sheet(isPresented: $showWinetricks) {
            if let p = winetricksPrefix {
                WinetricksView(wineManager: wineManager, initialPrefix: p, wineBinaryPath: winetricksWineBinaryPath)
            }
        }
        .sheet(isPresented: $showCrossOverTricks) {
            if let p = crossOverTricksPrefix {
                CrossOverTricksView(wineManager: wineManager, initialPrefix: p)
            }
        }
    }

    private func openWinetricksWithPath(_ path: String) {
        winetricksPrefix = wineManager.prefixes.first(where: { $0.path == path })
            ?? WinePrefix(name: URL(fileURLWithPath: path).lastPathComponent, path: path)
        winetricksWineBinaryPath = editWineBinaryPath.isEmpty ? nil : editWineBinaryPath
        showWinetricks = true
    }

    private func openCrossOverTricks(for prefix: WinePrefix) {
        crossOverTricksPrefix = prefix
        showCrossOverTricks = true
    }

    private var wineConfigContent: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if game.runner == "CrossOver" {
                    crossoverContent
                } else {
                    genericWineContent
                }
            }
        } label: {
            LText("Wine-Konfiguration").font(.system(size: 16)).frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var genericWineContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            LText("Wine-Pfad (Binär)").font(.caption).foregroundColor(.secondary)
            TextField("/usr/local/bin/wine64", text: $editWineBinaryPath)
                .focused($isWineBinaryFocused)
                .onSubmit { commitWineBinaryPath() }
                .textFieldStyle(.roundedBorder)
                .font(.callout)

            LText("Wineprefix-Pfad").font(.caption).foregroundColor(.secondary)
            TextField("/pfad/zum/prefix", text: $editWinePrefixPath)
                .focused($isWinePrefixFocused)
                .onSubmit { commitWinePrefixPath() }
                .textFieldStyle(.roundedBorder)
                .font(.callout)

            if let prefixPath = game.winePrefixPath, !prefixPath.isEmpty {
                HStack(spacing: 8) {
                    Button("winecfg") {
                        if !editWineBinaryPath.isEmpty {
                            wineManager.runWinecfg(wineBinaryPath: editWineBinaryPath, prefixPath: prefixPath)
                        } else if let wv = wineManager.resolveWineVersion(for: game.wineVersionName) {
                            wineManager.runWinecfg(prefixPath: prefixPath, wineVersion: wv)
                        } else {
                            wineManager.runWinecfg(prefixPath: prefixPath)
                        }
                    }
                    .buttonStyle(.bordered)
                    Button("regedit") {
                        if !editWineBinaryPath.isEmpty {
                            wineManager.runRegedit(wineBinaryPath: editWineBinaryPath, prefixPath: prefixPath)
                        } else if let wv = wineManager.resolveWineVersion(for: game.wineVersionName) {
                            wineManager.runRegedit(prefixPath: prefixPath, wineVersion: wv)
                        } else {
                            wineManager.runRegedit(prefixPath: prefixPath)
                        }
                    }
                    .buttonStyle(.bordered)
                    if game.runner != "CrossOver" {
                        Button { openWinetricksWithPath(prefixPath) } label: { LText("Winetricks") }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .onAppear {
            editWineBinaryPath = game.wineBinaryPath ?? ""
            editWinePrefixPath = game.winePrefixPath ?? ""
            editDesktopResolution = game.wineDesktopResolution
            d3dMetalAvailable = wineManager.detectD3DMetal() != nil
        }
        .onDisappear {
            commitWineBinaryPath()
            commitWinePrefixPath()
        }
        .onChange(of: isWineBinaryFocused) { _, focused in
            if !focused { commitWineBinaryPath() }
        }
        .onChange(of: isWinePrefixFocused) { _, focused in
            if !focused { commitWinePrefixPath() }
        }
        .onChange(of: isDesktopResFocused) { _, focused in
            if !focused { commitDesktopResolution() }
        }

        Picker(selection: $game.wineArchitecture) {
            LText("64-Bit (win64)").tag(nil as String?)
            LText("32-Bit (win32)").tag("win32" as String?)
            LText("64-Bit (win64)").tag("win64" as String?)
        } label: {
            LText("Architektur")
        }

        // Render-Modus
        Picker(selection: $game.wineRenderMode) {
            ForEach(WineRenderMode.allCases, id: \.self) { mode in
                VStack(alignment: .leading) {
                    Text(mode.displayName)
                    Text(mode.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .tag(mode)
            }
        } label: {
            LText("Render-Modus")
        }
        .pickerStyle(.radioGroup)
        .helpLText("Übersetzungsweg für DirectX → Metal")

        // D3DMetal-Verfügbarkeit anzeigen
        if d3dMetalAvailable {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .imageScale(.small)
                LText("D3DMetal (GPTK) verfügbar")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else {
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.orange)
                    .imageScale(.small)
                LText("D3DMetal nicht gefunden – installiere CrossOver oder GPTK")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }

        // Performance-Optionen
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if isCrossOver24OrNewer {
                    Toggle(isOn: Binding(
                        get: { game.wineMSync ?? false },
                        set: { game.wineMSync = $0 }
                    )) { LText("MSync (MSync-Synchronisation, ab CrossOver 24)") }
                    .helpLText("WINE_MSYNC_DISABLE=0 – Ersetzt ESync/FSync auf macOS. Standard in CrossOver 24+. Deutlich stabiler als ESync/FSync.")

                    if game.wineMSync ?? false {
                        LText("ESync und FSync werden ignoriert, da MSync aktiv ist.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Toggle(isOn: $game.wineESync) { LText("ESync (ereignisbasierte Synchronisation)") }
                        .helpLText("WINEESYNC=1 – Reduziert CPU-Overhead bei Thread-Sync. Empfohlen für moderne Spiele.")

                    Toggle(isOn: $game.wineFSync) { LText("FSync (futex-basierte Synchronisation)") }
                        .helpLText("WINEFSYNC=1 – Noch effizienter als ESync, erfordert kompatiblen Wine-Kernel.")
                }

                Toggle(isOn: $game.wineShaderCache) { LText("Shader-Cache aktivieren") }
                    .helpLText("D3DMETAL_SHADER_CACHE=1 – Reduziert Stottern durch gecachte Shader.")
            }
            .padding(.vertical, 4)
        } label: {
            LText("Leistungsoptionen").font(.system(size: 16)).frame(maxWidth: .infinity)
        }

        Picker(selection: $game.wineAudioDriver) {
            LText("CoreAudio").tag("coreaudio")
            LText("PulseAudio").tag("pulse")
            LText("ALSA").tag("alsa")
            LText("Keiner (disabled)").tag("disabled")
        } label: {
            LText("Audio-Treiber")
        }
        .helpLText("Audio-Backend für Wine")

        Toggle(isOn: $game.wineDesktopMode) { LText("Virtuellen Desktop verwenden") }

        if game.wineDesktopMode {
            TextField(tr("Desktop-Auflösung"), text: $editDesktopResolution)
                .focused($isDesktopResFocused)
                .helpLText("z.B. 1280x720, 1920x1080")
        }

        if wineManager.installedVersions.isEmpty {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                LText("Keine Wine-Version gefunden. Lade eine unter Wine-Einstellungen herunter.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func commitWineBinaryPath() {
        game.wineBinaryPath = editWineBinaryPath.isEmpty ? nil : editWineBinaryPath
    }

    private func commitWinePrefixPath() {
        game.winePrefixPath = editWinePrefixPath.isEmpty ? nil : editWinePrefixPath
    }

    private func commitDesktopResolution() {
        guard editDesktopResolution != game.wineDesktopResolution else { return }
        game.wineDesktopResolution = editDesktopResolution
    }

    @ViewBuilder
    private var crossoverContent: some View {
        crossoverPicker

        VStack(alignment: .leading, spacing: 6) {
            Picker(selection: prefixBinding) {
                LText("Standard (kein Prefix)").tag(nil as UUID?)
                ForEach(wineManager.prefixes) { p in
                    Text(p.name).tag(p.id as UUID?)
                }
            } label: {
                LText("Wineprefix (Bottle)")
            }

            if let prefix = selectedPrefix {
                VStack(alignment: .leading, spacing: 2) {
                    Text(prefix.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(prefix.architecture.rawValue), \(prefix.windowsVersion)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 8) {
                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.prompt = tr("Bottle auswählen")
                    panel.message = tr("Wähle einen CrossOver Bottle-Ordner aus (~/Library/Application Support/CrossOver/Bottles/)")
                    if panel.runModal() == .OK, let url = panel.url {
                        let path = url.path
                        let crossoverVersions = wineManager.installedVersions.filter { $0.type == .crossover }
                        let selectedVersion = crossoverVersions.first(where: { $0.name == game.wineVersionName })
                        let selectedCO = selectedVersion.flatMap { v in
                            wineManager.crossOverInstallations.first(where: { $0.wineBinaryPath == v.wineBinaryPath })
                        }
                        let bottleLabel = selectedCO?.name ?? selectedVersion?.name ?? "CrossOver"
                        let name = "\(bottleLabel): \(url.lastPathComponent)"
                        if !wineManager.prefixes.contains(where: { $0.path == path }) {
                            let isWin64 = FileManager.default.fileExists(atPath: "\(path)/drive_c/Program Files (x86)")
                            let arch: WinePrefix.WineArch = isWin64 ? .win64 : .win32
                            let prefix = WinePrefix(name: name, path: path, architecture: arch)
                            wineManager.prefixes.append(prefix)
                            wineManager.savePrefixes()
                            game.winePrefixID = prefix.id
                            game.winePrefixName = prefix.name
                        } else if let existing = wineManager.prefixes.first(where: { $0.path == path }) {
                            game.winePrefixID = existing.id
                            game.winePrefixName = existing.name
                        }
                    }
                } label: { LText("Bottle durchsuchen…") }
                .font(.caption)

                if let prefix = selectedPrefix {
                    Button(role: .destructive) {
                        wineManager.prefixes.removeAll { $0.id == prefix.id }
                        wineManager.savePrefixes()
                        game.winePrefixID = nil
                        game.winePrefixName = nil
                    } label: { LText("Bottle entfernen") }
                    .font(.caption)
                }
            }
        }

        if let prefix = selectedPrefix {
            HStack(spacing: 8) {
                Button("winecfg") {
                    if let wv = wineManager.resolveWineVersion(for: game.wineVersionName) {
                        wineManager.runWinecfg(for: prefix, wineVersion: wv)
                    } else {
                        wineManager.runWinecfg(for: prefix)
                    }
                }
                .buttonStyle(.bordered)
                Button("regedit") {
                    if let wv = wineManager.resolveWineVersion(for: game.wineVersionName) {
                        wineManager.runRegedit(for: prefix, wineVersion: wv)
                    } else {
                        wineManager.runRegedit(for: prefix)
                    }
                }
                .buttonStyle(.bordered)
                if game.runner != "CrossOver" {
                    Button { openCrossOverTricks(for: prefix) } label: { LText("Crossovertricks") }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var crossoverPicker: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                let crossoverVersions = wineManager.installedVersions.filter { $0.type == .crossover }

                if crossoverVersions.isEmpty {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        LText("Keine CrossOver-Installation gefunden. Stelle sicher, dass CrossOver.app im Programme-Ordner ist.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Picker(selection: $game.wineVersionName) {
                        LText("Standard").tag(nil as String?)
                        ForEach(crossoverVersions) { v in
                            HStack {
                                Text(v.displayName)
                                if isCXPatchVersion(v) {
                                    badgeCXPatch
                                }
                            }
                            .tag(v.name as String?)
                        }
                    } label: {
                        LText("Auswahl")
                    }

                    if let selectedName = game.wineVersionName,
                       let selected = crossoverVersions.first(where: { $0.name == selectedName }) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .imageScale(.small)
                            Text("\(selected.displayName) – \(selected.path)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        if isCXPatchVersion(selected) {
                            HStack(spacing: 4) {
                                Image(systemName: "ant.fill")
                                    .foregroundColor(.purple)
                                    .imageScale(.small)
                                LText("CXPatch erkannt – erweiterte Kompatibilität aktiv")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Divider()

                Button { addCrossOverInstallation() } label: { LText("CrossOver-Installation hinzufügen…") }
                .buttonStyle(.plain)
                .font(.caption)
            }
            .padding(.vertical, 4)
        } label: {
            LText("CrossOver-Installation").font(.system(size: 16)).frame(maxWidth: .infinity)
        }
    }

    private var badgeCXPatch: some View {
        LText("CXPatch")
            .font(.caption2)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.purple.opacity(0.15))
            .foregroundColor(.purple)
            .cornerRadius(4)
    }

    private func isCXPatchVersion(_ version: WineVersion) -> Bool {
        version.displayName.lowercased().contains("cxpatch") ||
        wineManager.crossOverInstallations.contains(where: {
            $0.wineBinaryPath == version.wineBinaryPath && $0.isCXPatch
        })
    }

    private func addCrossOverInstallation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.prompt = tr("Auswählen")
        panel.message = tr("Wähle CrossOver.app aus dem Programme-Ordner")
        if panel.runModal() == .OK, let url = panel.url {
            wineManager.addCrossOverInstallation(path: url.path)
        }
    }
}
