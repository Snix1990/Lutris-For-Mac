import SwiftUI

struct RomFolderSettingsView: View {
    @StateObject private var manager = RomFolderManager.shared
    @State private var selectedPlatform = RomFolderManager.availablePlatforms[0]
    @State private var showFolderPicker = false
    @State private var isScanning = false
    @State private var scanResults: [String: [URL]] = [:]
    @State private var showResultAlert = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                LText("ROM-Ordner verwalten")
                    .font(.title2)
                    .bold()
                Spacer()
            }
            .padding()

            Divider()

            List {
                ForEach(manager.folders) { folder in
                    HStack {
                        Text(folder.platform)
                            .font(.headline)
                            .frame(width: 100, alignment: .leading)
                        Text(folder.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button(role: .destructive) {
                            manager.removeFolder(folder.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(minHeight: 120)

            HStack(spacing: 8) {
                Picker("", selection: $selectedPlatform) {
                    ForEach(RomFolderManager.availablePlatforms, id: \.self) { p in
                        Text(p).tag(p)
                    }
                }
                .labelsHidden()
                .frame(width: 120)

                Button {
                    showFolderPicker = true
                } label: {
                    LText("Ordner hinzufügen")
                }

                Spacer()

                Button {
                    isScanning = true
                    scanResults = [:]
                    Task {
                        scanResults = manager.scanROMs()
                        isScanning = false
                        showResultAlert = true
                    }
                } label: {
                    if isScanning {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        LText("Scannen")
                    }
                }
                .disabled(isScanning || manager.folders.isEmpty)
            }
            .padding()

            Divider()

            HStack {
                Spacer()
                Button {
                    importScannedGames()
                } label: {
                    LText("Gefundene Spiele importieren")
                }
                .disabled(scanResults.isEmpty)
            }
            .padding()
        }
        .frame(width: 520, height: 400)
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                manager.addFolder(platform: selectedPlatform, path: url.path)
            }
        }
        .alert(
            tr(scanResults.isEmpty ? "Keine ROMs gefunden" : "Scan abgeschlossen"),
            isPresented: $showResultAlert
        ) {
            Button("OK") { }
        } message: {
            if scanResults.isEmpty {
                LText("In den konfigurierten Ordnern wurden keine ROM-Dateien gefunden.")
            } else {
                let total = scanResults.values.reduce(0) { $0 + $1.count }
                let platforms = scanResults.keys.sorted().joined(separator: ", ")
                Text(verbatim: "\(total) ROMs gefunden in: \(platforms)")
            }
        }
    }

    private func importScannedGames() {
        let viewModel = GameLibraryViewModel.shared
        var imported = 0
        for (platform, files) in scanResults {
            for url in files {
                let name = url.deletingPathExtension().lastPathComponent
                let game = Game(
                    name: name,
                    platform: platform,
                    installPath: url.path,
                    runner: "RetroArch"
                )
                if !viewModel.games.contains(where: { $0.installPath == url.path }) {
                    viewModel.games.append(game)
                    imported += 1
                }
            }
        }
        if imported > 0 {
            viewModel.saveLibrary()
        }
        scanResults = [:]
    }
}
