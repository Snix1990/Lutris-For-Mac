import Foundation
import SwiftUI
import Carbon
import MachO

enum OSDPosition: String, Codable, CaseIterable, Sendable {
    case topLeft = "Oben Links"
    case topRight = "Oben Rechts"
    case bottomLeft = "Unten Links"
    case bottomRight = "Unten Rechts"

    var displayName: String { rawValue }
}

struct OSDSettings: Codable, Equatable {
    var enabled: Bool = false
    var position: OSDPosition = .topRight
    var attachToWindow: Bool = true
    var showFPS: Bool = true
    var showRAM: Bool = true
    var showCPU: Bool = true
    var showGPU: Bool = true
    var showFrameTimes: Bool = true
    var showMediaPlayer: Bool = true
    var showLogging: Bool = true
    var opacity: Double = 0.6
    var fontSize: Double = 13
    var verticalOffset: Double = 0
    var isLocked: Bool = false
}

@MainActor
final class OSDManager: ObservableObject {
    static let shared = OSDManager()

    @Published var settings: OSDSettings {
        didSet { save() }
    }

    @Published var isVisible = false
    @Published var isShowingSettings = false

    // Live data
    @Published var fps: Double = 60
    @Published var ramUsage: Double = 0
    @Published var cpuUsage: Double = 0
    @Published var frameTime: Double = 16
    @Published var mediaTitle: String = ""
    @Published var loggingActive = false

    // Runtime idle tracking
    var lastInteraction = Date.distantFuture

    func touch() {
        lastInteraction = Date()
        isIdleCheckNeeded = true
    }

    var isIdleCheckNeeded = false

    private var overlayPanel: NSPanel?
    private var lockPanel: NSPanel?
    private var mediaPanel: NSPanel?
    private var positionTimer: Timer?
    private var dataTimer: Timer?

    // CPU delta tracking
    private var previousCPUTicks: (system: UInt64, user: UInt64, idle: UInt64)?

