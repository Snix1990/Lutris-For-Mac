import SwiftUI

struct ScreenshotGalleryView: View {
    let gameName: String

    @State private var screenshots: [URL] = []
    @State private var selectedURL: URL?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                LText("Screenshots").font(.headline)

                if screenshots.isEmpty {
                    LText("Noch keine Screenshots").font(.caption).foregroundColor(.secondary)
                } else {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 100, maximum: 200), spacing: 6)
                    ], spacing: 6) {
                        ForEach(0..<screenshots.count, id: \.self) { i in
                            let url = screenshots[i]
                            let img = (try? Data(contentsOf: url)).flatMap { NSImage(data: $0) } ?? NSImage()
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: 110)
                                .clipped()
                                .cornerRadius(4)
                                .shadow(color: .black.opacity(0.12), radius: 2)
                                .onTapGesture {
                                    selectedURL = screenshots[i]
                                    showLightbox(imageURL: screenshots[i])
                                }
                                .contextMenu {
                                    Button {
                                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                                    } label: {
                                        LText("Im Finder zeigen")
                                    }
                                }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            loadScreenshots()
        }
    }

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
        hostView.autoresizingMask = [.width, .height]

        window.contentView = hostView
        window.makeKeyAndOrderFront(nil)
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
}

struct LightboxView: View {
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


