import SwiftUI
import UniformTypeIdentifiers

struct InstallerWindowView: View {
    @ObservedObject var viewModel: GameLibraryViewModel
    @StateObject private var engine = InstallerEngine.shared
    @StateObject private var wineManager = WineManager.shared
    @Environment(\.dismiss) private var dismiss

    // Wizard-Schritte
    @State private var currentStep = 0
    @State private var gameName = ""
    @State private var installPath = "/Applications"
    @State private var selectedRunner = "Wine"
    @State private var selectedWineVersion: WineVersion? = nil
    @State private var sourceType: SourceType = .url
    @State private var sourceURL = ""
    @State private var sourceFile: URL? = nil
    @State private var prefixName = ""
    @State private var prefixArch = "win64"
    @State private var envVars: [String: String] = [:]
    @State private var winetricksArgs: String = ""
    @State private var useExistingPrefix = false
    @State private var selectedExistingPrefix: WinePrefix? = nil
    @State private var showCommunity = false
    @State private var showJSONEditor = false
    @State private var generatedJSON = ""
    @State private var installSuccess = false
    @State private var jsonError: String?

    @ObservedObject private var emuManager = EmulatorManager.shared
    @State private var showWineManager = false

    enum SourceType: String, CaseIterable {
        case url = "URL"
        case file = "Datei"
        case template = "Vorlage"
        case community = "Community"
    }

    let steps = ["Spiel", "Runner", "Quelle", "Details", "Installation"]

