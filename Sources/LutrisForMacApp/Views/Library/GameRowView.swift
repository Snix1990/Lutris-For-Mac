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
                HStack(spacing: 6) {
                    Text(game.platform)
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                HStack(spacing: 1) {
                    ForEach(1...5, id: \.self) { i in
                        Image(systemName: i <= game.rating ? "star.fill" : "star")
                            .font(.system(size: 8))
                            .foregroundColor(.yellow)
                    }
                }
            }
            if game.playTime > 0 {
                Text(game.playTimeFormatted)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    onLaunch?()
                }
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.accentColor, lineWidth: isSelected || isHovered ? 1.5 : 0)
        )
        .onAppear {
            coverImage = mediaStore.cachedImage(for: game.id.uuidString, type: .cover)
            if coverImage == nil && !game.coverURL.isEmpty {
                Task { coverImage = await mediaStore.loadImage(from: game.coverURL, gameID: game.id.uuidString, type: .cover) }
            }
        }
    }
}
