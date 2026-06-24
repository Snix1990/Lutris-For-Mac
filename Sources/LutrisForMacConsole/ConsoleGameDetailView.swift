import SwiftUI
import LutrisForMacCore

public struct ConsoleGameDetailView: View {
    let game: Game
    let onLaunch: (() -> Void)?
    let onBack: () -> Void
    let mainFocusManager: ConsoleFocusManager?

    @StateObject private var focusManager = ConsoleFocusManager()
    @State private var bannerImage: NSImage?
    @State private var loadingBannerForID: UUID?

    private let mediaStore = MediaStore.shared
    private let focusCount = 2 // 0: back, 1: launch

    public init(game: Game, onLaunch: (() -> Void)? = nil, onBack: @escaping () -> Void, mainFocusManager: ConsoleFocusManager? = nil) {
        self.game = game
        self.onLaunch = onLaunch
        self.onBack = onBack
        self.mainFocusManager = mainFocusManager
    }

    public var body: some View {
        ZStack {
            // Hintergrund: dunkler Gradient oder Banner
            if let img = bannerImage {
                Color.clear
                    .ignoresSafeArea()
                    .overlay(
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: 8)
                    )
            } else {
                LinearGradient(
                    colors: [game.coverColor, Color(white: 0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }

            // Scharfes Banner (.fit) mit weichen Kanten (Mask bezieht sich auf Image-Größe)
            if let img = bannerImage {
                VStack {
                    Spacer(minLength: 0)
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .black, location: 0.03),
                                    .init(color: .black, location: 0.97),
                                    .init(color: .clear, location: 1),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .allowsHitTesting(false)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }

            // Back button: window-top-left
            backButton
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 32)
                .padding(.leading, 40)

            // Content: fills window, scrollable
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 32) {
                    headerArea
                    descriptionArea
                    ConsoleScreenshotGalleryView(gameName: game.name)
                    Color.clear.frame(height: 100)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 100)
            .padding(.horizontal, 60)

            // Launch bar: window-bottom-center
            launchBar
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: game.id) { await loadBanner() }
        .onAppear {
            ControllerNavigationSystem.shared.setFocusManager(focusManager)
            focusManager.isLinearMode = true
            focusManager.gridColumnCount = 1
            focusManager.activeSection = .allGames
            focusManager.itemCountInSection = focusCount
            focusManager.focusedIndex = 1
        }
        .onDisappear {
            if let main = mainFocusManager {
                ControllerNavigationSystem.shared.setFocusManager(main)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .consoleConfirm)) { noti in
            guard let sectionRaw = noti.userInfo?["section"] as? Int,
                  let section = ConsoleSection(rawValue: sectionRaw),
                  section == .allGames,
                  let index = noti.userInfo?["index"] as? Int
            else { return }
            switch index {
            case 0: onBack()
            case 1: onLaunch?()
            default: break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .consoleBack)) { _ in
            onBack()
        }
        .onReceive(NotificationCenter.default.publisher(for: .consoleMenu)) { _ in
            onBack()
        }
    }

    // MARK: – Back Button

    private var backButton: some View {
        let isFocused = focusManager.isFocused(section: .allGames, index: 0)
        return Button(action: onBack) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    Text(verbatim: tr("Zurück"))
                        .font(.system(size: 18, weight: .medium))
            }
            .foregroundColor(.white.opacity(isFocused ? 1.0 : 0.7))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(isFocused ? Color.white.opacity(0.2) : Color.white.opacity(0.1))
            )
            .overlay(
                Capsule()
                    .stroke(isFocused ? Color.ps4Pink : Color.clear, lineWidth: 2)
            )
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.spring(response: 0.2), value: isFocused)
        }
        .buttonStyle(.plain)
    }

    // MARK: – Header (Cover + Title + Metadata)

    private var headerArea: some View {
        HStack(alignment: .bottom, spacing: 32) {
            ConsoleCoverView(
                game: game,
                size: CGSize(width: 180, height: 252)
            )
            .layoutPriority(1)

            VStack(alignment: .leading, spacing: 12) {
                Text(game.title)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.4)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    metadataLabel(icon: "cpu", text: game.runner)
                    if !game.platform.isEmpty {
                        metadataLabel(icon: "square.stack.3d.up", text: game.platform)
                    }
                    if !game.category.isEmpty {
                        metadataLabel(icon: "tag", text: game.category)
                    }
                }

                HStack(spacing: 16) {
                    if game.playTime > 0 {
                        Label(game.playTimeFormatted, systemImage: "clock")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.white.opacity(0.6))
                    }

                    if game.rating > 0 {
                        HStack(spacing: 2) {
                            ForEach(1...5, id: \.self) { i in
                                Image(systemName: i <= game.rating ? "star.fill" : "star")
                                    .font(.system(size: 14))
                                    .foregroundColor(.yellow)
                            }
                        }
                    }
                }

                if let last = game.lastPlayed {
                    Text(verbatim: tr("Zuletzt gespielt: ") + last.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 40)
    }

    private func metadataLabel(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(text)
                .font(.system(size: 14, weight: .medium))
        }
        .foregroundColor(.white.opacity(0.7))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.1)))
    }

    // MARK: – Description

    private var descriptionArea: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: tr("BESCHREIBUNG"))
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))

            if !game.gameDescription.isEmpty {
                Text(game.gameDescription)
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .foregroundColor(.white)
                    .lineSpacing(6)
            } else {
                Text(verbatim: tr("Keine Beschreibung verfügbar. Du kannst eine Beschreibung in den Spiele-Einstellungen hinzufügen."))
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.white.opacity(0.5))
                    .italic()
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.black.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: – Launch Bar

    private var launchBar: some View {
        let isFocused = focusManager.isFocused(section: .allGames, index: 1)
        return HStack {
            Spacer()

            Button(action: { onLaunch?() }) {
                HStack(spacing: 16) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 22))
                    Text(verbatim: tr("Spiel starten"))
                        .font(.system(size: 22, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 48)
                .padding(.vertical, 18)
                .background(Capsule().fill(Color.ps4Pink))
                .shadow(color: isFocused ? .ps4Pink.opacity(0.6) : .ps4Pink.opacity(0.4),
                        radius: isFocused ? 24 : 16)
            }
            .buttonStyle(.plain)
            .overlay(
                Capsule()
                    .stroke(isFocused ? Color.white : Color.clear, lineWidth: isFocused ? 3 : 0)
            )
            .scaleEffect(isFocused ? 1.08 : 1.0)
            .animation(.spring(response: 0.2), value: isFocused)

            Spacer()
        }
        .padding(.bottom, 48)
        .padding(.top, 16)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
            .offset(y: -20)
        )
    }

    // MARK: – Banner Loading

    private func loadBanner() async {
        let gameID = game.id.uuidString
        loadingBannerForID = game.id

        if let cached = mediaStore.cachedImage(for: gameID, type: .banner) {
            bannerImage = cached
            loadingBannerForID = nil
            return
        }

        guard !game.bannerURL.isEmpty else {
            bannerImage = nil
            loadingBannerForID = nil
            return
        }

        let img = await mediaStore.loadImage(from: game.bannerURL, gameID: gameID, type: .banner)
        if loadingBannerForID == game.id {
            bannerImage = img
            loadingBannerForID = nil
        }
    }
}
