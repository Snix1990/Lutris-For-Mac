import SwiftUI
import LutrisForMacCore

struct ConsoleScreenshotGalleryView: View {
    let gameName: String

    @State private var screenshots: [URL] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: tr("SCREENSHOTS"))
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))

            if screenshots.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.2))
                        Text(verbatim: tr("Noch keine Screenshots"))
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .padding(.vertical, 24)
                    Spacer()
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(screenshots.enumerated()), id: \.offset) { _, url in
                            screenshotThumbnail(url: url)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.black.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            loadScreenshots()
        }
    }

    private func screenshotThumbnail(url: URL) -> some View {
        let img = (try? Data(contentsOf: url)).flatMap { NSImage(data: $0) } ?? NSImage()
        return Image(nsImage: img)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 200, height: 120)
            .clipped()
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 4)
            .onTapGesture {
                showLightbox(imageURL: url)
            }
    }

    private func loadScreenshots() {
        let folder = ScreenshotManager.shared.screenshotFolder
            .appendingPathComponent(sanitizeFolderName(gameName))
        guard FileManager.default.fileExists(atPath: folder.path),
              let enumerator = FileManager.default.enumerator(
                  at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
                  options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]
              ) else { return }

        var results: [(url: URL, date: Date)] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "png" {
            if let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
               let date = attrs.contentModificationDate {
                results.append((url, date))
            }
        }
        results.sort { $0.date > $1.date }
        screenshots = results.map(\.url)
    }

    private func sanitizeFolderName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: "-_."))
        return name.components(separatedBy: allowed.inverted).joined()
    }

    // MARK: - Lightbox

    private static var lightboxWindow: NSWindow?

    private func showLightbox(imageURL: URL) {
        let image = NSImage(contentsOf: imageURL)
        let screenSize = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
        let maxW = screenSize.width * 0.5
        let maxH = screenSize.height * 0.5
        let displayW = image.map { min(maxW, $0.size.width) } ?? maxW
        let displayH = image.map { min(maxH, $0.size.height) } ?? maxH

        let window: NSWindow
        if let w = Self.lightboxWindow {
            window = w
            window.contentView = nil
        } else {
            window = NSWindow(
                contentRect: NSScreen.main?.frame ?? .zero,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .screenSaver
            window.ignoresMouseEvents = false
            window.isReleasedWhenClosed = false
            Self.lightboxWindow = window
        }

        window.title = imageURL.lastPathComponent
        window.identifier = NSUserInterfaceItemIdentifier(imageURL.path)

        let weakWindow = window
        let hostView = NSHostingView(rootView: LightboxView(
            displaySize: CGSize(width: displayW, height: displayH),
            imageURL: imageURL,
            onClose: { weakWindow.orderOut(nil) }
        ))
        hostView.frame = NSScreen.main?.frame ?? .zero
        hostView.autoresizingMask = [NSView.AutoresizingMask.width, NSView.AutoresizingMask.height]

        window.contentView = hostView
        window.makeKeyAndOrderFront(nil)
    }
}

private struct LightboxView: View {
    let displaySize: CGSize
    let imageURL: URL
    let onClose: () -> Void

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: displaySize.width, height: displaySize.height)
                    .shadow(color: .black.opacity(0.5), radius: 20)
            }

            VStack {
                HStack {
                    Text(imageURL.lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .shadow(radius: 2)
                        .padding(.leading, 20)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.white.opacity(0.9))
                            .shadow(color: .black, radius: 6)
                    }
                    .buttonStyle(.plain)
                    .padding(20)
                }
                Spacer()
            }
        }
        .onAppear {
            if let data = try? Data(contentsOf: imageURL) {
                image = NSImage(data: data)
            }
        }
    }
}
