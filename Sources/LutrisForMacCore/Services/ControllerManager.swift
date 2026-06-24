import Foundation
import GameController
import AppKit

@MainActor
public final class ControllerManager: ObservableObject {
    public static let shared = ControllerManager()

    @Published public var connectedControllers: [ControllerInfo] = []
    @Published public var lastActivity: String = ""

    private var observationTokens: [NSObjectProtocol] = []
    private var batteryPollTimer: Timer?
    private var lowBatteryNotifiedIDs: Set<String> = []

    public struct ControllerInfo: Identifiable {
        public let id = UUID()
        public let uniqueID: String
        public let vendorName: String
        public let category: ControllerCategory
        public let productCategory: String
        public var batteryLevel: Float?
        public var batteryState: BatteryState
        public var isConnected: Bool

        public enum ControllerCategory: String {
            case extended = "Extended Gamepad"
            case micro = "Micro Gamepad"
            case standard = "Standard"
            case unknown = "Unbekannt"
        }

        public enum BatteryState: String {
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

        observationTokens.append(
            NotificationCenter.default.addObserver(
                forName: .remappingChanged,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    HIDRemapper.shared.refreshAll()
                }
            }
        )
    }

    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        batteryPollTimer?.invalidate()
    }

    public func refresh() {
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
        let batteryState = batteryState(from: battery?.batteryState ?? .unknown)
        let batteryLevel = getBatteryLevel(for: controller)

        return ControllerInfo(
            uniqueID: controller.vendorName ?? UUID().uuidString,
            vendorName: controller.vendorName ?? "Unbekannt",
            category: category,
            productCategory: controller.productCategory,
            batteryLevel: batteryLevel,
            batteryState: batteryState,
            isConnected: true
        )
    }

    // MARK: - Battery Helper
    private func getBatteryLevel(for controller: GCController) -> Float? {
        // Versuche 1: Direkt vom Controller
        if let directLevel = controller.battery?.batteryLevel, directLevel > 0 {
            return directLevel
        }
        
        // Versuche 2: Über ConsoleBatteryMonitor (Fallback)
        let vendorName = controller.vendorName ?? ""
        if !vendorName.isEmpty {
            let info = ConsoleBatteryMonitor.readBattery(vendorName: vendorName)
            switch info {
            case .connected(let level, _):
                return level
            default:
                break
            }
        }
        
        return nil
    }


    private func updateBattery(for controller: GCController) {
        let battery = controller.battery
        let id = controller.vendorName ?? UUID().uuidString
        guard let idx = connectedControllers.firstIndex(where: { $0.uniqueID == id }) else { return }
        connectedControllers[idx].batteryLevel = getBatteryLevel(for: controller)
        connectedControllers[idx].batteryState = batteryState(from: battery?.batteryState ?? .unknown)
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

    // MARK: - Remapping (delegated to HIDRemapper)

    /// Activate the mapping profile for a game launch.
    public func activateMapping(for gameID: UUID) {
        RemappingService.shared.activate(for: gameID)
        lastActivity = "Mapping aktiviert für \(gameID)"
    }

    /// Deactivate all mappings.
    public func deactivateMapping() {
        RemappingService.shared.deactivate()
        lastActivity = "Mapping deaktiviert"
    }

    // MARK: - Testing

    public func startSimulatedActivity() {
        lastActivity = "\(Date().formatted(date: .omitted, time: .standard)) – Eingabe erkannt"
    }
}

public extension Notification.Name {
    static let controllerBatteryLow = Notification.Name("controllerBatteryLow")
}
