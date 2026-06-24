import Foundation
import GameController
import AppKit
import LutrisForMacCore

// ================================================================
// ControllerIntegration.swift
// ================================================================
// Glue-Code zum bestehenden ControllerManager.
// Aktiviert/deaktiviert das ControllerNavigationSystem + räumt
// alte applyRemappings()-Handler weg, damit keine Konflikte
// zwischen zwei valueChangedHandler entstehen.
// ================================================================

@MainActor
public extension ControllerManager {

    /// Aktiviert Navigation für Console Mode.
    /// Löscht vorherige Remappings, da ControllerNavigationSystem
    /// einen eigenen valueChangedHandler setzt.
    func enableNavigationSystem(focusManager: ConsoleFocusManager) {
        // Original-Handler vor HIDRemapper-Überschreibung sichern
        for controller in GCController.controllers() {
            guard let gamepad = controller.extendedGamepad else { continue }
            let oid = ObjectIdentifier(controller)
            if HIDRemapper.shared.originalHandlers[oid] == nil {
                HIDRemapper.shared.originalHandlers[oid] = gamepad.valueChangedHandler
            }
        }

        HIDRemapper.shared.backend = .passThrough
        HIDRemapper.shared.clear()
        ControllerNavigationSystem.shared.activate(focusManager: focusManager)
    }

    /// Deaktiviert das Navigationssystem und stellt HIDRemapper vollständig wieder her.
    func disableNavigationSystem() {
        ControllerNavigationSystem.shared.deactivate()
        HIDRemapper.shared.backend = .gcController
        HIDRemapper.shared.refreshAll()
    }
}
