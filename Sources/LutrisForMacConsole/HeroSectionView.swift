import SwiftUI
import LutrisForMacCore

public struct HeroSectionView: View {
    let game: Game
    let bannerImage: NSImage?
    let focusManager: ConsoleFocusManager
    let onLaunch: ((Game) -> Void)?
    let onShowDetails: ((Game) -> Void)?

    private var heroFocused: Bool {
        focusManager.isFocused(section: .hero, index: 0)
    }

    public init(
        game: Game,
        bannerImage: NSImage? = nil,
        focusManager: ConsoleFocusManager,
        onLaunch: ((Game) -> Void)? = nil,
        onShowDetails: ((Game) -> Void)? = nil
    ) {
        self.game = game
        self.bannerImage = bannerImage
        self.focusManager = focusManager
        self.onLaunch = onLaunch
        self.onShowDetails = onShowDetails
    }

    public var body: some View {
        Group {
            if let banner = bannerImage {
                Image(nsImage: banner)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.7)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                    )
            } else {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(
                        colors: [game.coverColor, .black],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(height: 300)
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: tr("CONTINUE PLAYING"))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        Text(game.title)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(40)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(alignment: .bottomLeading) {
            HStack(alignment: .bottom, spacing: 30) {
                ConsoleCoverView(
                    game: game,
                    size: CGSize(width: 200, height: 280),
                    onTap: { onLaunch?(game) }
                )
                .focusHighlight(isFocused: heroFocused)

                VStack(alignment: .leading, spacing: 16) {
                    Text(verbatim: tr("CONTINUE PLAYING"))
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))

                    Text(game.title)
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    HStack(spacing: 20) {
                        FocusableConsoleButton(
                            title: tr("Play"),
                            icon: "play.fill",
                            color: .ps4Pink,
                            section: .hero,
                            buttonIndex: 0,
                            focusManager: focusManager,
                            action: { onLaunch?(game) },
                            showsHighlightBorder: false
                        )

                        FocusableConsoleButton(
                            title: tr("Details"),
                            icon: "info.circle.fill",
                            color: .white.opacity(0.2),
                            section: .hero,
                            buttonIndex: 1,
                            focusManager: focusManager,
                            action: { onShowDetails?(game) },
                            showsHighlightBorder: false
                        )
                    }
                }

                Spacer()
            }
            .padding(40)
        }
    }
}
