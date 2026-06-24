import SwiftUI
import LutrisForMacCore

public struct ConsoleCoverView: View {
    let game: Game
    let size: CGSize
    let onTap: (() -> Void)?

    @State private var coverImage: NSImage?
    @State private var isLoading = false
    private let mediaStore = MediaStore.shared

    public init(game: Game, size: CGSize, onTap: (() -> Void)? = nil) {
        self.game = game
        self.size = size
        self.onTap = onTap
    }

    public var body: some View {
        Group {
            if let img = coverImage {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else if isLoading {
                ZStack {
                    LinearGradient(
                        colors: [game.coverColor, .black.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    ProgressView()
                        .scaleEffect(0.8)
                        .foregroundColor(.white.opacity(0.5))
                }
            } else {
                LinearGradient(
                    colors: [game.coverColor, .black.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: size.width * 0.3))
                        .foregroundColor(.white.opacity(0.3))
                )
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { onTap?() }
        .task(id: game.id) {
            guard coverImage == nil, !isLoading else { return }
            coverImage = mediaStore.cachedImage(for: game.id.uuidString, type: .cover)
            if coverImage == nil, !game.coverURL.isEmpty {
                isLoading = true
                let img = await mediaStore.loadImage(from: game.coverURL, gameID: game.id.uuidString, type: .cover)
                isLoading = false
                if img != nil { coverImage = img }
            }
        }
    }
}
