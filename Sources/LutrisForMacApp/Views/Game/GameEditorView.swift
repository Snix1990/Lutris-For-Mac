import SwiftUI
import AppKit

struct PendingGameChanges {
    var name: String
    var installPath: String
    var launcherCommand: String
    var steamAppID: String?
    var coverURL: String
    var bannerURL: String
    var iconURL: String
    var category: String
}

struct GameEditorView: View {
    @Binding var game: Game
    let onCommitPending: ((UUID, PendingGameChanges) -> Void)?
    @State private var showCoverSearch = false
    @State private var coverImage: NSImage?
    @State private var editName: String = ""
    @State private var editInstallPath: String = ""
    @State private var editLauncherCommand: String = ""
    @State private var editSteamAppID: String = ""
    @State private var editCoverURL: String = ""
    @State private var editBannerURL: String = ""
    @State private var editIconURL: String = ""
    @State private var editCategory: String = ""
    @State private var editNotes: String = ""
    @State private var editDescription: String = ""
    @State private var editEnvVars: String = ""
    @FocusState private var isNameFocused: Bool
    @FocusState private var isInstallPathFocused: Bool
    @FocusState private var isLauncherCommandFocused: Bool
    @FocusState private var isSteamAppIDFocused: Bool
    @FocusState private var isCoverURLFocused: Bool
    @FocusState private var isBannerURLFocused: Bool
    @FocusState private var isIconURLFocused: Bool
    @FocusState private var isCategoryFocused: Bool
    @FocusState private var isNotesFocused: Bool
    @FocusState private var isDescriptionFocused: Bool
    @State private var isFetchingDescription: Bool = false
    @FocusState private var isEnvVarsFocused: Bool
    private let runnerManager = RunnerManager.shared
    private let mediaStore = MediaStore.shared
    private let serviceManager = ServiceManager.shared

    var body: some View {
        VStack(spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent(tr("Name")) {
                        TextField("", text: $editName)
                            .focused($isNameFocused)
                            .onSubmit { commitName() }
                    }
                    LabeledContent(tr("Plattform")) {
                        Picker("", selection: $game.platform) {
                            ForEach(availablePlatforms, id: \.self) { platform in
                                Text(platform)
                            }
                        }
                        .labelsHidden()
                    }
                    LabeledContent(tr("Installationspfad")) {
                        HStack(spacing: 6) {
                            TextField("", text: $editInstallPath)
                                .focused($isInstallPathFocused)
                                .onSubmit { commitInstallPath() }
                            Button { chooseInstallPath() } label: { LText("Wählen") }
                            .controlSize(.small)
                        }
                    }
                    LabeledContent(tr("Runner")) {
                        Picker("", selection: $game.runner) {
                            ForEach(runnerManager.runners) { runner in
                                HStack {
                                    Image(systemName: runner.category.systemImage)
                                    Text(runner.displayName)
                                }
                                .tag(runner.name)
                            }
                            Divider()
                            LText("Benutzerdefiniert").tag("Custom")
                        }
                        .labelsHidden()
                    }

                    if game.runner == "Custom" {
                        LabeledContent(tr("Launcher-Befehl")) {
                            TextField("", text: $editLauncherCommand)
                                .focused($isLauncherCommandFocused)
                                .onSubmit { commitLauncherCommand() }
                        }
                    } else if let runner = runnerManager.runners.first(where: { $0.name == game.runner }) {
                        if !runner.installed {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(verbatim: trf("%@ ist nicht installiert", runner.displayName))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Text(runner.launchTemplate.displayDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 100)
                    }

                    Divider()

                    LabeledContent(tr("Drittanbieter")) {
                        Picker("", selection: $game.serviceName) {
                            Text(verbatim: tr("Kein")).tag(nil as String?)
                            ForEach(serviceManager.services) { service in
                                HStack {
                                    Image(systemName: service.iconSystemName)
                                    Text(service.displayName)
                                }
                                .tag(service.name as String?)
                            }
                        }
                        .labelsHidden()
                    }

                    if game.serviceName == "Steam" {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: Binding(
                                get: { game.launchViaSteam ?? false },
                                set: { game.launchViaSteam = $0 }
                            )) { LText("Über Steam starten") }

                            LabeledContent(tr("Steam AppID")) {
                                TextField("", text: $editSteamAppID)
                                    .focused($isSteamAppIDFocused)
                                    .onSubmit { commitSteamAppID() }
                            }

                            Toggle(isOn: Binding(
                                get: { game.steamEmulatorEnabled ?? false },
                                set: { game.steamEmulatorEnabled = $0 }
                            )) { LText("Steam Emulator (Steamless + Goldberg)") }
                            .helpLText("Entfernt Steam-DRM via Steamless und emuliert Steamworks-API. Setzt das Spiel nach dem Schließen wieder zurück.")
                            .disabled(game.steamAppID?.isEmpty ?? true)

                            if game.installPath.hasPrefix("steam://") {
                                LText("Wird ignoriert – Spiel wird via Steam gestartet")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if game.steamEmulatorEnabled == true {
                                SteamEmulatorToolsSection()
                            }
                        }
                        .padding(.leading, 100)
                    }
                }
            } label: {
                LText("Spiel-Information").font(.system(size: 16)).frame(maxWidth: .infinity)
            }