    private let defaultsKey = "osdSettings"

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(OSDSettings.self, from: data) {
            settings = decoded
        } else {
            settings = OSDSettings()
        }
    }

    func toggle() {
        touch()
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        touch()
        guard overlayPanel == nil else {
            overlayPanel?.orderFront(nil)
            isVisible = true
            startDataTimer()
            return
        }

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .hudWindow, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = settings.isLocked

        let hosting = NSHostingView(rootView: OSDOverlayView())
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)

        positionPanel(panel)
        panel.orderFront(nil)
        overlayPanel = panel
        isVisible = true
        startDataTimer()

        if settings.isLocked {
            showButtonPanels()
        }

        startPositionTimer()
    }

    func hide() {
        stopPositionTimer()
        stopDataTimer()
        hideButtonPanels()
        overlayPanel?.orderOut(nil)
        overlayPanel = nil
        isVisible = false
    }

    func toggleLock() {
        settings.isLocked.toggle()
        overlayPanel?.ignoresMouseEvents = settings.isLocked
        if settings.isLocked {
            showButtonPanels()
        } else {
            hideButtonPanels()
        }
    }

    private func showButtonPanels() {
        showLockPanel()
        showMediaPanel()
    }

    private func hideButtonPanels() {
        lockPanel?.orderOut(nil)
        lockPanel = nil
        mediaPanel?.orderOut(nil)
        mediaPanel = nil
    }

    private func makeButtonPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .hudWindow, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating + 1
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        return panel
    }

    private func showLockPanel() {
        guard let overlay = overlayPanel else { return }
        lockPanel?.orderOut(nil)

        let panel = makeButtonPanel()
        let hosting = NSHostingView(rootView: LockButtonView())
        hosting.layout()
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)

        // Positioniere über dem Lock-Button (oben rechts)
        let ox = overlay.frame.maxX - hosting.fittingSize.width - 7
        let oy = overlay.frame.maxY - hosting.fittingSize.height - 5
        panel.setFrameOrigin(NSPoint(x: ox, y: oy))
        panel.orderFront(nil)
        lockPanel = panel
    }

    private func showMediaPanel() {
        guard overlayPanel != nil else { return }
        mediaPanel?.orderOut(nil)

        let panel = makeButtonPanel()
        let hosting = NSHostingView(rootView: MediaButtonsView())
        hosting.layout()
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)

        if let overlay = overlayPanel {
            // Media-Buttons sind im unteren VStack: padding(.vertical, 6), spacing 2
            // Von unten: 6px padding + (loggingRow? rowH+spacing : 0) + mediaRow/2
            let rowH = CGFloat(settings.fontSize) + 4
            let spacing: CGFloat = 2
            var fromBottom: CGFloat = 6 // bottom padding
            if settings.showLogging {
                fromBottom += rowH + spacing
            }
            fromBottom += rowH / 2 - 1 // center of media row, 1px tiefer
            let oy = overlay.frame.minY + fromBottom - hosting.fittingSize.height / 2
            // Der OSD-mediaRow hat hinten noch Text "—", der die Buttons nach links drückt.
            // MediaButtonsView hat nur die Buttons → muss weiter links stehen.
            let textWidth: CGFloat = 11 // "—" ≈ 8px + spacing 4px
            let ox = overlay.frame.maxX - hosting.fittingSize.width - 8 - textWidth
            panel.setFrameOrigin(NSPoint(x: ox, y: oy))
        }
        panel.orderFront(nil)
        mediaPanel = panel
    }

    /// Zeigt das OSD, aktiviert die App und gibt den Mauszeiger frei,
    /// damit der Nutzer mit dem OSD interagieren kann (Media, Settings).
    func requestInteraction() {
        show()
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSCursor.unhide()
    }

    func updatePosition() {
        guard let panel = overlayPanel else { return }
        positionPanel(panel)
        repositionButtonPanels()
    }

    func resizeToFit() {
        guard let panel = overlayPanel,
              let hosting = panel.contentView as? NSHostingView<OSDOverlayView> else { return }
        hosting.layout()
        panel.setContentSize(hosting.fittingSize)
        positionPanel(panel)
        repositionButtonPanels()
    }

    private func repositionButtonPanels() {
        guard let overlay = overlayPanel else { return }
        if let lp = lockPanel {
            let ox = overlay.frame.maxX - lp.frame.width - 7
            let oy = overlay.frame.maxY - lp.frame.height - 5
            lp.setFrameOrigin(NSPoint(x: ox, y: oy))
        }
        if let mp = mediaPanel {
            let rowH = CGFloat(settings.fontSize) + 4
            let spacing: CGFloat = 2
            var fromBottom: CGFloat = 6
            if settings.showLogging {
                fromBottom += rowH + spacing
            }
            fromBottom += rowH / 2 - 1
            let oy = overlay.frame.minY + fromBottom - mp.frame.height / 2
            let textWidth: CGFloat = 11
            let ox = overlay.frame.maxX - mp.frame.width - 8 - textWidth
            mp.setFrameOrigin(NSPoint(x: ox, y: oy))
        }
    }

    func resizeForSettings() {
        guard let panel = overlayPanel else { return }
        // Panel muss Key-Window werden können für Texteingabe
        panel.styleMask.remove(.nonactivatingPanel)
        panel.styleMask.insert(.titled)
        panel.setContentSize(NSSize(width: 320, height: 420))
        positionPanel(panel)
        panel.makeKey()
    }

    func exitSettingsMode() {
        guard let panel = overlayPanel else { return }
        panel.styleMask.insert(.nonactivatingPanel)
        panel.styleMask.remove(.titled)
        panel.setContentSize(NSSize(width: 320, height: 80))
        resizeToFit()
    }

    // MARK: - Media Commands

    enum MediaCommand: Int {
        case play       = 0
        case pause      = 1
        case togglePlayPause = 2
        case nextTrack  = 4
        case previousTrack = 5
    }

    func sendMediaCommand(_ cmd: MediaCommand) {
        let keyCode: UInt32
        switch cmd {
        case .play, .togglePlayPause: keyCode = 16  // NX_KEYTYPE_PLAY
        case .nextTrack:              keyCode = 17  // NX_KEYTYPE_NEXT
        case .previousTrack:          keyCode = 18  // NX_KEYTYPE_PREVIOUS
        case .pause:                  keyCode = 16
        }

        // 1) HID system event (funktioniert meist ohne Accessibility)
        let downData = Int((keyCode << 16) | 0x0a00)
        if let down = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                         modifierFlags: [], timestamp: 0,
                                         windowNumber: 0, context: nil, subtype: 8,
                                         data1: downData, data2: -1) {
            down.cgEvent?.post(tap: .cgAnnotatedSessionEventTap)
        }
        let upData = Int((keyCode << 16) | 0x0b00)
        if let up = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                       modifierFlags: [], timestamp: 0,
                                       windowNumber: 0, context: nil, subtype: 8,
                                       data1: upData, data2: -1) {
            up.cgEvent?.post(tap: .cgAnnotatedSessionEventTap)
        }

        // 2) Fallback: MediaRemote private framework
        mediaRemoteSendCommand(cmd.rawValue)
    }

    // MARK: - Global Hotkey

    private var hotKeyRef: EventHotKeyRef?

    func registerGlobalHotkey() {
        unregisterGlobalHotkey()

        let shortcut = Keybinds.shortcut(for: .toggleOSD)
        guard let keyCode = carbonKeyCode(from: shortcut.key) else { return }
        let modifiers = carbonModifiers(from: shortcut.modifiers)

        var id = EventHotKeyID()
        id.signature = OSType("Lutr".utf8.reduce(0) { ($0 << 8) | OSType($1) })
        id.id = 1

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), modifiers, id, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else {
            print("OSD: global hotkey registration failed (\(status))")
            return
        }
        hotKeyRef = ref
        print("OSD: global hotkey registered")
    }

    func unregisterGlobalHotkey() {
        guard let ref = hotKeyRef else { return }
        UnregisterEventHotKey(ref)
        hotKeyRef = nil
    }

    static func installCarbonHandler() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), hotkeyCallback, 1, &eventType, nil, &eventHandlerRef)
    }

    // MARK: - Data sampling

    func sampleAll() {
        let pm = PerformanceMonitor.shared
        fps = pm.fps
        frameTime = pm.frameTime
        ramUsage = sampleRAM()
        cpuUsage = sampleCPU()
        mediaTitle = nowPlayingTitle()
    }

    private func startDataTimer() {
        stopDataTimer()
        dataTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isShowingSettings else { return }
                self.sampleAll()
            }
        }
        sampleAll() // initial sample
    }

    private func stopDataTimer() {
        dataTimer?.invalidate()
        dataTimer = nil
    }

    private func sampleRAM() -> Double {
        let host = mach_host_self()
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vmStat = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &vmStat) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let pageSize = UInt64(vm_kernel_page_size)
        let total = ProcessInfo.processInfo.physicalMemory
        let used = UInt64(vmStat.active_count + vmStat.wire_count + vmStat.compressor_page_count) * pageSize
        guard total > 0 else { return 0 }
        return Double(used) / Double(total) * 100
    }

    private func sampleCPU() -> Double {
        var cpuInfo: processor_info_array_t?
        var cpuMsgCount: mach_msg_type_number_t = 0
        var cpuCount: natural_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &cpuInfo, &cpuMsgCount)
        guard result == KERN_SUCCESS, let info = cpuInfo else { return 0 }

        let count = Int(cpuCount)
        var system: UInt64 = 0, user: UInt64 = 0, idle: UInt64 = 0
        let stateCount = Int(CPU_STATE_MAX)
        for i in 0..<count {
            let offset = stateCount * i
            system += UInt64(info[offset + Int(CPU_STATE_SYSTEM)])
            user   += UInt64(info[offset + Int(CPU_STATE_USER)])
            idle   += UInt64(info[offset + Int(CPU_STATE_IDLE)])
        }

        defer {
            let size = vm_size_t(cpuMsgCount) * vm_size_t(MemoryLayout<natural_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }

        guard let prev = previousCPUTicks else {
            previousCPUTicks = (system, user, idle)
            return 0
        }

        let dSystem = system - prev.system
        let dUser   = user   - prev.user
        let dIdle   = idle   - prev.idle
        let total   = dSystem + dUser + dIdle

        previousCPUTicks = (system, user, idle)
        guard total > 0 else { return 0 }
        return Double(dUser + dSystem) / Double(total) * 100
    }

    private func nowPlayingTitle() -> String {
        mediaRemoteGetNowPlayingInfo()
    }

    // MARK: - Position

    private func positionPanel(_ panel: NSPanel) {
        let panelSize = panel.frame.size

        let windowFrame = frontmostWindowFrame()
        let targetFrame: CGRect
        if settings.attachToWindow, let wf = windowFrame {
            targetFrame = wf
        } else if let screen = NSScreen.main {
            targetFrame = screen.visibleFrame
        } else {
            return
        }

        let origin: NSPoint
        let voff = CGFloat(settings.verticalOffset)
        if settings.attachToWindow, let wf = windowFrame {
            let margin: CGFloat = 10
            switch settings.position {
            case .topLeft:
                origin = NSPoint(x: wf.minX + margin, y: wf.maxY - panelSize.height - margin + voff)
            case .topRight:
                origin = NSPoint(x: wf.maxX - panelSize.width - margin, y: wf.maxY - panelSize.height - margin + voff)
            case .bottomLeft:
                origin = NSPoint(x: wf.minX + margin, y: wf.minY + margin + voff)
            case .bottomRight:
                origin = NSPoint(x: wf.maxX - panelSize.width - margin, y: wf.minY + margin + voff)
            }
        } else {
            let margin: CGFloat = 12
            switch settings.position {
            case .topLeft:
                origin = NSPoint(x: targetFrame.minX + margin, y: targetFrame.maxY - panelSize.height - margin + voff)
            case .topRight:
                origin = NSPoint(x: targetFrame.maxX - panelSize.width - margin, y: targetFrame.maxY - panelSize.height - margin + voff)
            case .bottomLeft:
                origin = NSPoint(x: targetFrame.minX + margin, y: targetFrame.minY + margin + voff)
            case .bottomRight:
                origin = NSPoint(x: targetFrame.maxX - panelSize.width - margin, y: targetFrame.minY + margin + voff)
            }
        }
        panel.setFrameOrigin(origin)

        let msg = "[OSD] origin=\(NSStringFromPoint(origin)) target=\(NSStringFromRect(targetFrame)) voff=\(settings.verticalOffset)\n"
        if let handle = FileHandle(forWritingAtPath: "/tmp/osd_debug.log") {
            handle.seekToEndOfFile()
            handle.write(msg.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? msg.write(toFile: "/tmp/osd_debug.log", atomically: true, encoding: .utf8)
        }
    }

    private func frontmostWindowFrame() -> CGRect? {
        // 1) PerformanceMonitor's sticky Game-Fenster (PID-locked, wechselt nicht bei Focus)
        if let frame = PerformanceMonitor.shared.gameWindowFrame { return frame }

        // 2) Fallback: GameSessionManager
        let gamePIDs = GameSessionManager.shared.activeGamePIDs
        guard !gamePIDs.isEmpty else { return nil }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in infoList {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  gamePIDs.contains(pid),
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"], let y = boundsDict["Y"],
                  let w = boundsDict["Width"], let h = boundsDict["Height"],
                  w > 0, h > 0 else { continue }
            return CGRect(x: x, y: y, width: w, height: h)
        }
        return nil
    }

    private func startPositionTimer() {
        stopPositionTimer()
        guard settings.attachToWindow else { return }
        positionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePosition()
            }
        }
    }

    private func stopPositionTimer() {
        positionTimer?.invalidate()
        positionTimer = nil
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

// MARK: - MediaRemote (private framework)

private let mediaRemoteHandle: UnsafeMutableRawPointer? = {
    dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)
}()

