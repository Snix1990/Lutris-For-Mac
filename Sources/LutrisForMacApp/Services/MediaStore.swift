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
                let dest = path(for: gameID, type: type, ext: "jpg")
                try? FileManager.default.copyItem(at: oldURL, to: dest)
                try? FileManager.default.removeItem(at: oldURL)
                caches[type]?.setObject(img, forKey: gameID as NSString, cost: cost(img))
                setIndexEntry(gameID: gameID, type: type, ext: "jpg")
                return img
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
            try data.write(to: path(for: gameID, type: type, ext: ext))
            caches[type]?.setObject(image, forKey: gameID as NSString, cost: data.count)
            setIndexEntry(gameID: gameID, type: type, ext: ext)
            changeCounter += 1
            return image
        } catch {
            return nil
        }
    }

    func setLocalImage(at sourceURL: URL, gameID: String, type: MediaType) -> NSImage? {
        guard let image = NSImage(contentsOf: sourceURL) else { return nil }
        let ext = sourceURL.pathExtension.isEmpty ? "jpg" : sourceURL.pathExtension
        let dest = path(for: gameID, type: type, ext: ext)
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: sourceURL, to: dest)
        let cost = image.representations.first.map { $0.pixelsWide * $0.pixelsHigh * 4 } ?? 0
        caches[type]?.setObject(image, forKey: gameID as NSString, cost: cost)
        setIndexEntry(gameID: gameID, type: type, ext: ext)
        changeCounter += 1
        return image
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
