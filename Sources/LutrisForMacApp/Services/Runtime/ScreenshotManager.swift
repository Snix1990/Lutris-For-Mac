import Cocoa
import UniformTypeIdentifiers

@MainActor
final class ScreenshotManager: ObservableObject {
    static let shared = ScreenshotManager()

    @Published var screenshotFolder: URL {
        didSet { save() }
    }

    @Published var hotkeyModifiers: NSEvent.ModifierFlags {
        didSet { save() }
    }

    @Published var hotkeyKeyCode: UInt16 {
        didSet { save() }
    }

    var hotkeyDisplayString: String {
        var parts: [String] = []
        if hotkeyModifiers.contains(.command) { parts.append("⌘") }
        if hotkeyModifiers.contains(.option) { parts.append("⌥") }
        if hotkeyModifiers.contains(.control) { parts.append("⌃") }
        if hotkeyModifiers.contains(.shift) { parts.append("⇧") }
        if let name = keyCodeName(hotkeyKeyCode) { parts.append(name) }
        return parts.isEmpty ? "—" : parts.joined()
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {
        let defaultFolder = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let modsRaw = UserDefaults.standard.integer(forKey: "screenshotHotkeyModifiers")
        let savedKeyCode = UserDefaults.standard.integer(forKey: "screenshotHotkeyKeyCode")

        if let data = UserDefaults.standard.data(forKey: "screenshotFolder"),
           let url = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSURL.self, from: data) as? URL {
            screenshotFolder = url
        } else {
            screenshotFolder = defaultFolder
        }

        var mods = NSEvent.ModifierFlags(rawValue: UInt(modsRaw))
        if mods.isEmpty { mods = [.command, .shift] }
        hotkeyModifiers = mods

        hotkeyKeyCode = savedKeyCode != 0 ? UInt16(savedKeyCode) : 1
    }



    func register() {
        unregister()
        let eventMask = (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon in
                let manager = Unmanaged<ScreenshotManager>.fromOpaque(refcon!).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func unregister() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
    }

    func captureScreenshot() {
        let gameName = GameSessionManager.shared.activeSessions.first?.gameName ?? "Allgemein"
        let gameFolder = screenshotFolder.appendingPathComponent(sanitizeFolderName(gameName))
        try? FileManager.default.createDirectory(at: gameFolder, withIntermediateDirectories: true)

        let displayID = CGMainDisplayID()
        guard let image = CGDisplayCreateImage(displayID) else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let filename = "Screenshot_\(dateFormatter.string(from: Date())).png"
        let fileURL = gameFolder.appendingPathComponent(filename)

        guard let destination = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)

        NotificationManager.info(title: "Screenshot", message: "Gespeichert: \(gameName)/\(filename)")
    }

    private func sanitizeFolderName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: "-_."))
        return name.components(separatedBy: allowed.inverted).joined()
    }

    // MARK: - Private

    private func reregister() {
        register()
    }

    private nonisolated func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        let expectedFlags: CGEventFlags = [
            .maskCommand, .maskAlternate, .maskControl, .maskShift
        ].filter { mod in
            UserDefaults.standard.integer(forKey: "screenshotHotkeyModifiers") & Int(mod.rawValue) != 0
        }.reduce(into: CGEventFlags()) { $0.insert($1) }

        let actualFlags = flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])

        let savedKeyCode = UInt16(UserDefaults.standard.integer(forKey: "screenshotHotkeyKeyCode"))

        if UInt16(keyCode) == savedKeyCode && actualFlags == expectedFlags {
            DispatchQueue.main.async {
                self.captureScreenshot()
            }
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func save() {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: screenshotFolder, requiringSecureCoding: false) {
            UserDefaults.standard.set(data, forKey: "screenshotFolder")
        }
        UserDefaults.standard.set(Int(hotkeyKeyCode), forKey: "screenshotHotkeyKeyCode")
        UserDefaults.standard.set(Int(hotkeyModifiers.rawValue), forKey: "screenshotHotkeyModifiers")
    }

    private func keyCodeName(_ code: UInt16) -> String? {
        switch Int(code) {
        case 0: return "A"; case 1: return "S"; case 2: return "D"; case 3: return "F"
        case 4: return "H"; case 5: return "G"; case 6: return "Z"; case 7: return "X"
        case 8: return "C"; case 9: return "V"; case 11: return "B"; case 12: return "Q"
        case 13: return "W"; case 14: return "E"; case 15: return "R"; case 16: return "Y"
        case 17: return "T"; case 18: return "1"; case 19: return "2"; case 20: return "3"
        case 21: return "4"; case 22: return "6"; case 23: return "5"; case 24: return "="
        case 25: return "9"; case 26: return "7"; case 27: return "-"; case 28: return "8"
        case 29: return "0"; case 30: return "]"; case 31: return "O"; case 32: return "U"
        case 33: return "["; case 34: return "I"; case 35: return "P"; case 36: return "Return"
        case 37: return "L"; case 38: return "J"; case 39: return "'"; case 40: return "K"
        case 41: return ";"; case 42: return "\\"; case 43: return ","; case 44: return "/"
        case 45: return "N"; case 46: return "M"; case 47: return "."; case 48: return "Tab"
        case 49: return "Space"; case 50: return "`"; case 51: return "Delete"
        case 53: return "Esc"; case 122: return "F1"; case 120: return "F2"
        case 99: return "F3"; case 118: return "F4"; case 96: return "F5"
        case 97: return "F6"; case 98: return "F7"; case 100: return "F8"
        case 101: return "F9"; case 109: return "F10"; case 103: return "F11"
        case 111: return "F12"; default: return nil
        }
    }
}
