import SwiftUI

struct ServiceSettingsView: View {
    @StateObject private var serviceManager = ServiceManager.shared
    @ObservedObject var viewModel: GameLibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isImporting = false
    @State private var importMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            serviceList
            scannedList
            footer
        }
        .frame(minWidth: 520, minHeight: 480)
    }

    private var header: some View {
        VStack(spacing: 4) {
            LText("Drittanbieter-Integrationen")
                .font(.title2)
                .bold()
            LText("Scanne installierte Spiele von Steam, Heroic, itch.io und Battle.net")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private var serviceList: some View {
        List {
            Section(header: Text(verbatim: tr("Verfügbare Dienste"))) {
                ForEach(serviceManager.services) { service in
                    HStack {
                        Image(systemName: service.iconSystemName)
                            .frame(width: 24)
                            .foregroundColor(service.installed ? .accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(service.displayName)
                                .font(.headline)
                            HStack(spacing: 6) {
                                statusBadge(service.installed, text: tr("Installiert"))
                                if service.gameCount > 0 {
                                    Text(verbatim: trf("%d importiert", service.gameCount))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        Spacer()
                        if service.installed {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .listStyle(.bordered)
        .alternatingRowBackgrounds()
    }

    private var scannedList: some View {
        Group {
            if !serviceManager.scannedGames.isEmpty {
                List {
                    Section(header: Text(verbatim: tr("Gefundene Spiele (\(serviceManager.scannedGames.count))"))) {
                        ForEach(serviceManager.scannedGames) { game in
                            HStack {
                                Text(game.serviceName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 60, alignment: .leading)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(game.name)
                                        .font(.body)
                                    Text(game.installPath)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .listStyle(.bordered)
                .alternatingRowBackgrounds()
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if isImporting {
                ProgressView()
                    .scaleEffect(0.8)
                LText("Scanne nach installierten Spielen...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !importMessage.isEmpty {
                Text(importMessage)
                    .font(.caption)
                    .foregroundColor(.green)
            }

            HStack(spacing: 12) {
                Button { dismiss() } label: { LText("Schliessen") }
                    .keyboardShortcut(.cancelAction)

                Button {
                    Task { await scanAndImport() }
                } label: {
                    Label { LText("Scannen & Importieren") } icon: { Image(systemName: "arrow.triangle.2.circlepath") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isImporting)
            }
        }
        .padding()
    }

    private func scanAndImport() async {
        isImporting = true
        importMessage = ""

        await serviceManager.scanAllServices()

        let count = serviceManager.importGames(serviceManager.scannedGames, into: &viewModel.games)
        viewModel.saveLibrary()
        importMessage = trf("%d neue Spiele importiert.", count)
        isImporting = false
    }

    private func statusBadge(_ active: Bool, text: String) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(active ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            Text(verbatim: active ? tr("Ja") : tr("Nein"))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