private typealias MRMediaRemoteGetNowPlayingInfoFunc = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
private typealias MRMediaRemoteSendCommandFunc = @convention(c) (Int, [AnyHashable: Any]?) -> Bool

private let _MRMediaRemoteGetNowPlayingInfo: MRMediaRemoteGetNowPlayingInfoFunc? = {
    guard let handle = mediaRemoteHandle,
          let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") else { return nil }
    return unsafeBitCast(sym, to: MRMediaRemoteGetNowPlayingInfoFunc.self)
}()

private let _MRMediaRemoteSendCommand: MRMediaRemoteSendCommandFunc? = {
    guard let handle = mediaRemoteHandle,
          let sym = dlsym(handle, "MRMediaRemoteSendCommand") else { return nil }
    return unsafeBitCast(sym, to: MRMediaRemoteSendCommandFunc.self)
}()

private func mediaRemoteGetNowPlayingInfo() -> String {
    guard let fn = _MRMediaRemoteGetNowPlayingInfo else { return "" }
    var result = ""
    let sem = DispatchSemaphore(value: 0)
    fn(.main) { info in
        if let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String {
            let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
            if artist.isEmpty {
                result = title
            } else {
                result = "\(artist) — \(title)"
            }
        }
        sem.signal()
    }
    _ = sem.wait(timeout: .now() + 0.5)
    return result
}