    var body: some View {
        VStack(spacing: 0) {
            if engine.isRunning {
                runningView
            } else if installSuccess {
                successView
            } else if showJSONEditor {
                jsonEditorFallbackView
            } else if showCommunity {
                CommunityInstallerView(viewModel: viewModel)
            } else {
                wizardView
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .sheet(isPresented: $showWineManager) {
            WineSettingsView()
        }
    }

    // MARK: - Wizard

    private var wizardView: some View {
        VStack(spacing: 0) {
            // Step indicator
            HStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, label in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(i <= currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                            .frame(width: 22, height: 22)
                            .overlay(
                                Text("\(i + 1)")
                                    .font(.caption.bold())
                                    .foregroundColor(i <= currentStep ? .white : .secondary)
                            )
                    Text(verbatim: tr(label))
                        .font(.caption)
                        .foregroundColor(i <= currentStep ? .primary : .secondary)
                    }
                    if i < steps.count - 1 {
                        Rectangle()
                            .fill(i < currentStep ? Color.accentColor : Color.gray.opacity(0.2))
                            .frame(height: 2)
                            .frame(maxWidth: 40)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            // Step content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch currentStep {
                    case 0: stepGameInfo
                    case 1: stepRunner
                    case 2: stepSource
                    case 3: stepConfig
                    case 4: stepSummary
                    default: EmptyView()
                    }
                }
                .padding(20)
            }

            Divider()

            if let jsonError = jsonError {
                Text(jsonError)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
            if let engineError = engine.error, !engineError.isEmpty {
                Text(engineError)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            // Navigation buttons
            HStack {
                if currentStep > 0 {
                    Button { withAnimation { currentStep -= 1 } } label: { LText("Zurück") }
                    .keyboardShortcut(.leftArrow)
                }
                Spacer()
                if currentStep == steps.count - 1 {
                    Button {
                        installFromWizard()
                    } label: {
                        Label { LText("Installieren") } icon: { Image(systemName: "hammer") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(gameName.isEmpty)
                } else {
                    Button { withAnimation { currentStep += 1 } } label: { LText("Weiter") }
                    .keyboardShortcut(.return)
                    .disabled(!canGoNext)
                }
                Button { dismiss() } label: { LText("Abbrechen") }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
    }

    private var canGoNext: Bool {
        switch currentStep {
        case 0: return !gameName.isEmpty
        case 1: return !selectedRunner.isEmpty
        case 2:
            switch sourceType {
            case .url: return !sourceURL.isEmpty
            case .file: return sourceFile != nil
            case .template, .community: return true
            }
        case 3: return true
        default: return false
        }
    }

    // MARK: - Step 0: Spiel-Info

    private var stepGameInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            LText("Wie heißt dein Spiel?")
                .font(.title2).bold()
            TextField(tr("Spielname"), text: $gameName)
                .textFieldStyle(.roundedBorder)

            LText("Wohin soll es installiert werden?")
                .font(.title2).bold()
            HStack {
                TextField(tr("Installationspfad"), text: $installPath)
                    .textFieldStyle(.roundedBorder)
                Button { chooseInstallPath() } label: { LText("Wählen") }
            }

            LText("Du kannst später alles in der Bibliothek anpassen.")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    // MARK: - Step 1: Runner

    private var runnerOptions: [(String, String, String)] {
        var options: [(String, String, String)] = [
            ("Wine", "wineglass", "Windows-Spiele (via Wine/Crossover/GPTK)"),
            ("Native macOS", "macwindow", "Mac-.app oder .dmg"),
        ]
        for emu in emuManager.emulators {
            options.append((emu.name, self.icon(for: emu.name), emu.description))
        }
        return options
    }

    private func icon(for name: String) -> String {
        switch name {
        case "DOSBox", "DOSBox-X": "terminal"
        case "RetroArch", "OpenEmu": "gamecontroller"
        case "ScummVM": "pointfilltopleft"
        case "Dolphin": "gamecontroller"
        case "MelonDS": "gamecontroller"
        case "Ryujinx", "Astris": "gamecontroller"
        case "Azahar": "gamecontroller"
        case "PCSX2", "RPCS3", "DuckStation": "gamecontroller"
        case "Flycast": "gamecontroller"
        case "PPSSPP": "gamecontroller"
        case "PlayCover": "app"
        default: "gamecontroller"
        }
    }

    private var stepRunner: some View {
        VStack(alignment: .leading, spacing: 12) {
            LText("Welche Art von Spiel möchtest du installieren?")
                .font(.title2).bold()

            ForEach(runnerOptions, id: \.0) { (name, icon, desc) in
                Button {
                    selectedRunner = name
                } label: {
                    HStack {
                        Image(systemName: icon)
                            .font(.title3)
                            .frame(width: 24)
                        VStack(alignment: .leading) {
                            Text(verbatim: tr(name)).font(.headline)
                            Text(verbatim: tr(desc)).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        if selectedRunner == name {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding(10)
                    .background(selectedRunner == name ? Color.accentColor.opacity(0.08) : Color.clear)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            if selectedRunner == "Wine" {
                Divider()
                LText("Wine-Version (optional)")
                    .font(.headline)

                let installed = wineManager.installedVersions
                if installed.isEmpty {
                    HStack {
                        LText("Keine Wine-Version installiert.")
                            .foregroundColor(.secondary)
                    Button { showWineManager = true } label: { LText("Verwalten…") }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Picker("", selection: $selectedWineVersion) {
                        Text(verbatim: tr("Automatisch (erste verfügbare)")).tag(nil as WineVersion?)
                        ForEach(installed) { v in
                            HStack {
                                Text(v.displayName)
                                if wineManager.isCached(v.name) {
                                    Image(systemName: "archivebox.fill").foregroundColor(.orange)
                                }
                            }.tag(v as WineVersion?)
                        }
                    }
                    .labelsHidden()
                    Button { showWineManager = true } label: { LText("Wine-Versionen verwalten") }
                        .buttonStyle(.bordered)
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Step 2: Quelle

    private var stepSource: some View {
        VStack(alignment: .leading, spacing: 12) {
            LText("Woher bekommst du die Installationsdatei?")
                .font(.title2).bold()

            Picker("", selection: $sourceType) {
                ForEach(SourceType.allCases, id: \.self) { t in
                    Text(verbatim: tr(t.rawValue)).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch sourceType {
            case .url:
                VStack(alignment: .leading, spacing: 4) {
                    LText("Direktlink zur Installationsdatei (.exe, .app, .dmg, .zip…)")
                        .font(.caption)
                    TextField("https://example.com/spiel/setup.exe", text: $sourceURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                }

            case .file:
                VStack(alignment: .leading, spacing: 4) {
                    LText("Wähle die Installationsdatei von deinem Mac aus.")
                        .font(.caption)
                    HStack {
                        Text(sourceFile?.lastPathComponent ?? "Keine Datei ausgewählt")
                            .foregroundColor(sourceFile != nil ? .primary : .secondary)
                        Spacer()
                        Button { chooseSourceFile() } label: { LText("Durchsuchen…") }
                    }
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
                }

            case .template:
                templatePickerView

            case .community:
                VStack(spacing: 12) {
                    LText("Durchsuche Community-Installationsskripte.")
                        .font(.caption).foregroundColor(.secondary)
                    Button { showCommunity = true } label: { LText("Community-Skripte durchsuchen") }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    @ViewBuilder
    private var templatePickerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            LText("Wähle eine Vorlage als Ausgangspunkt:")
                .font(.caption)
            List(InstallerScript.samples) { script in
                Button {
                    selectedRunner = script.runner
                    sourceURL = ""
                    sourceFile = nil
                    // Lade die Vorlage in den JSON-Editor, damit der Nutzer sie anpassen kann
                    if let data = try? JSONEncoder().encode(script),
                       let json = String(data: data, encoding: .utf8) {
                        generatedJSON = json
                    }
                } label: {
                    VStack(alignment: .leading) {
                        Text(script.name).font(.headline)
                        Text(script.description).font(.caption).foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.bordered)
            .frame(height: 200)
            LText("Nach Auswahl einer Vorlage kannst du sie im JSON-Editor anpassen.")
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    // MARK: - Step 3: Konfiguration

    private var stepConfig: some View {
        VStack(alignment: .leading, spacing: 12) {
            LText("Weitere Einstellungen")
                .font(.title2).bold()

            if selectedRunner == "Wine" || selectedRunner == "DOSBox" {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        LText("Wine-Prefix")
                            .font(.headline)

                        Picker("", selection: $useExistingPrefix) {
                            Text(verbatim: tr("Neuen Prefix erstellen")).tag(false)
                            Text(verbatim: tr("Vorhandenen Prefix verwenden")).tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        if useExistingPrefix {
                            let prefixes = wineManager.prefixes
                            if prefixes.isEmpty {
                                LText("Keine vorhandenen Prefixes gefunden.")
                                    .foregroundColor(.secondary)
                                Button { showWineManager = true } label: { LText("Prefix verwalten…") }
                                    .buttonStyle(.bordered)
                            } else {
                                Picker("", selection: $selectedExistingPrefix) {
                                    Text(verbatim: tr("Bitte wählen…")).tag(nil as WinePrefix?)
                                    ForEach(prefixes) { p in
                                        HStack {
                                            Text(p.name)
                                            Text(p.architecture.displayName).font(.caption).foregroundColor(.secondary)
                                        }.tag(p as WinePrefix?)
                                    }
                                }
                                .labelsHidden()

                                if let sel = selectedExistingPrefix {
                                    HStack(spacing: 4) {
                                        Image(systemName: "folder").foregroundColor(.blue)
                                        Text(sel.path).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                        } else {
                            HStack {
                                LText("Name:")
                                    .frame(width: 70, alignment: .trailing)
                                TextField(tr("Präfix-Name"), text: $prefixName)
                                    .textFieldStyle(.roundedBorder)
                            }
                            HStack {
                                LText("Architektur:")
                                    .frame(width: 70, alignment: .trailing)
                                Picker("", selection: $prefixArch) {
                                    Text("win64").tag("win64")
                                    Text("win32").tag("win32")
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                            }
                        }
                    }
                    .padding(4)
                }
                .onAppear {
                    if prefixName.isEmpty { prefixName = "\(gameName.lowercased().replacingOccurrences(of: " ", with: "-"))-prefix" }
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    LText("Umgebungsvariablen (optional)")
                        .font(.headline)
                    ForEach(Array(envVars.keys.sorted()), id: \.self) { key in
                        HStack {
                            TextField("KEY", text: .init(
                                get: { key },
                                set: { newKey in
                                    let val = envVars.removeValue(forKey: key) ?? ""
                                    envVars[newKey] = val
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            Text("=")
                            TextField("VALUE", text: .init(
                                get: { envVars[key] ?? "" },
                                set: { envVars[key] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            Button {
                                envVars.removeValue(forKey: key)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button {
                        let newKey = "VAR\(envVars.count + 1)"
                        envVars[newKey] = ""
                    } label: {
                        Label { LText("Variable hinzufügen") } icon: { Image(systemName: "plus.circle") }
                    }
                }
                .padding(4)
            }
            // Winetricks input
            if selectedRunner == "Wine" {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        LText("Winetricks (optional)")
                            .font(.headline)
                        Text("Gib Winetricks-Verben ein, z.B. vcrun2019 vcrun2015")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("vcrun2019 vcrun2015", text: $winetricksArgs)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(4)
                }
            }
        }
    }

    // MARK: - Step 4: Zusammenfassung

    private var stepSummary: some View {
        VStack(alignment: .leading, spacing: 16) {
            LText("Zusammenfassung")
                .font(.title2).bold()

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    summaryRow("Spielname", gameName)
                    summaryRow("Installationspfad", installPath)
                    summaryRow("Runner", selectedRunner)
                    if selectedRunner == "Wine" {
                        summaryRow("Wine-Version", selectedWineVersion?.displayName ?? "Automatisch")
                        if useExistingPrefix, let pfx = selectedExistingPrefix {
                            summaryRow("Prefix", pfx.name)
                            summaryRow("Architektur", pfx.architecture.displayName)
                        } else {
                            summaryRow("Prefix", prefixName.isEmpty ? "\(gameName)-prefix" : prefixName)
                            summaryRow("Architektur", prefixArch)
                        }
                    }
                    summaryRow("Quelle", sourceType == .url ? sourceURL : (sourceType == .file ? sourceFile?.path ?? "" : sourceType.rawValue))
                    if !envVars.isEmpty {
                        summaryRow("Umgebungsvariablen", envVars.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
                    }
                    if !winetricksArgs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        summaryRow("Winetricks", winetricksArgs)
                    }
                }
                .padding(4)
            }

            HStack {
                Spacer()
                Button {
                    generateScriptFromWizard()
                    showJSONEditor = true
                } label: { LText("Als JSON bearbeiten…") }
                .buttonStyle(.bordered)
            }
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
            HStack(alignment: .top) {
                Text(verbatim: tr(label) + ":")
                    .font(.subheadline.bold())
                    .frame(width: 120, alignment: .trailing)
                Text(value)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
    }

    // MARK: - Script-Generierung

    private func generateScriptFromWizard() {
        let tasks: [InstallerScript.InstallTask]
        let runner = selectedRunner == "Native macOS" ? "Native" : selectedRunner
        let platform = runner == "Wine" ? "Windows" : (runner == "Native" ? "macOS" : runner)

        let prefixNameResolved: String = {
            if useExistingPrefix, let pfx = selectedExistingPrefix {
                return pfx.name
            }
            return prefixName.isEmpty ? "\(gameName.lowercased().replacingOccurrences(of: " ", with: "-"))-prefix" : prefixName
        }()

        let prefixArchResolved: String = {
            if useExistingPrefix, let pfx = selectedExistingPrefix {
                return pfx.architecture.rawValue
            }
            return prefixArch
        }()

        switch (runner, sourceType) {
        case ("Wine", .url):
            var t: [InstallerScript.InstallTask] = []
            t.append(.mkdir(path: "{gamePath}", description: "Erstelle Spiel-Ordner"))
            var winePathForTasks: String? = nil
            // If a Wine version is selected and cached, extract it from cache into the game folder before creating the prefix
            if let sel = selectedWineVersion {
                if wineManager.isCached(sel.name) {
                    let safeName = sel.name
                    let dest = "{gamePath}/\(safeName)"
                    t.append(.extract(archive: wineManager.archivePathInCache(sel.name).path, dest: dest, type: nil, description: "Entpacke Wine aus Cache: \(safeName)"))
                    winePathForTasks = "\(dest)/bin/wine"
                } else {
                    // installed version will be picked by useWineVersion variable
                    winePathForTasks = nil
                }
            }
            if !useExistingPrefix {
                t.append(.mkdir(path: "{gamePath}/prefix", description: "Erstelle Prefix-Ordner"))
                t.append(.createPrefix(name: prefixNameResolved, arch: prefixArchResolved, prefixPath: "{gamePath}/prefix", winePath: winePathForTasks, description: "Erstelle Wine-Prefix"))
            }
            let winePrefixForTasks = useExistingPrefix ? (selectedExistingPrefix?.path ?? prefixNameResolved) : "{gamePath}/prefix"

            // Winetricks: optional verbs provided by the user
            if !winetricksArgs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let verbs = winetricksArgs.split(separator: " ").map { String($0) }
                t.append(.wineTricks(verbs: verbs, prefixPath: winePrefixForTasks, winePath: winePathForTasks, description: "Installiere Winetricks-Pakete: \(winetricksArgs)"))
            }

            t.append(contentsOf: [
                .download(url: sourceURL, dest: "{tmp}/setup.exe", description: "Lade Installer herunter"),
                .wineExecute(executable: "{tmp}/setup.exe", args: nil, winePrefix: winePrefixForTasks, winePath: winePathForTasks, description: "Führe Installer aus"),
                .message(text: "\(gameName) wurde installiert!", description: nil),
            ])
            for (key, val) in envVars where !key.isEmpty {
                t.append(.setEnvironment(key: key, value: val, description: nil))
            }
            tasks = t

        case ("Wine", .file):
            let src = sourceFile?.path ?? ""
            var t: [InstallerScript.InstallTask] = []
            t.append(.mkdir(path: "{gamePath}", description: "Erstelle Spiel-Ordner"))
            var winePathForTasks: String? = nil
            if let sel = selectedWineVersion, wineManager.isCached(sel.name) {
                let safeName = sel.name
                let dest = "{gamePath}/\(safeName)"
                t.append(.extract(archive: wineManager.archivePathInCache(sel.name).path, dest: dest, type: nil, description: "Entpacke Wine aus Cache: \(safeName)"))
                winePathForTasks = "\(dest)/bin/wine"
            }
            if !useExistingPrefix {
                t.append(.mkdir(path: "{gamePath}/prefix", description: "Erstelle Prefix-Ordner"))
                t.append(.createPrefix(name: prefixNameResolved, arch: prefixArchResolved, prefixPath: "{gamePath}/prefix", winePath: winePathForTasks, description: "Erstelle Wine-Prefix"))
            }
            let winePrefixForTasks = useExistingPrefix ? (selectedExistingPrefix?.path ?? prefixNameResolved) : "{gamePath}/prefix"

            // Winetricks: optional verbs provided by the user
            if !winetricksArgs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let verbs = winetricksArgs.split(separator: " ").map { String($0) }
                t.append(.wineTricks(verbs: verbs, prefixPath: winePrefixForTasks, winePath: winePathForTasks, description: "Installiere Winetricks-Pakete: \(winetricksArgs)"))
            }

            t.append(contentsOf: [
                .wineExecute(executable: src, args: nil, winePrefix: winePrefixForTasks, winePath: winePathForTasks, description: "Führe Installer aus"),
                .message(text: "\(gameName) wurde installiert!", description: nil),
            ])
            for (key, val) in envVars where !key.isEmpty {
                t.append(.setEnvironment(key: key, value: val, description: nil))
            }
            tasks = t

        case ("Native", .url):
            let isDmg = sourceURL.lowercased().hasSuffix(".dmg")
            if isDmg {
                tasks = [
                    .download(url: sourceURL, dest: "{tmp}/download.dmg", description: "Lade Spiel herunter"),
                    .extract(archive: "{tmp}/download.dmg", dest: "{tmp}/extracted", type: .dmg, description: "Hänge DMG ein"),
                    .execute(command: "cp -R \"{tmp}/extracted/*.app\" /Applications/", description: "Kopiere nach /Applications"),
                    .message(text: "\(gameName) wurde installiert!", description: nil),
                ]
            } else {
                tasks = [
                    .download(url: sourceURL, dest: "{tmp}/game.app", description: "Lade Spiel herunter"),
                    .execute(command: "cp -R \"{tmp}/game.app\" /Applications/", description: "Kopiere nach /Applications"),
                    .message(text: "\(gameName) wurde installiert!", description: nil),
                ]
            }

        case ("Native", .file):
            let src = sourceFile?.path ?? ""
            tasks = [
                .execute(command: "cp -R \"\(src)\" /Applications/", description: "Kopiere nach /Applications"),
                .message(text: "\(gameName) wurde installiert!", description: nil),
            ]

        case ("DOSBox", .url):
            tasks = [
                .mkdir(path: "{gamePath}", description: "Erstelle Spiel-Ordner"),
                .download(url: sourceURL, dest: "{tmp}/game.zip", description: "Lade Spiel herunter"),
                .extract(archive: "{tmp}/game.zip", dest: "{gamePath}", type: .zip, description: "Extrahiere Spiel"),
                .message(text: "Spiel bereit. Starte es mit DOSBox.", description: nil),
            ]

        case ("DOSBox", .file):
            let src = sourceFile?.path ?? ""
            tasks = [
                .mkdir(path: "{gamePath}", description: "Erstelle Spiel-Ordner"),
                .execute(command: "cp -R \"\(src)\" \"{gamePath}/\"", description: "Kopiere Spiel"),
                .message(text: "Spiel bereit. Starte es mit DOSBox.", description: nil),
            ]

        case ("RetroArch", .url):
            tasks = [
                .mkdir(path: "{gamePath}", description: "Erstelle Spiel-Ordner"),
                .download(url: sourceURL, dest: "{gamePath}/rom", description: "Lade ROM herunter"),
                .message(text: "ROM installiert. Starte es mit RetroArch.", description: nil),
            ]

        default:
            tasks = [
                .download(url: sourceURL.isEmpty ? "https://example.com/game" : sourceURL, dest: "{tmp}/game", description: "Lade Spiel herunter"),
                .message(text: "\(gameName) wurde installiert!", description: nil),
            ]
        }

        let script = InstallerScript(
            name: "Wizard: \(gameName)",
            gameName: gameName,
            runner: runner,
            platform: platform,
            description: "Erstellt via Installations-Assistent",
            tasks: tasks,
            environmentVariables: envVars,
            requires: runner == "Wine" ? ["Wine"] : []
        )

        if let data = try? JSONEncoder().encode(script),
           let json = String(data: data, encoding: .utf8) {
            generatedJSON = json
        }
    }

    private func installFromWizard() {
        jsonError = nil
        engine.error = nil
        generateScriptFromWizard()
        guard let data = generatedJSON.data(using: .utf8) else {
            jsonError = "Konnte Script nicht erzeugen: Ungültige JSON-Daten"
            return
        }

        do {
            let script = try JSONDecoder().decode(InstallerScript.self, from: data)
            Task {
                engine.variables["useWineVersion"] = selectedWineVersion?.name
                let success = await engine.run(script: script, gamePath: installPath, gameName: gameName)
                if success {
                    var game = Game(
                        name: gameName,
                        platform: script.platform,
                        installPath: installPath,
                        runner: script.runner,
                        notes: "Installiert via Assistent"
                    )
                    // Save wine paths from the install process
                    if let wineBin = engine.variables["wineBin"] {
                        game.wineBinaryPath = wineBin
                    }
                    if let prefixPath = engine.variables["winePrefixPath"] {
                        game.winePrefixPath = prefixPath
                    }
                    await MainActor.run {
                        viewModel.games.append(game)
                        viewModel.saveLibrary()
                        installSuccess = true
                    }
                }
            }
        } catch {
            jsonError = "Konnte Script nicht erzeugen: \(error.localizedDescription)"
        }
    }

    // MARK: - JSON-Fallback

    private var jsonEditorFallbackView: some View {
        VStack(spacing: 8) {
            LText("Skript-Editor")
                .font(.title2).bold()

            Form {
                Section(header: Text(verbatim: tr("Spiel"))) {
                    TextField(tr("Spielname"), text: $gameName)
                    HStack {
                        TextField(tr("Installationspfad"), text: $installPath)
                        Button { chooseInstallPath() } label: { LText("Wählen") }
                    }
                }

                Section(header: Text(verbatim: tr("Skript (JSON)"))) {
                    TextEditor(text: $generatedJSON)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 200)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.25))
                        )
                }

                if let error = jsonError {
                    Text(error).foregroundColor(.red).font(.caption)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button { showJSONEditor = false } label: { LText("Assistent") }
                Spacer()
                Button { dismiss() } label: { LText("Abbrechen") }
                    .keyboardShortcut(.cancelAction)
                Button {
                    installFromJSON()
                } label: {
                    Label { LText("Installieren") } icon: { Image(systemName: "hammer") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(gameName.isEmpty || generatedJSON.isEmpty)
            }
            .padding()
        }
        .padding()
        .onChange(of: generatedJSON) { _, newValue in
            parseJSON(newValue)
        }
    }

    private func parseJSON(_ json: String) {
        guard let data = json.data(using: .utf8) else {
            jsonError = nil
            return
        }
        do {
            _ = try JSONDecoder().decode(InstallerScript.self, from: data)
            jsonError = nil
        } catch {
            jsonError = "JSON-Fehler: \(error.localizedDescription)"
        }
    }

    private func installFromJSON() {
        guard let data = generatedJSON.data(using: .utf8),
              let script = try? JSONDecoder().decode(InstallerScript.self, from: data) else {
            jsonError = "Ungültiges JSON"
            return
        }
        Task {
            let success = await engine.run(script: script, gamePath: installPath, gameName: gameName)
            if success {
                let game = Game(
                    name: gameName,
                    platform: script.platform,
                    installPath: installPath,
                    runner: script.runner,
                    notes: "Installiert via JSON-Skript"
                )
                await MainActor.run {
                    viewModel.games.append(game)
                    viewModel.saveLibrary()
                    installSuccess = true
                }
            }
        }
    }

    // MARK: - Running View

    private var runningView: some View {
        VStack(spacing: 16) {
            Text(verbatim: trf("Installiere %@...", gameName))
                .font(.title2).bold()

            ProgressView(value: engine.progress)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 4) {
                Text(engine.currentTaskDescription)
                    .font(.subheadline).foregroundColor(.secondary)

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(engine.log.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption).foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 220)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Button { engine.cancel() } label: { LText("Abbrechen") }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48)).foregroundColor(.green)

            Text(verbatim: trf("%@ wurde installiert!", gameName))
                .font(.title2).bold()

            LText("Das Spiel wurde zur Bibliothek hinzugefügt.")
                .foregroundColor(.secondary)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(engine.log.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 170)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Button { dismiss() } label: { LText("Schliessen") }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    // MARK: - Helpers

    private func chooseInstallPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = tr("Auswählen")
        if panel.runModal() == .OK, let url = panel.url {
            installPath = url.path
        }
    }

    private func chooseSourceFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.exe, .application, .diskImage, .zip, .archive]
        panel.prompt = tr("Auswählen")
        if panel.runModal() == .OK, let url = panel.url {
            sourceFile = url.standardizedFileURL
        }
    }
}
