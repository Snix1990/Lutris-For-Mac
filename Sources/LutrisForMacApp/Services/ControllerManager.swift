import Foundation
import GameController
import AppKit

@MainActor
final class ControllerManager: ObservableObject {
    static let shared = ControllerManager()

    @Published var connectedControllers: [ControllerInfo] = []
    @Published var lastActivity: String = ""

    private var observationTokens: [NSObjectProtocol] = []
    private var batteryPollTimer: Timer?
    private var lowBatteryNotifiedIDs: Set<String> = []
    private var remappingHandlers: [String: Any] = [:]

    struct ControllerInfo: Identifiable {
        let id = UUID()
        let uniqueID: String
        let vendorName: String
        let category: ControllerCategory
        let productCategory: String
        var batteryLevel: Float?
        var batteryState: BatteryState
        var isConnected: Bool

        enum ControllerCategory: String {
            case extended = "Extended Gamepad"
            case micro = "Micro Gamepad"
            case standard = "Standard"
            case unknown = "Unbekannt"
        }

        enum BatteryState: String {
            case unknown = "Unbekannt"
            case charging = "Lädt"
            case discharging = "Entlädt"
            case full = "Voll"
        }
    }

    private init() {
        startObserving()
        scanControllers()
        startBatteryPolling()

        // Re-apply remappings when RemappingManager changes
        observationTokens.append(
            NotificationCenter.default.addObserver(
                forName: .remappingChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshRemappings()
                }
            }
        )
    }

    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        batteryPollTimer?.invalidate()
    }

    func refresh() {
        scanControllers()
    }

    // MARK: - Observing

    private func startObserving() {
        let center = NotificationCenter.default
        observationTokens.append(
            center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
                Task { @MainActor [weak self] in
                    self?.scanControllers()
                    self?.lastActivity = "Controller verbunden"
                    if let ctrl = note.object as? GCController {
                        self?.applyRemappings(for: ctrl)
                    }
                }
            }
        )
        observationTokens.append(
            center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.scanControllers()
                    self?.lastActivity = "Controller getrennt"
                }
            }
        )
    }

    // MARK: - Battery Polling

    private func startBatteryPolling() {
        batteryPollTimer?.invalidate()
        batteryPollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollBatteryLevels()
            }
        }
    }

    private func pollBatteryLevels() {
        for controller in GCController.controllers() {
            updateBattery(for: controller)
            checkLowBattery(controller)
        }
    }

    private func checkLowBattery(_ controller: GCController) {
        guard let battery = controller.battery,
              battery.batteryState != .charging,
              battery.batteryState != .full,
              battery.batteryLevel < 0.2 else {
            if let id = controller.vendorName {
                lowBatteryNotifiedIDs.remove(id)
            }
            return
        }

        let name = controller.vendorName ?? "Controller"
        guard !lowBatteryNotifiedIDs.contains(name) else { return }
        lowBatteryNotifiedIDs.insert(name)

        NotificationManager.warning(
            title: "\(name) – Akku schwach",
            message: "Noch \(Int(battery.batteryLevel * 100))% – Bald aufladen.",
            duration: 6
        )

        NotificationCenter.default.post(
            name: .controllerBatteryLow,
            object: nil,
            userInfo: ["name": name, "level": battery.batteryLevel]
        )
    }

    // MARK: - Scanning

    private func scanControllers() {
        connectedControllers = GCController.controllers().map { controller in
            makeControllerInfo(controller)
        }
    }

    private func makeControllerInfo(_ controller: GCController) -> ControllerInfo {
        let category: ControllerInfo.ControllerCategory
        if controller.extendedGamepad != nil {
            category = .extended
        } else if controller.microGamepad != nil {
            category = .micro
        } else {
            category = .standard
        }

        let battery = controller.battery
        return ControllerInfo(
            uniqueID: controller.vendorName ?? UUID().uuidString,
            vendorName: controller.vendorName ?? "Unbekannt",
            category: category,
            productCategory: controller.productCategory,
            batteryLevel: battery?.batteryLevel,
            batteryState: batteryState(from: battery?.batteryState ?? .unknown),
            isConnected: true
        )
    }

    private func updateBattery(for controller: GCController) {
        guard let battery = controller.battery else { return }
        let id = controller.vendorName ?? UUID().uuidString
        guard let idx = connectedControllers.firstIndex(where: { $0.uniqueID == id }) else { return }
        connectedControllers[idx].batteryLevel = battery.batteryLevel
        connectedControllers[idx].batteryState = batteryState(from: battery.batteryState)
    }

    private func batteryState(from state: GCDeviceBattery.State) -> ControllerInfo.BatteryState {
        switch state {
        case .unknown:    return .unknown
        case .charging:   return .charging
        case .discharging: return .discharging
        case .full:       return .full
        @unknown default: return .unknown
        }
    }

    // MARK: - Button Remapping

    func applyRemappings(for controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }
        let mappings = RemappingManager.shared.activeMappings()
        guard !mappings.isEmpty else { return }

        let originalHandler = gamepad.valueChangedHandler

        gamepad.valueChangedHandler = { [weak self] gp, element in
            originalHandler?(gp, element)

            guard let self = self else { return }
            let elID = self.buttonID(for: element, on: gp)
            guard let mapping = mappings.first(where: { $0.sourceID == elID }),
                  let targetEl = self.element(for: mapping.targetID, on: gp),
                  let btn = targetEl as? GCControllerButtonInput,
                  let sourceBtn = element as? GCControllerButtonInput else { return }

            btn.pressedChangedHandler?(btn, sourceBtn.value, sourceBtn.isPressed)

            self.lastActivity = "Remap: \(mapping.sourceID) → \(mapping.targetID)"
        }

        let key = controller.vendorName ?? controller.productCategory
        var dict = remappingHandlers[key] as? [String: Any] ?? [:]
        dict["valueChangedHandler"] = gamepad.valueChangedHandler
        remappingHandlers[key] = dict
    }

    func removeRemappings(for controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }
        let key = controller.vendorName ?? controller.productCategory
        if let dict = remappingHandlers[key] as? [String: Any],
           let handler = dict["valueChangedHandler"] as? (GCExtendedGamepad, GCControllerElement) -> Void {
            if gamepad.valueChangedHandler as AnyObject === handler as AnyObject {
                gamepad.valueChangedHandler = nil
            }
        }
        remappingHandlers[key] = nil
    }

    /// Reset and re-apply remappings to all connected controllers.
    func refreshRemappings() {
        for ctrl in GCController.controllers() {
            removeRemappings(for: ctrl)
            applyRemappings(for: ctrl)
        }
    }

    // MARK: - Button ID Helpers

    private func buttonID(for element: GCControllerElement, on gp: GCExtendedGamepad) -> String {
        switch element {
        case gp.buttonA: return "buttonA"
        case gp.buttonB: return "buttonB"
        case gp.buttonX: return "buttonX"
        case gp.buttonY: return "buttonY"
        case gp.leftShoulder: return "leftShoulder"
        case gp.rightShoulder: return "rightShoulder"
        case gp.leftTrigger: return "leftTrigger"
        case gp.rightTrigger: return "rightTrigger"
        case gp.dpad.up: return "dpadUp"
        case gp.dpad.down: return "dpadDown"
        case gp.dpad.left: return "dpadLeft"
        case gp.dpad.right: return "dpadRight"
        case gp.leftThumbstickButton: return "leftThumbstickButton"
        case gp.rightThumbstickButton: return "rightThumbstickButton"
        case gp.buttonMenu: return "buttonMenu"
        case gp.buttonOptions: return "buttonOptions"
        default: return element.localizedName ?? ""
        }
    }

    private func element(for buttonID: String, on gamepad: GCExtendedGamepad) -> GCControllerElement? {
        switch buttonID {
        case "buttonA": return gamepad.buttonA
        case "buttonB": return gamepad.buttonB
        case "buttonX": return gamepad.buttonX
        case "buttonY": return gamepad.buttonY
        case "leftShoulder": return gamepad.leftShoulder
        case "rightShoulder": return gamepad.rightShoulder
        case "leftTrigger": return gamepad.leftTrigger
        case "rightTrigger": return gamepad.rightTrigger
        case "dpadUp": return gamepad.dpad.up
        case "dpadDown": return gamepad.dpad.down
        case "dpadLeft": return gamepad.dpad.left
        case "dpadRight": return gamepad.dpad.right
        case "leftThumbstickButton": return gamepad.leftThumbstickButton
        case "rightThumbstickButton": return gamepad.rightThumbstickButton
        case "buttonMenu": return gamepad.buttonMenu
        case "buttonOptions": return gamepad.buttonOptions
        default: return nil
        }
    }

    // MARK: - Testing

    func startSimulatedActivity() {
        lastActivity = "\(Date().formatted(date: .omitted, time: .standard)) – Eingabe erkannt"
    }
}

extension Notification.Name {
    static let controllerBatteryLow = Notification.Name("controllerBatteryLow")
}
