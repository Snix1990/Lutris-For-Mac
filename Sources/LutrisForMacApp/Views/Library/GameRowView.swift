import SwiftUI

struct GameRowView: View {
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
        HStack(spacing: 10) {
            if let img = coverImage {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 60)
                    .cornerRadius(4)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.08))
                    .frame(width: 40, height: 60)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(game.name)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    Text(game.platform)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    if !game.category.isEmpty {
                        Text(game.category)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }
            Spacer()
            if game.rating > 0 {
                ratingBadge
            }
            if game.playTime > 0 {
                Text(game.playTimeFormatted)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.accentColor, lineWidth: isSelected || isHovered ? 1.5 : 0)
        )
        .onHover { isHovered = $0 }
        .onAppear {
            loadCover()
        }
    }

    private var ratingBadge: some View {
        HStack(spacing: 1) {
            Image(systemName: "star.fill")
                .font(.system(size: 8))
                .foregroundColor(.yellow)
            Text("\(game.rating)")
                .font(.caption2)
                .foregroundColor(.secondary)
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
