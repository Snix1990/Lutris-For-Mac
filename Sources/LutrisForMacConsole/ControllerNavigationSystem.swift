import Foundation
import GameController
import LutrisForMacCore

// MARK: - ControllerNavigationSystem

@MainActor
public final class ControllerNavigationSystem {
    public static let shared = ControllerNavigationSystem()

    private weak var focusManager: ConsoleFocusManager?
    public var isActivated: Bool { focusManager != nil }
    public var wiredControllerCount: Int = 0

    private var pollTimer: Timer?
    private var prevState: [String: Bool] = [:]

    /// The layout service for UI navigation mapping.
    private let layoutService = UIControllerLayoutService.shared

    private init() {}

    /// Build the button → action map dynamically based on detected controller layout.
    private func buildActionMap() -> [String: @MainActor (ConsoleFocusManager) -> Void] {
        var map: [String: @MainActor (ConsoleFocusManager) -> Void] = [:]

        // We may have multiple controllers; collect all action maps.
        // Use the first connected controller's layout.
        let layout: UIControllerLayout
        if let firstCtrl = GCController.controllers().first {
            layout = layoutService.detectLayout(for: firstCtrl)
        } else {
            layout = .generic
        }

        // Get effective action map (layout defaults + custom overrides)
        let effectiveMap = layoutService.effectiveActionMap(for: layout)

        // Map each physical button ID to the corresponding closure
        for (physicalID, action) in effectiveMap {
            map[physicalID] = closure(for: action)
        }

        // Also keep thumbstick directionals from layout
        // (they are already in effectiveMap)
        // Ensure leftThumbstickButton and rightThumbstickButton have sensible defaults
        if effectiveMap["leftThumbstickButton"] == nil {
            map["leftThumbstickButton"] = { $0.confirm() }
        }
        if effectiveMap["rightThumbstickButton"] == nil {
            map["rightThumbstickButton"] = { $0.back() }
        }

        // Also map leftTrigger/rightTrigger to moveLeft/moveRight for convenience
        if map["leftTrigger"] == nil {
            map["leftTrigger"] = { $0.moveLeft() }
        }
        if map["rightTrigger"] == nil {
            map["rightTrigger"] = { $0.moveRight() }
        }

        return map
    }

    private func closure(for action: UIAction) -> @MainActor (ConsoleFocusManager) -> Void {
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

    public func activate(focusManager: ConsoleFocusManager) {
        self.focusManager = focusManager
        wiredControllerCount = GCController.controllers().count
        layoutService.refreshDetectedLayouts()
        startPolling()
    }

    public func deactivate() {
        stopPolling()
        prevState.removeAll()
        focusManager = nil
    }

    public func setFocusManager(_ fm: ConsoleFocusManager) {
        focusManager = fm
    }

    // MARK: - Polling

    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(pollTimer!, forMode: .common)
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func poll() {
        guard focusManager != nil else { return }

        let actionMap = buildActionMap()

        for controller in GCController.controllers() {
            guard let gp = controller.extendedGamepad else { continue }

            pollButton(gp.buttonA,        id: "buttonA", actionMap: actionMap)
            pollButton(gp.buttonB,        id: "buttonB", actionMap: actionMap)
            pollButton(gp.buttonX,        id: "buttonX", actionMap: actionMap)
            pollButton(gp.buttonY,        id: "buttonY", actionMap: actionMap)
            pollButton(gp.leftShoulder,   id: "leftShoulder", actionMap: actionMap)
            pollButton(gp.rightShoulder,  id: "rightShoulder", actionMap: actionMap)
            pollButton(gp.leftTrigger,    id: "leftTrigger", actionMap: actionMap)
            pollButton(gp.rightTrigger,   id: "rightTrigger", actionMap: actionMap)
            pollButton(gp.buttonMenu,     id: "buttonMenu", actionMap: actionMap)
            if let opt = gp.buttonOptions { pollButton(opt, id: "buttonOptions", actionMap: actionMap) }
            pollDpad(gp.dpad, actionMap: actionMap)
            pollThumbstick(gp.leftThumbstick, "leftThumbStick", actionMap: actionMap)
            if let btn = gp.leftThumbstickButton { pollButton(btn, id: "leftThumbstickButton", actionMap: actionMap) }
            if let btn = gp.rightThumbstickButton { pollButton(btn, id: "rightThumbstickButton", actionMap: actionMap) }
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

    private func pollButton(_ btn: GCControllerButtonInput, id: String, actionMap: [String: @MainActor (ConsoleFocusManager) -> Void]) {
        let pressed = btn.isPressed
        let justPressed = pressed && prevState[id] == false
        prevState[id] = pressed
        guard justPressed, let fm = focusManager else { return }
        if let action = actionMap[id] {
            action(fm)
        }
    }

    private func pollDpad(_ dpad: GCControllerDirectionPad, actionMap: [String: @MainActor (ConsoleFocusManager) -> Void]) {
        func axisPressed(_ val: Float) -> Bool { val > 0.9 }

        let up    = axisPressed(dpad.up.value)
        let down  = axisPressed(dpad.down.value)
        let left  = axisPressed(dpad.left.value)
        let right = axisPressed(dpad.right.value)

        let prevUp    = prevState["dpadUp"] ?? false
        let prevDown  = prevState["dpadDown"] ?? false
        let prevLeft  = prevState["dpadLeft"] ?? false
        let prevRight = prevState["dpadRight"] ?? false

        prevState["dpadUp"]    = up
        prevState["dpadDown"]  = down
        prevState["dpadLeft"]  = left
        prevState["dpadRight"] = right

        guard let fm = focusManager else { return }

        if up && !prevUp    { if let a = actionMap["dpadUp"]    { a(fm) } }
        if down && !prevDown  { if let a = actionMap["dpadDown"]  { a(fm) } }
        if left && !prevLeft  { if let a = actionMap["dpadLeft"]  { a(fm) } }
        if right && !prevRight { if let a = actionMap["dpadRight"] { a(fm) } }
    }

    private func pollThumbstick(_ stick: GCControllerDirectionPad, _ prefix: String, actionMap: [String: @MainActor (ConsoleFocusManager) -> Void]) {
        let deadzone: Float = 0.5
        let x = stick.xAxis.value
        let y = stick.yAxis.value

        let left  = x < -deadzone
        let right = x > deadzone
        let up    = y > deadzone
        let down  = y < -deadzone

        let prevLeft  = prevState["\(prefix)Left"] ?? false
        let prevRight = prevState["\(prefix)Right"] ?? false
        let prevUp    = prevState["\(prefix)Up"] ?? false
        let prevDown  = prevState["\(prefix)Down"] ?? false

        prevState["\(prefix)Left"]  = left
        prevState["\(prefix)Right"] = right
        prevState["\(prefix)Up"]    = up
        prevState["\(prefix)Down"]  = down

        guard let fm = focusManager else { return }

        if up && !prevUp             { if let a = actionMap["\(prefix)Up"]    { a(fm) } }
        else if down && !prevDown    { if let a = actionMap["\(prefix)Down"]  { a(fm) } }
        else if left && !prevLeft    { if let a = actionMap["\(prefix)Left"]  { a(fm) } }
        else if right && !prevRight  { if let a = actionMap["\(prefix)Right"] { a(fm) } }
    }
}
