import SwiftUI
import LutrisForMacCore

public struct RecentSectionView: View {
    let games: [Game]
    let cardWidth: CGFloat
    let focusManager: ConsoleFocusManager
    let onShowDetails: ((Game) -> Void)?

    public init(
        games: [Game],
        cardWidth: CGFloat,
        focusManager: ConsoleFocusManager,
        onShowDetails: ((Game) -> Void)? = nil
    ) {
        self.games = games
        self.cardWidth = cardWidth
        self.focusManager = focusManager
        self.onShowDetails = onShowDetails
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: tr("RECENT"))
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(Array(games.enumerated()), id: \.element.id) { idx, game in
                        FocusableGameCard(
                            game: game,
                            section: .recent,
                            index: idx,
                            focusManager: focusManager,
                            onShowDetails: onShowDetails,
                            coverWidth: cardWidth - 8
                        )
                        .frame(width: cardWidth)
                    }
                }
            }
        }
    }
}
