import SwiftUI

struct GameDetailView: View {
    @Binding var game: Game
    let onDelete: () -> Void
    let onLaunch: () -> Void
    let onCommitPending: ((UUID, PendingGameChanges) -> Void)?
    @ObservedObject private var emu = SteamEmulatorManager.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    MediaHeaderView(game: $game)

                    if let warning = emu.applyWarning {
                        emulatorWarning(warning)
                    }

                    if game.steamEmulatorEnabled == true {
                        goldbergSection
                    }

                    GameEditorView(game: $game, onCommitPending: onCommitPending)

                    ScreenshotGalleryView(gameName: game.name)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 10)
            }

            Divider()
            BottomToolbarView(game: $game, onDelete: onDelete, onLaunch: onLaunch)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func emulatorWarning(_ warning: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(warning)
                .font(.caption)
            Spacer()
            Button {
                emu.applyWarning = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(6)
        .padding(.bottom, 4)
    }

    private var goldbergSection: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "square.and.arrow.down")
                    .foregroundColor(.accentColor)
                LText("Goldberg DLLs deployen")
                    .font(.caption)
                Spacer()
                Button {
                    Task {
                        do {
                            try await emu.deployGoldbergOnly(game: game)
                        } catch {
                            emu.applyWarning = error.localizedDescription
                        }
                    }
                } label: {
                    LText("Ausführen")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(emu.isDownloading)
            }
            HStack {
                Image(systemName: "eject")
                    .foregroundColor(.red)
                LText("Emulator entfernen")
                    .font(.caption)
                Spacer()
                Button(role: .destructive) {
                    emu.removeInjector(game: game)
                } label: {
                    LText("Entfernen")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.05))
        .cornerRadius(6)
        .padding(.bottom, 4)
    }
}

// MARK: - Media Header (isoliert — nur hier lauscht onReceive)

private struct MediaHeaderView: View {
    @Binding var game: Game
    @State private var coverImage: NSImage?
    @State private var bannerImage: NSImage?
    @State private var loadingCoverForID: UUID?
    @State private var loadingBannerForID: UUID?
    private let mediaStore = MediaStore.shared

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let img = bannerImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxHeight: 220)
                    .clipped()
                    .allowsHitTesting(false)
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxHeight: 220)

            HStack(alignment: .bottom, spacing: 16) {
                if let img = coverImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 150)
                        .cornerRadius(8)
                        .shadow(color: .black.opacity(0.3), radius: 6)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(game.name)
                        .font(.title2)
                        .bold()
                        .foregroundColor(bannerImage != nil ? .white : .primary)

                    HStack(spacing: 6) {
                        Text(game.platform)
                            .font(.subheadline)
                            .foregroundColor(bannerImage != nil ? .white.opacity(0.8) : .secondary)

                        if !game.category.isEmpty {
                            Text(game.category)
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.regularMaterial)
                                .cornerRadius(3)
                        }
                    }

                    if game.rating > 0 {
                        HStack(spacing: 1) {
                            ForEach(1...5, id: \.self) { i in
                                Image(systemName: i <= game.rating ? "star.fill" : "star")
                                    .font(.system(size: 10))
                                    .foregroundColor(.yellow)
                            }
                        }
                    }

                    if game.playTime > 0 {
                        Text(game.playTimeFormatted)
                            .font(.caption)
                            .foregroundColor(bannerImage != nil ? .white.opacity(0.7) : .secondary)
                    }
                }
            }
            .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.bottom, 4)
        .onChange(of: game.id) { _, newID in
            loadMedia(for: newID)
        }
        .onReceive(mediaStore.$changeCounter.dropFirst()) { _ in
            loadMedia(for: game.id)
        }
    }

    private func loadMedia(for newID: UUID) {
        guard !game.installPath.isEmpty else { return }
        if let cached = mediaStore.cachedImage(for: newID.uuidString, type: .cover) {
            coverImage = cached
            loadingCoverForID = nil
        } else if !game.coverURL.isEmpty {
            coverImage = nil
            loadingCoverForID = newID
            Task {
                let img = await mediaStore.loadImage(from: game.coverURL, gameID: newID.uuidString, type: .cover)
                if loadingCoverForID == newID {
                    coverImage = img
                    loadingCoverForID = nil
                }
            }
        }
        if let cached = mediaStore.cachedImage(for: newID.uuidString, type: .banner) {
            bannerImage = cached
            loadingBannerForID = nil
        } else if !game.bannerURL.isEmpty {
            bannerImage = nil
            loadingBannerForID = newID
            Task {
                let img = await mediaStore.loadImage(from: game.bannerURL, gameID: newID.uuidString, type: .banner)
                if loadingBannerForID == newID {
                    bannerImage = img
                    loadingBannerForID = nil
                }
            }
        }
    }
}

// MARK: - Bottom Toolbar (isoliert — kein Re-Render durch cover/banner)

private struct BottomToolbarView: View {
    @Binding var game: Game
    let onDelete: () -> Void
    let onLaunch: () -> Void
    private let integration = DesktopIntegrationManager.shared

    var body: some View {
        HStack(spacing: 12) {
            Button(role: .destructive, action: onDelete) {
                Label("", systemImage: "trash")
            }
            .helpLText("Spiel entfernen")
            .keyboardShortcut(Keybinds.shortcut(for: .deleteGame).key, modifiers: Keybinds.shortcut(for: .deleteGame).modifiers)

            Button {
                if integration.shortcutExists(game: game) {
                    integration.removeShortcut(game: game)
                } else {
                    _ = integration.createShortcut(game: game)
                }
            } label: {
                Label("", systemImage: integration.shortcutExists(game: game) ? "link.circle.fill" : "link")
            }
            .helpLText(integration.shortcutExists(game: game) ? "Shortcut entfernen" : "Shortcut erstellen")

            Button {
                let panel = NSSavePanel()
                panel.title = tr("Spielkonfiguration exportieren")
                panel.nameFieldStringValue = "\(game.name).lutrisgame.json"
                panel.allowedContentTypes = [.json]
                guard panel.runModal() == .OK, let url = panel.url else { return }
                if let data = try? JSONEncoder().encode(game) {
                    try? data.write(to: url, options: .atomic)
                }
            } label: {
                Label("", systemImage: "square.and.arrow.up")
            }
            .helpLText("Spielkonfiguration exportieren")

            Button {
                let panel = NSOpenPanel()
                panel.title = tr("Spielkonfiguration importieren")
                panel.allowedContentTypes = [.json]
                panel.allowsMultipleSelection = false
                guard panel.runModal() == .OK, let url = panel.url,
                      let data = try? Data(contentsOf: url),
                      let imported = try? JSONDecoder().decode(Game.self, from: data)
                else { return }
                NotificationCenter.default.post(
                    name: .importGameConfig,
                    object: imported
                )
            } label: {
                Label("", systemImage: "square.and.arrow.down")
            }
            .helpLText("Spielkonfiguration importieren")

            Spacer()

            Button(action: onLaunch) {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .helpLText("Starten")
        }
        .controlSize(.large)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
