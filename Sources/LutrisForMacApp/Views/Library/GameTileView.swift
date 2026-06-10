import SwiftUI

struct GameTileView: View {
    let game: Game
    let isSelected: Bool
    let onLaunch: (() -> Void)?
    private let mediaStore = MediaStore.shared
    @State private var coverImage: NSImage?
    @State private var isHovered = false

    init(game: Game, isSelected: Bool = false, onLaunch: (() -> Void)? = nil) {
        self.game = game
        self.isSelected = isSelected
        self.onLaunch = onLaunch
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                if let img = coverImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 140 * 6 / 9, height: 140)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.08))
                        .frame(width: 140 * 6 / 9, height: 140)
                        .overlay(
                            Image(systemName: "sparkles")
                                .font(.system(size: 28))
                                .foregroundColor(.accentColor)
                        )
                }

                if game.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                        .padding(4)
                }
            }
            .frame(width: 140 * 6 / 9)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .center, spacing: 2) {
                Text(game.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(game.platform)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .padding(0)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentColor, lineWidth: isSelected || isHovered ? 2 : 0)
        )
        .onHover { isHovered = $0 }
        .onAppear {
            loadCover()
        }
    }

    private func loadCover() {
        guard coverImage == nil else { return }
        coverImage = mediaStore.cachedImage(for: game.id.uuidString, type: .cover)
        if coverImage == nil, !game.coverURL.isEmpty {
            Task {
                let img = await mediaStore.loadImage(from: game.coverURL, gameID: game.id.uuidString, type: .cover)
                if img != nil { coverImage = img }
            }
        }
    }
}
