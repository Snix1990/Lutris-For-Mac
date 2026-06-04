import SwiftUI

struct EmulatorSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = EmulatorManager.shared
    @State private var selectedPlatform: String = "Alle"
    @State private var isCheckingUpdates = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                LText("Emulatoren verwalten")
                    .font(.title2)
                    .bold()
                Spacer()
                if isCheckingUpdates {
                    ProgressView()
                        .controlSize(.small)
                    LText("Suche nach Updates…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if manager.isDownloading {
                    ProgressView()
                        .controlSize(.small)
                    Text(manager.installStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Button {
                    isCheckingUpdates = true
                    Task {
                        await manager.checkForUpdates()
                        isCheckingUpdates = false
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isCheckingUpdates || manager.isDownloading)
                .helpLText("Nach Updates suchen")
            }
            .padding()

            Divider()

            if let error = manager.installError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1))
                .padding(.bottom, 4)
            }

            HStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(platforms, id: \.self) { platform in
                            Button {
                                selectedPlatform = platform
                            } label: {
                                HStack {
                                    Text(platform)
                                        .foregroundColor(selectedPlatform == platform ? .accentColor : .primary)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    selectedPlatform == platform
                                        ? Color.accentColor.opacity(0.1)
                                        : Color.clear
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .frame(width: 130)

                Divider()

                ScrollView {
                    VStack(spacing: 16) {
                        let filtered = filteredEmulators
                        if filtered.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                                LText("Keine Emulatoren für diese Plattform")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 40)
                            .frame(maxWidth: .infinity)
                        }
                        ForEach(filtered) { emu in
                            EmulatorRow(emu: emu, manager: manager)
                        }
                    }
                    .padding(20)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button { dismiss() } label: { LText("Schliessen") }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 640, height: 540)
        .onAppear {
            manager.detectInstalled()
            Task { await manager.checkForUpdates() }
        }
    }

    private var filteredEmulators: [Emulator] {
        if selectedPlatform == "Alle" {
            return manager.emulators
        }
        return manager.emulators.filter { $0.supportsPlatforms.contains(selectedPlatform) }
    }

    private var platforms: [String] {
        let all = manager.emulators.flatMap(\.supportsPlatforms)
        return ["Alle"] + Set(all).sorted()
    }
}

private struct EmulatorRow: View {
    let emu: Emulator
    @ObservedObject var manager: EmulatorManager
    @State private var isWorking = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(emu.displayName)
                    .font(.headline)
                Text(emu.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(emu.category.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(3)
                    if !emu.supportsPlatforms.isEmpty {
                        Text(emu.supportsPlatforms.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Text(emu.installType.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if manager.isDownloading && manager.installStatus.contains(emu.displayName) {
                if manager.downloadProgress > 0 && manager.downloadProgress < 1 {
                    ProgressView(value: manager.downloadProgress)
                        .frame(width: 60)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            } else if isWorking {
                ProgressView()
                    .controlSize(.small)
            } else if emu.updateAvailable {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        LText("Update")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    Text("\(emu.installedVersion) → \(emu.latestVersion)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Button {
                        isWorking = true
                        Task {
                            defer { isWorking = false }
                            try? await manager.updateEmulator(emu)
                        }
                    } label: {
                        LText("Aktualisieren")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if emu.installed {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    LText("Installiert")
                        .font(.caption)
                        .foregroundColor(.green)
                    if !emu.installedVersion.isEmpty {
                        Text(emu.installedVersion)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Button {
                    isWorking = true
                    Task {
                        defer { isWorking = false }
                        try? await manager.installEmulator(emu)
                        manager.detectInstalled()
                    }
                } label: {
                    LText("Installieren")
                }
                .buttonStyle(.borderedProminent)
            }

            Button {
                if let url = URL(string: emu.downloadPageURL) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "safari")
            }
            .buttonStyle(.plain)
            .helpLText("Download-Seite öffnen")
        }
        .padding(10)
    }
}
