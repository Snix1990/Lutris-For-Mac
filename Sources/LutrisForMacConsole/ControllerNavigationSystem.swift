import Foundation
import GameController
import Combine
import LutrisForMacCore

// MARK: - ControllerNavigationSystem

@MainActor
public final class ControllerNavigationSystem {
    public static let shared = ControllerNavigationSystem()

    private weak var focusManager: ConsoleFocusManager?
    public var isActivated: Bool { focusManager != nil }
    public var wiredControllerCount: Int = 0

    private var pollTimer: Timer?
    /// prevState verwendet PhysicalButton.rawValue als Keys
    private var prevState: [String: Bool] = [:]

    private let layoutService = UIControllerLayoutService.shared

    // ── Gecachte Action-Map (wird nur bei actionMapVersion-Änderung neu gebaut) ──
    private var cachedClosureMap: [PhysicalButton: @MainActor (ConsoleFocusManager) -> Void] = [:]
    private var cachedLayoutVersion: UInt64 = 0

    // ── Combine-Cancellable für Layout-Änderungen ──
    private var layoutObserver: AnyCancellable?

    private init() {}

    // MARK: - Lifecycle

    public func activate(focusManager: ConsoleFocusManager) {
        self.focusManager = focusManager
        wiredControllerCount = GCController.controllers().count
        layoutService.refreshDetectedLayouts()
        rebuildCache()
        startPolling()

        // Auf Layout-Änderungen lauschen → Cache bei Bedarf invalidieren
        layoutObserver = layoutService.$actionMapVersion
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.rebuildCache()
                }
            }
    }

    public func deactivate() {
        layoutObserver?.cancel()
        layoutObserver = nil
        stopPolling()
        prevState.removeAll()
        cachedClosureMap.removeAll()
        focusManager = nil
    }

    public func setFocusManager(_ fm: ConsoleFocusManager) {
        focusManager = fm
        rebuildCache()
    }

    // MARK: - Cache

    private func rebuildCache() {
        let layout: UIControllerLayout
        if let firstCtrl = GCController.controllers().first {
            layout = layoutService.detectLayout(for: firstCtrl)
        } else {
            layout = .generic
        }
        cachedClosureMap = Self.buildClosureMap(layout: layout, layoutService: layoutService)
        cachedLayoutVersion = layoutService.actionMapVersion
    }

    private static func buildClosureMap(layout: UIControllerLayout, layoutService: UIControllerLayoutService) -> [PhysicalButton: @MainActor (ConsoleFocusManager) -> Void] {
        let actionMap = layoutService.effectiveActionMapWithConvenience(for: layout)
        var map: [PhysicalButton: @MainActor (ConsoleFocusManager) -> Void] = [:]
        for (physical, action) in actionMap {
            map[physical] = Self.closure(for: action)
        }
        return map
    }

    private static func closure(for action: UIAction) -> @MainActor (ConsoleFocusManager) -> Void {
        switch action {
        case .confirm:               return { $0.confirm() }
        case .back:                  return { $0.back() }
        case .toggleSearch:          return { $0.toggleSearch() }
        case .menu:                  return { $0.menu() }
        case .navTabLeft:            return { $0.navTabLeft() }
        case .navTabRight:           return { $0.navTabRight() }
        case .moveUp:                return { $0.moveUp() }
        case .moveDown:              return { $0.moveDown() }
        case .moveLeft:              return { $0.moveLeft() }
        case .moveRight:             return { $0.moveRight() }
        case .cycleContentSectionUp:   return { $0.cycleContentSectionUp() }
        case .cycleContentSectionDown: return { $0.cycleContentSectionDown() }
        }
    }

    // MARK: - Polling

    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.pollTick()
        }
        RunLoop.main.add(pollTimer!, forMode: .common)
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func pollTick() {
        guard focusManager != nil else { return }

        // Cache bei Bedarf aktualisieren (selten, da actionMapVersion nur bei User-Aktion steigt)
        if cachedLayoutVersion != layoutService.actionMapVersion {
            rebuildCache()
        }

        let map = cachedClosureMap

        for controller in GCController.controllers() {
            guard let gp = controller.extendedGamepad else { continue }

            pollButton(gp.buttonA,        .buttonA, map)
            pollButton(gp.buttonB,        .buttonB, map)
            pollButton(gp.buttonX,        .buttonX, map)
            pollButton(gp.buttonY,        .buttonY, map)
            pollButton(gp.leftShoulder,   .leftShoulder, map)
            pollButton(gp.rightShoulder,  .rightShoulder, map)
            pollButton(gp.leftTrigger,    .leftTrigger, map)
            pollButton(gp.rightTrigger,   .rightTrigger, map)
            pollButton(gp.buttonMenu,     .buttonMenu, map)
            if let opt = gp.buttonOptions { pollButton(opt, .buttonOptions, map) }
            pollDpad(gp.dpad, map)
            pollThumbstick(gp.leftThumbstick, .leftThumbStickUp, map)
            if let btn = gp.leftThumbstickButton { pollButton(btn, .leftThumbstickButton, map) }
            if let btn = gp.rightThumbstickButton { pollButton(btn, .rightThumbstickButton, map) }
        }

        // Scroll via right thumbstick
        if let gp = GCController.controllers().compactMap({ $0.extendedGamepad }).first {
            let x = gp.rightThumbstick.xAxis.value
            let y = gp.rightThumbstick.yAxis.value
            let deadzone: Float = 0.3
            if abs(x) > deadzone || abs(y) > deadzone {
                NotificationCenter.default.post(
                    name: .consoleScroll,
                    object: nil,
                    userInfo: ["dx": CGFloat(x), "dy": CGFloat(y)]
                )
            }
        }
    }

    // MARK: - Poll Helpers (type-safe)

    private func pollButton(_ btn: GCControllerButtonInput, _ physical: PhysicalButton, _ map: [PhysicalButton: @MainActor (ConsoleFocusManager) -> Void]) {
        let key = physical.rawValue
        let pressed = btn.isPressed
        let justPressed = pressed && prevState[key] == false
        prevState[key] = pressed
        guard justPressed, let fm = focusManager, let action = map[physical] else { return }
        action(fm)
    }

    private func pollDpad(_ dpad: GCControllerDirectionPad, _ map: [PhysicalButton: @MainActor (ConsoleFocusManager) -> Void]) {
        func axisPressed(_ val: Float) -> Bool { val > 0.9 }

        typealias P = PhysicalButton
        let dirs: [(P, Float, String)] = [
            (.dpadUp,    dpad.up.value,    "dpadUp"),
            (.dpadDown,  dpad.down.value,  "dpadDown"),
            (.dpadLeft,  dpad.left.value,  "dpadLeft"),
            (.dpadRight, dpad.right.value, "dpadRight"),
        ]

        guard let fm = focusManager else { return }

        for (physical, value, key) in dirs {
            let pressed = axisPressed(value)
            let justPressed = pressed && prevState[key] == false
            prevState[key] = pressed
            if justPressed, let action = map[physical] {
                action(fm)
            }
        }
    }

    private func pollThumbstick(_ stick: GCControllerDirectionPad, _: PhysicalButton, _ map: [PhysicalButton: @MainActor (ConsoleFocusManager) -> Void]) {
        let deadzone: Float = 0.5
        let x = stick.xAxis.value
        let y = stick.yAxis.value

        typealias P = PhysicalButton
        let dirs: [(P, Bool, String)] = [
            (.leftThumbStickUp,    y > deadzone,  P.leftThumbStickUp.rawValue),
            (.leftThumbStickDown,  y < -deadzone, P.leftThumbStickDown.rawValue),
            (.leftThumbStickLeft,  x < -deadzone, P.leftThumbStickLeft.rawValue),
            (.leftThumbStickRight, x > deadzone,  P.leftThumbStickRight.rawValue),
        ]

        guard let fm = focusManager else { return }

        for (physical, pressed, key) in dirs {
            let justPressed = pressed && prevState[key] == false
            prevState[key] = pressed
            if justPressed, let action = map[physical] {
                action(fm)
            }
        }
    }
}

// MARK: - Identifiable

extension PhysicalButton: Identifiable {
    public var id: String { rawValue }
}
