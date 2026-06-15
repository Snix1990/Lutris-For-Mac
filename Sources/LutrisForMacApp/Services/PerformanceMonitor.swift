import Foundation
import CoreVideo
import CoreGraphics
import AppKit
import IOKit
import ScreenCaptureKit

@MainActor
final class PerformanceMonitor: ObservableObject {
    static let shared = PerformanceMonitor()

    @Published private(set) var fps: Double = 60
    @Published private(set) var frameTime: Double = 16
    @Published private(set) var gpuUsage: Double = 0

    /// Fenster-Frame des Games für OSD-Position (NUR GameSession + sticky PID, kein frontmostApp).
    @Published private(set) var gameWindowFrame: CGRect?

    /// Fenster für FPS-Messung (darf frontmostApp fallback haben).
    private var fpsWindowID: CGWindowID?

    // Display-linked frame tracking (accurate for fullscreen games)
    private var displayLink: CVDisplayLink?
    private var lastFrameTime = CACurrentMediaTime()
    private var frameCount: UInt = 0
    private var fpsAccumulator: Double = 0
    private let fpsWindow: Double = 1.0

    // Window content change detection (for windowed games)
    private var lastRowPixels: [UInt8]?
    private var windowChangeCount: UInt = 0
    private var windowAccumulator: Double = 0
    private var windowFPS: Double = 0
    private var contentSampler: Timer?

    // GPU usage sampling
    private var gpuTimer: Timer?

    // Sticky PID — einmal an ein Game geheftet, bleibt es dort
    private var trackedGamePID: Int32?
    private var trackedGameWindowID: CGWindowID?

    private init() {
        startDisplayLink()
        startContentSampler()
        startGPUSampling()
    }

    // MARK: - CVDisplayLink (fullscreen / display-level fps)

    private func startDisplayLink() {
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let displayLink else { return }
        CVDisplayLinkSetOutputHandler(displayLink) { [weak self] _, _, _, _, _ in
            self?.nonisolatedFrameCallback()
            return kCVReturnSuccess
        }
        CVDisplayLinkStart(displayLink)
    }

    private func frameCallback() {
        frameCount += 1
        fpsAccumulator += CACurrentMediaTime() - lastFrameTime
        lastFrameTime = CACurrentMediaTime()

        if fpsAccumulator >= fpsWindow {
            let avgFrameTime = fpsAccumulator / Double(frameCount)
            let displayFPS = avgFrameTime > 0 ? 1.0 / avgFrameTime : 60

            Task { @MainActor in
                let effective = windowFPS > 0 && windowFPS < displayFPS * 0.8
                    ? windowFPS : displayFPS
                self.fps = effective
                self.frameTime = effective > 0 ? 1000.0 / effective : 16
            }

            frameCount = 0
            fpsAccumulator = 0
        }
    }

    nonisolated private func nonisolatedFrameCallback() {
        Task { @MainActor in
            self.frameCallback()
        }
    }

    // MARK: - Window content change detection (for windowed games)

