import Foundation
import GameController
import AppKit

@MainActor
final class ControllerManager: ObservableObject {
    static let shared = ControllerManager()

    @Published var connectedControllers: [ControllerInfo] = []
    @Published var lastActivity: String = ""

    private var observationTokens: [NSObjectProtocol] = []

    struct ControllerInfo: Identifiable, Equatable {
        let id = UUID()
        let uniqueID: String
        let vendorName: String
        let category: ControllerCategory
        let productCategory: String
        var batteryLevel: Float?
        var isConnected: Bool

        enum ControllerCategory: String {
            case extended = "Extended Gamepad"
            case micro = "Micro Gamepad"
            case standard = "Standard"
            case unknown = "Unbekannt"
        }
    }

    private init() {
        startObserving()
        scanControllers()
    }

    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func refresh() {
        scanControllers()
    }

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

    private func scanControllers() {
        connectedControllers = GCController.controllers().map { controller in
            let info = controllerInfo(controller)
            return info
        }
    }

    private func controllerInfo(_ controller: GCController) -> ControllerInfo {
        let category: ControllerInfo.ControllerCategory
        if controller.extendedGamepad != nil {
            category = .extended
        } else if controller.microGamepad != nil {
            category = .micro
        } else {
            category = .standard
        }

        let battery: Float?
        if #available(macOS 15.0, *) {
            battery = controller.battery?.batteryLevel
        } else {
            battery = nil
        }

        return ControllerInfo(
            uniqueID: controller.vendorName ?? UUID().uuidString,
            vendorName: controller.vendorName ?? "Unbekannt",
            category: category,
            productCategory: controller.productCategory,
            batteryLevel: battery,
            isConnected: true
        )
    }

    // MARK: - Testing

    func startSimulatedActivity() {
        lastActivity = "\(Date().formatted(date: .omitted, time: .standard)) – Eingabe erkannt"
    }
}
