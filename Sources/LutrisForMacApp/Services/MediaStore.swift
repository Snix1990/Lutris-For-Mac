import SwiftUI

enum MediaType: String, CaseIterable, Codable {
    case cover
    case banner
    case icon
}

private let knownExts = ["jpg", "jpeg", "png", "ico", "gif", "bmp", "tiff", "webp"]

@MainActor
final class MediaStore: ObservableObject {
    static let shared = MediaStore()

    @Published public private(set) var changeCounter = 0

    private let mediaDir: URL
    private let oldCoverDir: URL
    private let indexURL: URL
    private var caches: [MediaType: NSCache<NSString, NSImage>] = [:]
    private var index: [String: [MediaType: String]] = [:]

    private init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = folder.appendingPathComponent("LutrisForMac", isDirectory: true)
        mediaDir = appFolder.appendingPathComponent("media", isDirectory: true)
        oldCoverDir = appFolder.appendingPathComponent("covers", isDirectory: true)
        indexURL = mediaDir.appendingPathComponent("media_index.json")
        try? FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)

        for type in MediaType.allCases {
            let c = NSCache<NSString, NSImage>()
            c.countLimit = 200
            c.totalCostLimit = 100 * 1024 * 1024
            caches[type] = c
        }

        loadIndex()
    }

    // MARK: - Paths

    private func path(for gameID: String, type: MediaType, ext: String) -> URL {
        mediaDir.appendingPathComponent("\(gameID)_\(type.rawValue).\(ext)")
    }

    private func oldCoverPath(for gameID: String) -> URL {
        oldCoverDir.appendingPathComponent("\(gameID).jpg")
    }

    // MARK: - Index

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL) else { return }

        if let dict = try? JSONDecoder().decode([String: [String: String]].self, from: data) {
            var result: [String: [MediaType: String]] = [:]
            for (gid, typeMap) in dict {
                var inner: [MediaType: String] = [:]
                for (rawType, ext) in typeMap {
                    if let t = MediaType(rawValue: rawType) { inner[t] = ext }
                }
                if !inner.isEmpty { result[gid] = inner }
            }
            index = result
            return
        }

        if let dict = try? JSONDecoder().decode([String: [String]].self, from: data) {
            var result: [String: [MediaType: String]] = [:]
            for (gid, types) in dict {
                var inner: [MediaType: String] = [:]
                for rawType in types {
                    if let t = MediaType(rawValue: rawType) { inner[t] = "jpg" }
                }
                if !inner.isEmpty { result[gid] = inner }
            }
            index = result
        }
    }

    private func saveIndex() {
        let dict = index.mapValues { $0.mapValues { $0 } }
        let data = try? JSONEncoder().encode(dict)
        guard let data else { return }
        // Debounce: nur alle 500ms auf Platte schreiben
        saveIndexWorkItem?.cancel()
        saveIndexWorkItem = DispatchWorkItem { [indexURL] in
            try? data.write(to: indexURL)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: saveIndexWorkItem!)
    }

    private var saveIndexWorkItem: DispatchWorkItem?

    private func setIndexEntry(gameID: String, type: MediaType, ext: String) {
        index[gameID, default: [:]][type] = ext
        saveIndex()
    }

    private func removeIndexEntry(gameID: String, type: MediaType) {
        index[gameID]?.removeValue(forKey: type)
        if index[gameID]?.isEmpty == true { index.removeValue(forKey: gameID) }
        saveIndex()
    }

    func hasMedia(gameID: String, type: MediaType) -> Bool {
        index[gameID]?[type] != nil
    }

    func mediaExtension(gameID: String, type: MediaType) -> String? {
        index[gameID]?[type]
    }

    // MARK: - Downsampling

    private func downsample(_ image: NSImage, type: MediaType) -> NSImage {
        let maxSize: CGSize
        switch type {
        case .cover:  maxSize = CGSize(width: 300, height: 450)
        case .banner: maxSize = CGSize(width: 1000, height: 400)
        case .icon:   maxSize = CGSize(width: 128, height: 128)
        }
        guard let rep = image.representations.first else { return image }
        let w = CGFloat(rep.pixelsWide)
        let h = CGFloat(rep.pixelsHigh)
        guard w > maxSize.width || h > maxSize.height else { return image }

        let scale = min(maxSize.width / w, maxSize.height / h, 1)
        let newW = Int(w * scale)
        let newH = Int(h * scale)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        guard let ctx = CGContext(data: nil, width: newW, height: newH, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        guard let resultCG = ctx.makeImage() else { return image }
        return NSImage(cgImage: resultCG, size: NSSize(width: newW, height: newH))
    }

    private func storeResized(_ image: NSImage, gameID: String, type: MediaType, ext: String) {
        let resized = downsample(image, type: type)
        let dest = path(for: gameID, type: type, ext: ext)
        if let tiffData = resized.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
            try? jpeg.write(to: dest, options: .atomic)
        }
        let cost = (resized.representations.first?.pixelsWide ?? 0) * (resized.representations.first?.pixelsHigh ?? 0) * 4
        caches[type]?.setObject(resized, forKey: gameID as NSString, cost: cost)
        setIndexEntry(gameID: gameID, type: type, ext: "jpg")
        changeCounter += 1
    }

    // MARK: - Cache

    func cachedImage(for gameID: String, type: MediaType) -> NSImage? {
        if let img = caches[type]?.object(forKey: gameID as NSString) { return img }

        func cost(_ img: NSImage) -> Int {
            guard let rep = img.representations.first else { return 0 }
            return rep.pixelsWide * rep.pixelsHigh * 4
        }

        if let ext = index[gameID]?[type],
           let img = NSImage(contentsOf: path(for: gameID, type: type, ext: ext)) {
            caches[type]?.setObject(img, forKey: gameID as NSString, cost: cost(img))
            return img
        }

        for ext in knownExts {
            let url = path(for: gameID, type: type, ext: ext)
            if let img = NSImage(contentsOf: url) {
                caches[type]?.setObject(img, forKey: gameID as NSString, cost: cost(img))
                setIndexEntry(gameID: gameID, type: type, ext: ext)
                return img
            }
        }

        if type == .cover {
            let oldURL = oldCoverPath(for: gameID)
            if let img = NSImage(contentsOf: oldURL) {
                let resized = downsample(img, type: .cover)
                storeResized(resized, gameID: gameID, type: .cover, ext: "jpg")
                try? FileManager.default.removeItem(at: oldURL)
                return resized
            }
        }

        return nil
    }

    func loadImage(from urlString: String, gameID: String, type: MediaType) async -> NSImage? {
        if let cached = cachedImage(for: gameID, type: type) { return cached }
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = NSImage(data: data) else { return nil }
            let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
            storeResized(image, gameID: gameID, type: type, ext: ext)
            return downsample(image, type: type)
        } catch {
            return nil
        }
    }

    func setLocalImage(at sourceURL: URL, gameID: String, type: MediaType) -> NSImage? {
        guard let image = NSImage(contentsOf: sourceURL) else { return nil }
        let ext = sourceURL.pathExtension.isEmpty ? "jpg" : sourceURL.pathExtension
        storeResized(image, gameID: gameID, type: type, ext: ext)
        return downsample(image, type: type)
    }

    func removeMedia(for gameID: String, type: MediaType) {
        caches[type]?.removeObject(forKey: gameID as NSString)
        if let ext = index[gameID]?[type] {
            try? FileManager.default.removeItem(at: path(for: gameID, type: type, ext: ext))
        } else {
            for ext in knownExts {
                try? FileManager.default.removeItem(at: path(for: gameID, type: type, ext: ext))
            }
        }
        removeIndexEntry(gameID: gameID, type: type)
        changeCounter += 1
    }

    func removeAllMedia(for gameID: String) {
        for type in MediaType.allCases {
            removeMedia(for: gameID, type: type)
        }
    }
}
