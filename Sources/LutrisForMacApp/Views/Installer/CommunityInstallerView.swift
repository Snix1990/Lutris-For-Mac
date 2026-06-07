import SwiftUI

struct CommunityInstallerView: View {
    @ObservedObject var viewModel: GameLibraryViewModel
    @StateObject private var service = CommunityInstallerService.shared
    @StateObject private var engine = InstallerEngine.shared
    @State private var showingSettings = false
    @State private var installPath: String = "/Applications"
    @State private var selectedScript: CommunityScript?
    @State private var downloadedScript: InstallerScript?
    @State private var installSuccess = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            if engine.isRunning {
                runningView
            } else if installSuccess {
                successView
            } else {
                mainListView
            }
        }
        .frame(minWidth: 540, minHeight: 420)
        .task {
            if service.scripts.isEmpty {
                await service.fetchIndex()
            }
        }
        .sheet(isPresented: $showingSettings) {
            settingsSheet
        }
    }

    // MARK: - Main List

    private var mainListView: some View {
        VStack(spacing: 0) {
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField(tr("Suchen..."), text: $service.searchText)
                        .textFieldStyle(.plain)
                    if !service.searchText.isEmpty {
                        Button { service.searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))

                if service.isFetching {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 24)
                }

                Button {
                    Task { await service.fetchIndex() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .helpLText("Index aktualisieren")
                .disabled(service.isFetching)

                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .helpLText("Index-URL einstellen")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if service.lastError != nil {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(service.lastError!)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
            }

            if service.filteredScripts.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text(service.isFetching ? "Lade Index..." : "Keine Skripte gefunden")
                        .foregroundColor(.secondary)
                    if !service.isFetching {
                    Button { Task { await service.fetchIndex() } } label: { LText("Index neu laden") }
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(service.filteredScripts) { script in
                        Button {
                            selectedScript = script
                            selectScript(script)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(script.gameName)
                                        .font(.headline)
                                    Text(script.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                    HStack(spacing: 8) {
                                        Label(script.runner, systemImage: "gearshape")
                                        Label("v\(script.version)", systemImage: "tag")
                                        if let author = script.author {
                                            Label(author, systemImage: "person")
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.bordered)
                .alternatingRowBackgrounds()
            }

            HStack {
                Button { dismiss() } label: { LText("Abbrechen") }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if !installPath.isEmpty {
                    Text(verbatim: trf("Installationspfad: %@", installPath))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Button { chooseInstallPath() } label: { LText("Ordner wählen") }
            }
            .padding()
        }
    }

    // MARK: - Settings

    private var settingsSheet: some View {
        VStack(spacing: 16) {
            LText("Community-Index Einstellungen")
                .font(.title2)
                .bold()

            LText("Gib die URL zu einer JSON-Index-Datei ein, die Community-Installationsskripte auflistet.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            TextField(tr("Index-URL"), text: Binding(
                get: { service.indexURL },
                set: { service.indexURL = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.caption)

            HStack {
                Button { showingSettings = false } label: { LText("Schliessen") }
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task { await service.fetchIndex() }
                    showingSettings = false
                } label: { LText("Speichern & Laden") }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 420)
    }

    // MARK: - Running

    private var runningView: some View {
        VStack(spacing: 16) {
            Text(verbatim: trf("Installiere %@...", selectedScript?.gameName ?? ""))
                .font(.title2)
                .bold()

            ProgressView(value: engine.progress)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 4) {
                Text(engine.currentTaskDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(engine.log.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 200)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Button { engine.cancel() } label: { LText("Abbrechen") }
        }
        .padding()
    }

    // MARK: - Success

    private var successView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text(verbatim: trf("%@ wurde installiert!", selectedScript?.gameName ?? ""))
                .font(.title2)
                .bold()

            LText("Das Spiel wurde zur Bibliothek hinzugefügt.")
                .foregroundColor(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(engine.log.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxHeight: 150)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Button { dismiss() } label: { LText("Schliessen") }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    // MARK: - Logic

    private func selectScript(_ meta: CommunityScript) {
        Task {
            guard let script = await service.downloadScript(meta) else { return }
            downloadedScript = script

            let success = await engine.run(script: script, gamePath: installPath, gameName: meta.gameName)
            if success {
                var game = Game(
                    name: meta.gameName,
                    platform: meta.platform,
                    installPath: installPath,
                    runner: meta.runner,
                    notes: "Installiert via Community-Skript (\(meta.version))"
                )
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
    }

    private func chooseInstallPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = tr("Auswählen")
        if panel.runModal() == .OK, let url = panel.url {
            installPath = url.path
        }
    }
}
