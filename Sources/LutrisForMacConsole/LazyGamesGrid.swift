import SwiftUI
import LutrisForMacCore

/// Ein lazy-paginierter Grid für Spiele.
/// Rendert nur ein Fenster von `pageSize`-Items und lädt bei Bedarf weitere.
/// Kompatibel mit `ScrollViewReader`/`proxy.scrollTo`.
public struct LazyGamesGrid: View {
    let games: [Game]
    let columns: Int
    let cardWidth: CGFloat
    let section: ConsoleSection
    @ObservedObject var focusManager: ConsoleFocusManager
    let onShowDetails: ((Game) -> Void)?
    let focusedIndex: Int

    private static let pageSize = 50

    @State private var loadedCount: Int = LazyGamesGrid.pageSize

    public init(
        games: [Game],
        columns: Int,
        cardWidth: CGFloat,
        section: ConsoleSection = .allGames,
        focusManager: ConsoleFocusManager,
        onShowDetails: ((Game) -> Void)?,
        focusedIndex: Int = 0
    ) {
        self.games = games
        self.columns = columns
        self.cardWidth = cardWidth
        self.section = section
        self.focusManager = focusManager
        self.onShowDetails = onShowDetails
        self.focusedIndex = focusedIndex
    }

    public var body: some View {
        let visibleGames = games.prefix(loadedCount)

        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(cardWidth), spacing: 20), count: columns),
            spacing: 20
        ) {
            ForEach(Array(visibleGames.enumerated()), id: \.element.id) { idx, game in
                FocusableGameCard(
                    game: game,
                    section: section,
                    index: idx,
                    focusManager: focusManager,
                    onShowDetails: onShowDetails,
                    coverWidth: cardWidth - 8
                )
                .id(game.id)
                .onAppear {
                    if idx >= loadedCount - Self.pageSize / 2 {
                        loadMore()
                    }
                }
            }

            if loadedCount < games.count {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 24, height: 24)
                    Spacer()
                }
                .padding(.vertical, 20)
                .id("loading_indicator")
                .onAppear {
                    loadMore()
                }
            }
        }
        .onChange(of: games.count) { _, _ in
            reset()
        }
        .onChange(of: focusedIndex) { _, newIndex in
            if newIndex >= loadedCount {
                loadUpTo(index: newIndex)
            }
        }
    }

    private func loadMore() {
        guard loadedCount < games.count else { return }
        loadedCount = min(games.count, loadedCount + Self.pageSize)
    }

    private func loadUpTo(index: Int) {
        guard index < games.count else { return }
        loadedCount = min(games.count, index + Self.pageSize)
    }

    public func reset() {
        loadedCount = Self.pageSize
    }
}