            // Runner-spezifische Konfiguration
            if let runner = runnerManager.runners.first(where: { $0.name == game.runner }),
               !runner.configFields.isEmpty {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $editDescription)
                        .focused($isDescriptionFocused)
                        .frame(minHeight: 120)
                    HStack {
                        if isFetchingDescription {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Suche Beschreibung…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            Task {
                                isFetchingDescription = true
                                let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
                                let desc = await GameDescriptionService.fetchDescription(
                                    gameName: editName,
                                    steamAppID: editSteamAppID.isEmpty ? nil : editSteamAppID,
                                    language: lang
                                )
                                if let desc = desc {
                                    editDescription = desc
                                }
                                isFetchingDescription = false
                            }
                        } label: {
                            LText("Beschreibung abrufen")
                        }
                        .disabled(isFetchingDescription || editName.isEmpty)
                        .controlSize(.small)
                    }
                }
            } label: {
                LText("Beschreibung").font(.system(size: 16)).frame(maxWidth: .infinity)
            }

            GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(runner.configFields) { field in
                            configFieldView(field, runner: runner)
                        }
                    }
                } label: {
                    Text(verbatim: trf("%@ – Einstellungen", runner.displayName)).font(.system(size: 16)).frame(maxWidth: .infinity)
                }
            }

            // Wine-Konfiguration (für Wine-basierte Runner)
            WineConfigView(game: $game)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent(tr("Cover-URL")) {
                        HStack(spacing: 6) {
                            TextField("", text: $editCoverURL)
                                .focused($isCoverURLFocused)
                                .onSubmit { commitCoverURL() }
                                .font(.caption)
                            Button {
                                Task {
                                    mediaStore.removeMedia(for: game.id.uuidString, type: .cover)
                                    coverImage = await mediaStore.loadImage(from: game.coverURL, gameID: game.id.uuidString, type: .cover)
                                }
                            } label: { LText("Laden") }
                            .disabled(game.coverURL.isEmpty)
                            .controlSize(.small)
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = true
                            panel.canChooseDirectories = false
                            panel.allowedContentTypes = [.image]
                            if panel.runModal() == .OK, let url = panel.url {
                                coverImage = mediaStore.setLocalImage(at: url, gameID: game.id.uuidString, type: .cover)
                                game.coverURL = ""
                            }
                        } label: { LText("Lokale Datei...") }
                        .controlSize(.small)

                        Button { showCoverSearch = true } label: { LText("Online suchen...") }
                        .controlSize(.small)

                        if !game.coverURL.isEmpty || coverImage != nil {
                            Button { 
                                editCoverURL = ""
                                mediaStore.removeMedia(for: game.id.uuidString, type: .cover)
                                coverImage = nil
                                game.coverURL = ""
                            } label: { LText("Entfernen") }
                            .controlSize(.small)
                            .foregroundColor(.red)
                        }
                    }

                    Divider()

                    LabeledContent(tr("Banner-URL")) {
                        HStack(spacing: 6) {
                            TextField("", text: $editBannerURL)
                                .focused($isBannerURLFocused)
                                .onSubmit { commitBannerURL() }
                                .font(.caption)
                            Button {
                                commitBannerURL()
                                Task {
                                    mediaStore.removeMedia(for: game.id.uuidString, type: .banner)
                                    _ = await mediaStore.loadImage(from: game.bannerURL, gameID: game.id.uuidString, type: .banner)
                                }
                            } label: { LText("Laden") }
                            .disabled(editBannerURL.isEmpty)
                            .controlSize(.small)
                        }
                    }

                    LabeledContent(tr("Icon-URL")) {
                        HStack(spacing: 6) {
                            TextField("", text: $editIconURL)
                                .focused($isIconURLFocused)
                                .onSubmit { commitIconURL() }
                                .font(.caption)
                            Button {
                                commitIconURL()
                                Task {
                                    mediaStore.removeMedia(for: game.id.uuidString, type: .icon)
                                    _ = await mediaStore.loadImage(from: game.iconURL, gameID: game.id.uuidString, type: .icon)
                                }
                            } label: { LText("Laden") }
                            .disabled(editIconURL.isEmpty)
                            .controlSize(.small)
                        }
                    }
                }
            } label: {
                LText("Medien").font(.system(size: 16)).frame(maxWidth: .infinity)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent(tr("Kategorie")) {
                        TextField("", text: $editCategory)
                            .focused($isCategoryFocused)
                            .onSubmit { commitCategory() }
                    }
                    .helpLText("z.B. Abenteuer, Indie, Strategie")

                    Toggle(isOn: $game.isFavorite) {
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                            LText("Favorit")
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        LText("Bewertung")
                            .font(.subheadline)
                        HStack(spacing: 4) {
                            ForEach(1...5, id: \.self) { i in
                                Button {
                                    game.rating = i
                                } label: {
                                    Image(systemName: i <= game.rating ? "star.fill" : "star")
                                        .foregroundColor(.yellow)
                                }
                                .buttonStyle(.plain)
                            }
                            if game.rating > 0 {
                                Button { game.rating = 0 } label: { LText("Zurücksetzen") }
                                    .buttonStyle(.plain)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if game.playTime > 0 {
                        HStack {
                                LText("Spielzeit")
                                .font(.subheadline)
                            Spacer()
                            Text(game.playTimeFormatted)
                                .foregroundColor(.secondary)
                        }
                        if let lastPlayed = game.lastPlayed {
                            HStack {
                                LText("Zuletzt gespielt")
                                    .font(.subheadline)
                                Spacer()
                                Text(lastPlayed, style: .date)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            } label: {
                LText("Organisation").font(.system(size: 16)).frame(maxWidth: .infinity)
            }

            GroupBox {
                TextEditor(text: $editNotes)
                    .focused($isNotesFocused)
                    .frame(minHeight: 100)
            } label: {
                LText("Notizen").font(.system(size: 16)).frame(maxWidth: .infinity)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    if game.screenshotPaths.isEmpty {
                        LText("Noch keine Screenshots").font(.caption).foregroundColor(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(game.screenshotPaths.indices, id: \.self) { i in
                                    let path = game.screenshotPaths[i]
                                    if let img = NSImage(contentsOfFile: path) {
                                        ZStack(alignment: .topTrailing) {
                                            Image(nsImage: img)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 120, height: 80)
                                                .clipped()
                                                .cornerRadius(6)
                                            Button {
                                                game.screenshotPaths.remove(at: i)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.red)
                                                    .background(Circle().fill(.white))
                                            }
                                            .buttonStyle(.plain)
                                            .offset(x: 6, y: -6)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(height: 90)
                    }
                    Button {
                        let panel = NSOpenPanel()
                        panel.allowsMultipleSelection = true
                        panel.canChooseFiles = true
                        panel.allowedContentTypes = [.image]
                        if panel.runModal() == .OK {
                            for url in panel.urls {
                                guard let dest = copyScreenshotToStore(url: url) else { continue }
                                if !game.screenshotPaths.contains(dest) {
                                    game.screenshotPaths.append(dest)
                                }
                            }
                        }
                    } label: {
                        Label(tr("Screenshots"), systemImage: "plus.circle")
                            .font(.subheadline)
                    }
                    .buttonStyle(.borderless)
                }
            } label: {
                LText("Screenshots").font(.system(size: 16)).frame(maxWidth: .infinity)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    LText("Eine pro Zeile (SCHLÜSSEL=WERT):")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    TextEditor(text: $editEnvVars)
                        .focused($isEnvVarsFocused)
                        .frame(minHeight: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.25))
                        )
                }
            } label: {
                LText("Umgebungsvariablen").font(.system(size: 16)).frame(maxWidth: .infinity)
            }

            runtimeSection
        }
        .padding(.top, 6)
        .onAppear {
            coverImage = mediaStore.cachedImage(for: game.id.uuidString, type: .cover)
            if coverImage == nil, !game.coverURL.isEmpty {
                Task { coverImage = await mediaStore.loadImage(from: game.coverURL, gameID: game.id.uuidString, type: .cover) }
            }
        }
        .sheet(isPresented: $showCoverSearch) {
            CoverSearchView(
                gameName: game.name,
                gameID: game.id.uuidString,
                onSelect: { url in
                    game.coverURL = url
                }
            )
        }
        .onChange(of: game.coverURL) { _, newURL in
            editCoverURL = newURL
        }
        .onAppear {
            editName = game.name
            editInstallPath = game.installPath
            editLauncherCommand = game.launcherCommand
            editSteamAppID = game.steamAppID ?? ""
            editCoverURL = game.coverURL
            editBannerURL = game.bannerURL
            editIconURL = game.iconURL
            editCategory = game.category
            editNotes = game.notes
            editDescription = game.gameDescription
            editEnvVars = game.environmentVariables
        }
        .onChange(of: game.id) { oldID, newID in
            guard oldID != newID else { return }
            let pending = PendingGameChanges(
                name: editName,
                installPath: editInstallPath,
                launcherCommand: editLauncherCommand,
                steamAppID: editSteamAppID.isEmpty ? nil : editSteamAppID,
                coverURL: editCoverURL,
                bannerURL: editBannerURL,
                iconURL: editIconURL,
                category: editCategory
            )
            onCommitPending?(oldID, pending)
            editName = game.name
            editInstallPath = game.installPath
            editLauncherCommand = game.launcherCommand
            editSteamAppID = game.steamAppID ?? ""
            editCoverURL = game.coverURL
            editBannerURL = game.bannerURL
            editIconURL = game.iconURL
            editCategory = game.category
            editNotes = game.notes
            editDescription = game.gameDescription
            editEnvVars = game.environmentVariables
        }
        .onChange(of: isNameFocused) { _, focused in
            if !focused { commitName() }
        }
        .onChange(of: isInstallPathFocused) { _, focused in
            if !focused { commitInstallPath() }
        }
        .onChange(of: isLauncherCommandFocused) { _, focused in
            if !focused { commitLauncherCommand() }
        }
        .onChange(of: isSteamAppIDFocused) { _, focused in
            if !focused { commitSteamAppID() }
        }
        .onChange(of: isCoverURLFocused) { _, focused in
            if !focused { commitCoverURL() }
        }
        .onChange(of: isBannerURLFocused) { _, focused in
            if !focused { commitBannerURL() }
        }
        .onChange(of: isIconURLFocused) { _, focused in
            if !focused { commitIconURL() }
        }
        .onChange(of: isCategoryFocused) { _, focused in
            if !focused { commitCategory() }
        }
        .onChange(of: isNotesFocused) { _, focused in
            if !focused { commitNotes() }
        }
        .onChange(of: isDescriptionFocused) { _, focused in
            if !focused { commitDescription() }
        }
        .onChange(of: isEnvVarsFocused) { _, focused in
            if !focused { commitEnvVars() }
        }
    }

    private let availablePlatforms = [
        "macOS", "Windows", "DOS", "GameCube", "Wii", "Nintendo DS",
        "3DS", "Switch", "PS1", "PS2", "PS3", "PSP", "Dreamcast",
        "Arcade", "Multi", "Linux", tr("Andere")
    ]

    @ViewBuilder
    private func configFieldView(_ field: Runner.RunnerConfigField, runner: Runner) -> some View {
        let binding = Binding<String>(
            get: { game.runnerConfig[field.id] ?? field.defaultValue },
            set: { game.runnerConfig[field.id] = $0 }
        )

        switch field.type {
        case .text:
            VStack(alignment: .leading, spacing: 4) {
                Text(field.label)
                    .font(.subheadline)
                TextField(field.help, text: binding)
                    .textFieldStyle(.roundedBorder)
                if !field.help.isEmpty {
                    Text(field.help)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

        case .toggle:
            Toggle(field.label, isOn: Binding(
                get: { binding.wrappedValue == "true" },
                set: { binding.wrappedValue = $0 ? "true" : "false" }
            ))

        case .filePicker:
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(field.label)
                        .font(.subheadline)
                    TextField(field.help, text: binding)
                        .textFieldStyle(.roundedBorder)
                }
                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        binding.wrappedValue = url.path
                    }
                } label: { LText("Wählen") }
            }

        case .picker:
            Picker(field.label, selection: binding) {
                LText("Standard").tag("")
                LText("Wert 1").tag("value1")
                LText("Wert 2").tag("value2")
            }
        }
    }

    private func commitName() {
        guard editName != game.name else { return }
        game.name = editName
    }

    private func commitInstallPath() {
        guard editInstallPath != game.installPath else { return }
        game.installPath = editInstallPath
    }

    private func commitLauncherCommand() {
        guard editLauncherCommand != game.launcherCommand else { return }
        game.launcherCommand = editLauncherCommand
    }

    private func commitSteamAppID() {
        let newValue = editSteamAppID.isEmpty ? nil : editSteamAppID
        guard newValue != game.steamAppID else { return }
        game.steamAppID = newValue
    }

    private func commitCoverURL() {
        guard editCoverURL != game.coverURL else { return }
        game.coverURL = editCoverURL
    }

    private func commitBannerURL() {
        guard editBannerURL != game.bannerURL else { return }
        game.bannerURL = editBannerURL
    }

    private func commitIconURL() {
        guard editIconURL != game.iconURL else { return }
        game.iconURL = editIconURL
    }

    private func commitCategory() {
        guard editCategory != game.category else { return }
        game.category = editCategory
    }

    private func commitNotes() {
        guard editNotes != game.notes else { return }
        game.notes = editNotes
    }

    private func commitDescription() {
        guard editDescription != game.gameDescription else { return }
        game.gameDescription = editDescription
    }

    private func commitEnvVars() {
        guard editEnvVars != game.environmentVariables else { return }
        game.environmentVariables = editEnvVars
    }

    private func chooseInstallPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Auswählen"

        if panel.runModal() == .OK, let url = panel.url {
            editInstallPath = url.path
            commitInstallPath()
        }
    }

    private func copyScreenshotToStore(url: URL) -> String? {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let screenshotsDir = appSupport.appendingPathComponent("LutrisForMac/screenshots/\(game.id.uuidString)")
        try? fm.createDirectory(at: screenshotsDir, withIntermediateDirectories: true)
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
        let dest = screenshotsDir.appendingPathComponent("\(UUID().uuidString).\(ext)")
        guard (try? fm.copyItem(at: url, to: dest)) != nil else { return nil }
        return dest.path
    }

    // MARK: - Runtime Options

    @ViewBuilder
    private var runtimeSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                // Gruppe 1: Fertig gebaut
                LText("Allgemein").font(.caption).foregroundColor(.secondary).padding(.top, 2)
                Toggle(isOn: $game.runtimeSettings.discordRPC) { LText("Discord-RPC (Spielpräsenz)") }
                Toggle(isOn: $game.runtimeSettings.cloudSync) { LText("Cloud-Sync (Speicherstände)") }
                if game.runtimeSettings.cloudSync {
                    HStack(spacing: 6) {
                        TextField(tr("Speicherpfad"), text: $game.customSavePath)
                            .font(.caption)
                            .helpLText("Absoluter Pfad zum Save-Ordner (z.B. ~/Library/Application Support/MeinSpiel/Saves)")
                        Button {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.prompt = tr("Auswählen")
                            if panel.runModal() == .OK, let url = panel.url {
                                game.customSavePath = url.path
                            }
                        } label: { LText("Wählen") }
                        .controlSize(.small)
                    }
                }
                Toggle(isOn: $game.runtimeSettings.webhook) { LText("Webhook bei Spiel-Ende") }
                    .helpLText("POST-JSON an konfigurierte Webhook-URL (siehe API-Einstellungen)")
                Toggle(isOn: $game.runtimeSettings.healthCheck) { LText("Health-Check vor Launch") }
                    .helpLText("Prüft Wine-Binary, Prefix-Integrität und Installationspfad")

                Divider()

                // Logging
                LText("Logging & Monitoring").font(.caption).foregroundColor(.secondary)
                Toggle(isOn: $game.runtimeSettings.processLogging) { LText("Prozess-Logging (stdout/stderr)") }
                    .helpLText("Erfasst die Ausgabe des gestarteten Prozesses im Log-Viewer")
                Toggle(isOn: $game.runtimeSettings.statsMonitoring) { LText("Ressourcen-Überwachung (CPU/RAM)") }
                    .helpLText("Sammelt CPU- und Speicherstatistiken während der Laufzeit")
                Toggle(isOn: $game.runtimeSettings.logFileRotation) { LText("Log-Datei auf Festplatte schreiben") }
                    .helpLText("Rotierende Logdatei in ~/Library/Application Support/LutrisForMac/runtime-logs/")
                Toggle(isOn: $game.runtimeSettings.wineDebugLogging) { LText("Wine-Debug-Logs (WINEDEBUG)") }
                    .helpLText("Setzt WINEDEBUG gemäß Wine-Debug-Kanälen (siehe Wine-Konfiguration)")

                Divider()

                // Scripting
                LText("Scripting").font(.caption).foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    LText("Pre-Launch-Skript").font(.caption).foregroundColor(.secondary)
                    TextEditor(text: $game.preLaunchScript)
                        .frame(height: 50)
                        .font(.system(.caption, design: .monospaced))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
                }
                VStack(alignment: .leading, spacing: 4) {
                    LText("Post-Exit-Skript").font(.caption).foregroundColor(.secondary)
                    TextEditor(text: $game.postExitScript)
                        .frame(height: 50)
                        .font(.system(.caption, design: .monospaced))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
                }
            }
        } label: {
            LText("Runtime-Optionen").font(.system(size: 16)).frame(maxWidth: .infinity)
        }
    }
}
