import SwiftUI

struct SteamLibrarySyncView: View {
    @ObservedObject var viewModel: GameLibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = UserDefaults.standard.string(forKey: "steamAPIKey") ?? ""
    @State private var steamID: String = UserDefaults.standard.string(forKey: "steamID") ?? ""
    @State private var detectedID: String?
    @State private var detectedName: String?
    @State private var hasCheckedLocal = false

    var body: some View {
        VStack(spacing: 0) {
            header
            formContent
            Spacer()
            footer
        }
        .frame(minWidth: 520, minHeight: 400)
        .task {
            detectLocalSteamID()
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 36))
                .foregroundColor(.accentColor)
            LText("Steam-Bibliothek synchronisieren")
                .font(.title2)
                .bold()
            LText("Importiere deine gesamte Steam-Spielebibliothek inkl. Cover und Spielzeit.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }

    private var formContent: some View {
        Form {
            Section(header: Text(verbatim: tr("API-Key"))) {
                SecureField(tr("Steam Web API Key"), text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .helpLText("Du findest deinen Key unter https://steamcommunity.com/dev/apikey")
                Link("API-Key besorgen…", destination: URL(string: "https://steamcommunity.com/dev/apikey")!)
                    .font(.caption)
            }

            Section(header: Text(verbatim: tr("Steam64-ID"))) {
                if let id = detectedID {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(verbatim: trf("Gefunden: %@", id))
                            .font(.body.monospaced())
                        if let name = detectedName {
                            Text("(\(name))")
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button { steamID = id } label: { LText("Übernehmen") }
                        .buttonStyle(.borderedProminent)
                        .disabled(steamID == id)
                    }
                } else if hasCheckedLocal {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        LText("Keine lokale Steam-Installation gefunden.")
                    }
                } else {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        LText("Suche nach lokaler Steam-Installation…")
                    }
                }

                if !detectedIDConfirmed {
                    TextField(tr("Steam64-ID manuell eingeben"), text: $steamID)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if viewModel.isSteamSyncing {
                Section(header: Text(verbatim: tr("Fortschritt"))) {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(viewModel.steamSyncProgress)
                            .font(.caption)
                    }
                }
            }

            if let error = viewModel.steamSyncError {
                Section(header: Text(verbatim: tr("Fehler"))) {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }

            if viewModel.steamSyncResults > 0 {
                Section(header: Text(verbatim: tr("Ergebnis"))) {
                    Text(verbatim: trf("%d neue Spiele importiert.", viewModel.steamSyncResults))
                        .foregroundColor(.green)
                        .font(.headline)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: { LText("Schliessen") }
                .keyboardShortcut(.cancelAction)

            Spacer()

            Button {
                sync()
            } label: {
                Label { LText("Synchronisieren") } icon: { Image(systemName: "arrow.triangle.2.circlepath") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isSteamSyncing || apiKey.isEmpty || steamID.isEmpty)
        }
        .padding()
    }

    private var detectedIDConfirmed: Bool {
        !steamID.isEmpty && steamID == detectedID
    }

    private func detectLocalSteamID() {
        hasCheckedLocal = true
        if let id = SteamAPI.shared.detectSteamID() {
            detectedID = id
            detectedName = SteamAPI.shared.detectAccountName(steamID: id)
            if steamID.isEmpty { steamID = id }
        }
    }

    private func sync() {
        UserDefaults.standard.set(apiKey, forKey: "steamAPIKey")
        UserDefaults.standard.set(steamID, forKey: "steamID")
        Task {
            await viewModel.syncSteamLibrary(apiKey: apiKey, steamID: steamID)
        }
    }
}