    private func startContentSampler() {
        contentSampler = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sampleWindowContent()
            }
        }
    }

    /// Findet Fenster-Frame für OSD-Position (sticky PID → GameSession → sticky frontmostApp → nil).
    /// Sobald ein PID gemerkt wurde, springt es nicht mehr bei Focus-Wechsel.
    private func resolveOSDWindowFrame() -> CGRect? {
        // 1) Sticky PID prüfen (bleibt bis Prozess stirbt)
        if let pid = trackedGamePID {
            if kill(pid, 0) == 0, let result = findWindow(forPID: pid) {
                trackedGameWindowID = result.windowID
                return result.frame
            }
            trackedGamePID = nil
            trackedGameWindowID = nil
        }

        // 2) GameSessionManager-PIDs
        for pid in GameSessionManager.shared.activeGamePIDs {
            if let result = findWindow(forPID: pid) {
                trackedGamePID = pid
                trackedGameWindowID = result.windowID
                return result.frame
            }
        }

        // 3) FrontmostApp — sticky merken, wechselt nicht bei Focus
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.bundleIdentifier != Bundle.main.bundleIdentifier,
              let result = findWindow(forApp: frontApp)
        else { return nil }

        trackedGamePID = frontApp.processIdentifier
        trackedGameWindowID = result.windowID
        return result.frame
    }

    /// Findet Fenster für FPS-Content-Sampling (sticky PID → GameSession → frontmostApp).
    private func resolveFPSWindow() -> CGWindowID? {
        if let pid = trackedGamePID, kill(pid, 0) == 0,
           let result = findWindow(forPID: pid) {
            return result.windowID
        }
        for pid in GameSessionManager.shared.activeGamePIDs {
            if let result = findWindow(forPID: pid) {
                return result.windowID
            }
        }
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.bundleIdentifier != Bundle.main.bundleIdentifier,
              let result = findWindow(forApp: frontApp)
        else { return nil }
        return result.windowID
    }

    private func findWindow(forPID pid: Int32) -> (windowID: CGWindowID, frame: CGRect)? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }

        var best: (windowID: CGWindowID, frame: CGRect, area: CGFloat)?

        for info in windows {
            guard let infoPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  infoPID == pid,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let w = bounds["Width"], let h = bounds["Height"],
                  w >= 200, h >= 200,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID
            else { continue }

            let area = w * h
            if let b = best, area <= b.area { continue }
            best = (windowID, CGRect(x: x, y: y, width: w, height: h), area)
        }

        return best.map { ($0.windowID, $0.frame) }
    }

    private func findWindow(forApp app: NSRunningApplication) -> (windowID: CGWindowID, frame: CGRect)? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in windows {
            guard let owner = info[kCGWindowOwnerName as String] as? String,
                  owner == app.localizedName,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  bounds["Width"] ?? 0 >= 200, bounds["Height"] ?? 0 >= 200,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID
            else { continue }
            if let x = bounds["X"], let y = bounds["Y"],
               let w = bounds["Width"], let h = bounds["Height"] {
                return (windowID, CGRect(x: x, y: y, width: w, height: h))
            }
        }
        return nil
    }

    private func sampleWindowContent() {
        gameWindowFrame = resolveOSDWindowFrame()
        guard let windowID = resolveFPSWindow() else { windowFPS = 0; return }
        Task { await sampleWindowPixels(windowID: windowID) }
    }

    private func sampleWindowPixels(windowID: CGWindowID) async {
        guard let row = await captureWindowRow(windowID: windowID) else {
            await MainActor.run { windowFPS = 0 }
            return
        }
        let count = row.count
        if let last = lastRowPixels, last.count == count {
            var changed = false
            for i in 0..<count {
                if abs(Int(row[i]) - Int(last[i])) > 20 { changed = true; break }
            }
            if changed { windowChangeCount += 1 }
        }
        lastRowPixels = row
        windowAccumulator += 0.1
        if windowAccumulator >= 1.0 {
            await MainActor.run {
                windowFPS = Double(windowChangeCount)
                windowChangeCount = 0
                windowAccumulator = 0
            }
        }
    }

    private func captureWindowRow(windowID: CGWindowID) async -> [UInt8]? {
        do {
            let content = try await SCShareableContent.current
            guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else { return nil }
            let bw = scWindow.frame.width
            let bh = scWindow.frame.height
            let rect = CGRect(x: 0, y: bh * 0.5, width: min(bw, 8), height: 1)
            let display = content.displays.first!
            let filter = SCContentFilter(display: display, including: [scWindow])
            let config = SCStreamConfiguration()
            config.width = Int(rect.width)
            config.height = Int(rect.height)
            config.capturesAudio = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            guard let provider = image.dataProvider,
                  let data = provider.data,
                  let pixels = CFDataGetBytePtr(data) else { return nil }
            let count = Int(rect.width) * 4
            var row = [UInt8](repeating: 0, count: count)
            for i in 0..<count { row[i] = pixels[i] }
            return row
        } catch {
            return nil
        }
    }

    // MARK: - GPU usage via IOKit

    private func startGPUSampling() {
        gpuTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.gpuUsage = self?.sampleGPUUsage() ?? 0
            }
        }
    }

    private func sampleGPUUsage() -> Double {
        var iterator = io_iterator_t()
        let matching = IOServiceMatching("AGXAccelerator")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else { return 0 }
        defer { IOObjectRelease(iterator) }

        var total: Double = 0
        var count = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let props = IORegistryEntryCreateCFProperty(
                service, "PerformanceStatistics" as CFString,
                kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [String: Any] {
                if let util = props["Device Utilization %"] as? Double {
                    total += util
                    count += 1
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return count > 0 ? total / Double(count) : 0
    }
}
