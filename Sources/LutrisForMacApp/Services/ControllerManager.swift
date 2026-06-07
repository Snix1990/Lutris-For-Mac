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
            center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
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
        let controllers = GCController.controllers()
        for controller in controllers {
            updateBattery(for: controller)
        }
    }

    // MARK: - Scanning

    private func scanControllers() {
        let controllers = GCController.controllers()
        connectedControllers = controllers.map { controller in
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
        updateBattery(for: controller, battery: battery)
    }

    private func updateBattery(for controller: GCController, battery: GCDeviceBattery) {
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

    // MARK: - Testing

    func startSimulatedActivity() {
        lastActivity = "\(Date().formatted(date: .omitted, time: .standard)) – Eingabe erkannt"
    }
}