private func mediaRemoteSendCommand(_ command: Int) {
    guard let fn = _MRMediaRemoteSendCommand else { return }
    _ = fn(command, nil)
}

// MARK: - Carbon helpers

private func carbonKeyCode(from key: KeyEquivalent) -> UInt16? {
    let ch = key.character.lowercased()
    let map: [String: UInt16] = [
        "a": 0x00, "b": 0x0B, "c": 0x08, "d": 0x02, "e": 0x0E,
        "f": 0x03, "g": 0x05, "h": 0x04, "i": 0x22, "j": 0x26,
        "k": 0x28, "l": 0x25, "m": 0x2E, "n": 0x2D, "o": 0x1F,
        "p": 0x23, "q": 0x0C, "r": 0x0F, "s": 0x01, "t": 0x11,
        "u": 0x20, "v": 0x09, "w": 0x0D, "x": 0x07, "y": 0x10,
        "z": 0x06,
        "0": 0x1D, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15,
        "5": 0x17, "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19,
        " ": 0x31, ".": 0x2F, ",": 0x2B, "/": 0x2C, ";": 0x29,
        "'": 0x27, "[": 0x21, "]": 0x1E, "\\": 0x2A, "-": 0x1B,
        "=": 0x18, "`": 0x32,
    ]
    if ch == "\u{7f}" { return 0x33 } // delete
    return map[ch]
}

private func carbonModifiers(from modifiers: SwiftUI.EventModifiers) -> UInt32 {
    var result: UInt32 = 0
    if modifiers.contains(SwiftUI.EventModifiers.command) { result |= UInt32(cmdKey) }
    if modifiers.contains(SwiftUI.EventModifiers.shift)   { result |= UInt32(shiftKey) }
    if modifiers.contains(SwiftUI.EventModifiers.option)  { result |= UInt32(optionKey) }
    if modifiers.contains(SwiftUI.EventModifiers.control) { result |= UInt32(controlKey) }
    return result
}

// MARK: - Carbon hotkey callback

private let hotkeyCallback: EventHandlerUPP = { _, event, _ in
    var id = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &id
    )
    if status == noErr {
        DispatchQueue.main.async {
            OSDManager.shared.toggle()
        }
    }
    return noErr
}

private var eventHandlerRef: EventHandlerRef?
