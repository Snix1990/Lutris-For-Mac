import Foundation
import GameController
import OSLog

// ================================================================
// HIDRemapper.swift  –  Controller button remapping engine
// ================================================================
// Zwei Backends:
//   .gcController – interceptiert valueChangedHandler (In‑App)
//   .ioKit        – Virtual IOHIDUserDevice (systemweit)
// ================================================================

private let log = Logger(subsystem: "net.lutrisformac", category: "HIDRemapper")

// MARK: - Backend Selection

public enum HIDRemapperBackend: String, Codable, Sendable {
    /// Intercepts GCController.valueChangedHandler (In‑App only)
    case gcController
    /// Virtual IOHIDUserDevice (systemweit sichtbar)
    case ioKit
    /// No remapping
    case passThrough
}

// MARK: - HIDRemapper

@MainActor
public final class HIDRemapper: ObservableObject {
    public static let shared = HIDRemapper()

    @Published public var backend: HIDRemapperBackend = .gcController {
        didSet {
            if oldValue == .ioKit { destroyAllVirtualDevices() }
            if backend == .gcController {
                // Re‑attach GCController handlers
                refreshAll()
            }
        }
    }

    @Published public var activeSourceToTarget: [String: String] = [:]
    @Published public var activeTargetToSource: [String: String] = [:]

    // GCController handler storage
    public var originalHandlers: [ObjectIdentifier: GCExtendedGamepadValueChangedHandler] = [:]
    private var remappedHandlers: [ObjectIdentifier: GCExtendedGamepadValueChangedHandler] = [:]

    // Virtual HID devices (keyed by controller identifier)
    private var virtualDevices: [String: VirtualHIDDevice] = [:]

    // ioKit‑forwarding handler storage (keeps GCController handler alive for reading)
    private var ioKitHandlers: [ObjectIdentifier: GCExtendedGamepadValueChangedHandler] = [:]

    private init() {
        setupNotifications()
    }

    // MARK: - Apply / Clear

    public func applyMappings(_ dict: [String: String]) {
        activeSourceToTarget = dict
        activeTargetToSource = Dictionary(uniqueKeysWithValues: dict.map { ($1, $0) })
        refreshAll()
    }

    public func apply(mappings: [ButtonRemapping]) {
        var dict: [String: String] = [:]
        for m in mappings where m.isActive {
            dict[m.sourceID] = m.targetID
        }
        applyMappings(dict)
    }

    public func apply(profile: PlatformMappingProfile) {
        apply(mappings: profile.mappings)
        log.info("Applied profile: \(profile.name)")
    }

    public func apply(gameConfig: GameMappingConfig, profiles: [PlatformMappingProfile]) {
        let effective = gameConfig.effectiveMappings(profiles: profiles)
        apply(mappings: effective)
        log.info("Applied game config for game \(gameConfig.gameID)")
    }

    public func clear() {
        activeSourceToTarget = [:]
        activeTargetToSource = [:]
        refreshAll()
    }

    // MARK: - Controller Management

    public func refreshAll() {
        for ctrl in GCController.controllers() {
            attachRemapping(to: ctrl)
        }
    }

    private func attachRemapping(to controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }
        let oid = ObjectIdentifier(controller)

        // Always save the original handler first
        if originalHandlers[oid] == nil {
            originalHandlers[oid] = gamepad.valueChangedHandler
        }

        switch backend {
        case .gcController:
            installGCControllerRemapping(gamepad: gamepad, oid: oid)
        case .ioKit:
            installIOKitRemapping(controller: controller, gamepad: gamepad, oid: oid)
        case .passThrough:
            restoreOriginal(gamepad: gamepad, oid: oid)
        }
    }

    private func detachRemapping(from controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }
        let oid = ObjectIdentifier(controller)
        restoreOriginal(gamepad: gamepad, oid: oid)

        if backend == .ioKit {
            let key = controller.vendorName ?? controller.productCategory
            destroyVirtualDevice(key: key)
        }
    }

    private func restoreOriginal(gamepad: GCExtendedGamepad, oid: ObjectIdentifier) {
        if let original = originalHandlers[oid] {
            gamepad.valueChangedHandler = original
        } else {
            gamepad.valueChangedHandler = nil
        }
        remappedHandlers[oid] = nil
        ioKitHandlers[oid] = nil
    }

    // MARK: - GCController Backend

    private func installGCControllerRemapping(gamepad: GCExtendedGamepad, oid: ObjectIdentifier) {
        let original = originalHandlers[oid]

        let handler: GCExtendedGamepadValueChangedHandler = { [weak self] gp, element in
            // Call original so other listeners still work
            original?(gp, element)

            guard let self else { return }
            guard let srcBtn = element as? GCControllerButtonInput else { return }

            let srcID = self.buttonID(for: element, on: gp)
            guard let targetID = self.activeSourceToTarget[srcID] else { return }
            guard let targetEl = self.element(for: targetID, on: gp) as? GCControllerButtonInput else { return }

            targetEl.pressedChangedHandler?(targetEl, srcBtn.value, srcBtn.isPressed)
        }

        gamepad.valueChangedHandler = handler
        remappedHandlers[oid] = handler
    }

    // MARK: - IOKit Backend (Virtual IOHIDUserDevice)

    private func installIOKitRemapping(controller: GCController, gamepad: GCExtendedGamepad, oid: ObjectIdentifier) {
        let key = controller.vendorName ?? controller.productCategory

        // Destroy existing virtual device for this controller
        destroyVirtualDevice(key: key)

        // Create new virtual device
        let vendorID = controller.vendorName?.hash ?? 0x1234
        let productID = controller.productCategory.hash

        guard let virtual = VirtualHIDDevice(
            id: key,
            name: controller.vendorName ?? controller.productCategory,
            vendorID: vendorID,
            productID: productID
        ) else {
            log.error("Failed to create virtual HID device for \(key)")
            return
        }
        virtualDevices[key] = virtual

        // Set up handler that reads ALL input and forwards to virtual device
        let handler: GCExtendedGamepadValueChangedHandler = { [weak self] gp, element in
            guard let self else { return }
            // Forward complete state to virtual device (with remapping)
            virtual.sendReport(from: gp, remap: self.activeSourceToTarget)
        }

        gamepad.valueChangedHandler = handler
        ioKitHandlers[oid] = handler
    }

    private func destroyVirtualDevice(key: String) {
        virtualDevices[key]?.cancel()
        virtualDevices.removeValue(forKey: key)
    }

    private func destroyAllVirtualDevices() {
        for (key, _) in virtualDevices {
            destroyVirtualDevice(key: key)
        }
    }

    // MARK: - Notifications

    private func setupNotifications() {
        let nc = NotificationCenter.default

        nc.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            guard let ctrl = note.object as? GCController else { return }
            Task { @MainActor [weak self] in
                self?.attachRemapping(to: ctrl)
            }
        }

        nc.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
            guard let ctrl = note.object as? GCController else { return }
            Task { @MainActor [weak self] in
                self?.detachRemapping(from: ctrl)
            }
        }

        nc.addObserver(forName: .remappingChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                let activeMappings = RemappingManager.shared.activeMappings()
                self?.apply(mappings: activeMappings)
            }
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
}
