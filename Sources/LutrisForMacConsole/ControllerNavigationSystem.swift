import Foundation
import GameController

// MARK: - Button Actions

private struct ButtonAction {
    let id: String
    let action: @MainActor (ConsoleFocusManager) -> Void
}

// MARK: - ControllerNavigationSystem

@MainActor
public final class ControllerNavigationSystem {
    public static let shared = ControllerNavigationSystem()

    private weak var focusManager: ConsoleFocusManager?
    public var isActivated: Bool { focusManager != nil }
    public var wiredControllerCount: Int = 0


    private var pollTimer: Timer?
    private var prevState: [String: Bool] = [:]
    private let buttonActions: [String: @MainActor (ConsoleFocusManager) -> Void] = [
        "buttonA":            { $0.confirm() },
        "buttonB":            { $0.back() },
        "buttonX":            { $0.back() },
        "buttonY":            { $0.confirm() },
        "leftShoulder":       { $0.navTabLeft() },
        "rightShoulder":      { $0.navTabRight() },
        "buttonMenu":         { $0.menu() },
        "buttonOptions":      { $0.toggleSearch() },
        "leftTrigger":        { $0.moveLeft() },
        "rightTrigger":       { $0.moveRight() },
        "leftThumbStickUp":   { $0.moveUp() },
        "leftThumbStickDown": { $0.moveDown() },
        "leftThumbStickLeft": { $0.moveLeft() },
        "leftThumbStickRight":{ $0.moveRight() },
        "dpadUp":             { $0.cycleContentSectionUp() },
        "dpadDown":           { $0.cycleContentSectionDown() },
        "dpadLeft":           { $0.moveLeft() },
        "dpadRight":          { $0.moveRight() },
        "leftThumbstickButton": { $0.confirm() },
        "rightThumbstickButton":{ $0.back() },
    ]

    private init() {}

    public func activate(focusManager: ConsoleFocusManager) {
        self.focusManager = focusManager
        wiredControllerCount = GCController.controllers().count
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

        for controller in GCController.controllers() {
            guard let gp = controller.extendedGamepad else { continue }

            pollButton(gp.buttonA,        id: "buttonA")
            pollButton(gp.buttonB,        id: "buttonB")
            pollButton(gp.buttonX,        id: "buttonX")
            pollButton(gp.buttonY,        id: "buttonY")
            pollButton(gp.leftShoulder,   id: "leftShoulder")
            pollButton(gp.rightShoulder,  id: "rightShoulder")
            pollButton(gp.leftTrigger,    id: "leftTrigger")
            pollButton(gp.rightTrigger,   id: "rightTrigger")
            pollButton(gp.buttonMenu,     id: "buttonMenu")
            if let opt = gp.buttonOptions { pollButton(opt, id: "buttonOptions") }
            pollDpad(gp.dpad)
            pollThumbstick(gp.leftThumbstick, "leftThumbStick")
            if let btn = gp.leftThumbstickButton { pollButton(btn, id: "leftThumbstickButton") }
            if let btn = gp.rightThumbstickButton { pollButton(btn, id: "rightThumbstickButton") }
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

    private func pollButton(_ btn: GCControllerButtonInput, id: String) {
        let pressed = btn.isPressed
        let justPressed = pressed && prevState[id] == false
        prevState[id] = pressed
        guard justPressed, let fm = focusManager else { return }
        if let action = buttonActions[id] {
            action(fm)
        }
    }

    private func pollDpad(_ dpad: GCControllerDirectionPad) {
        // D-Pad: only report when fully pressed (value == 1.0)
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

        if up && !prevUp    { if let a = buttonActions["dpadUp"]    { a(fm) } }
        if down && !prevDown  { if let a = buttonActions["dpadDown"]  { a(fm) } }
        if left && !prevLeft  { if let a = buttonActions["dpadLeft"]  { a(fm) } }
        if right && !prevRight { if let a = buttonActions["dpadRight"] { a(fm) } }
    }

    private func pollThumbstick(_ stick: GCControllerDirectionPad, _ prefix: String) {
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

        if up && !prevUp             { if let a = buttonActions["\(prefix)Up"]    { a(fm) } }
        else if down && !prevDown    { if let a = buttonActions["\(prefix)Down"]  { a(fm) } }
        else if left && !prevLeft    { if let a = buttonActions["\(prefix)Left"]  { a(fm) } }
        else if right && !prevRight  { if let a = buttonActions["\(prefix)Right"] { a(fm) } }
    }
}
