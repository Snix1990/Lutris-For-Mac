import SwiftUI
import LutrisForMacCore

public struct FocusableGameCard: View {
    let game: Game
    let section: ConsoleSection
    let index: Int
    let coverWidth: CGFloat
    @ObservedObject var focusManager: ConsoleFocusManager
    let onShowDetails: ((Game) -> Void)?

    @State private var isHovered = false

    private var isFocused: Bool {
        focusManager.isFocused(section: section, index: index)
    }

    public init(
        game: Game,
        section: ConsoleSection,
        index: Int,
        focusManager: ConsoleFocusManager,
        onShowDetails: ((Game) -> Void)? = nil,
        coverWidth: CGFloat = 200
    ) {
        self.game = game
        self.section = section
        self.index = index
        self.focusManager = focusManager
        self.onShowDetails = onShowDetails
        self.coverWidth = coverWidth
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ConsoleCoverView(
                game: game,
                size: CGSize(width: coverWidth, height: coverWidth * 1.4),
                onTap: { onShowDetails?(game) }
            )
            .focusHighlight(isFocused: isFocused, isHovered: isHovered)

            Text(game.title)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if game.playTime > 0 {
                Text(game.playTimeFormatted)
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.leading, 8)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
