import Foundation
import IOKit
import GameController

// MARK: - Public API

enum ControllerBatteryInfo {
    case connected(level: Float, name: String)
    case connectedNoBattery(name: String)
    case notFound
    
    var displayLevel: String {
        switch self {
        case .connected(let level, _):
            return "\(Int(level * 100))%"
        case .connectedNoBattery:
            return "—"
        case .notFound:
            return "N/A"
        }
    }
}

// MARK: - Battery Monitor

enum ConsoleBatteryMonitor {
    
    /// Liest den Battery-Level eines verbundenen Game-Controllers.
    static func readBattery(vendorName: String) -> ControllerBatteryInfo {
        if let info = readGameControllerBattery(vendorName: vendorName) {
            return info
        }
        return .notFound
    }
    
    // MARK: - GameController Framework (Generisch)
    
    private static func readGameControllerBattery(vendorName: String) -> ControllerBatteryInfo? {
        for controller in GCController.controllers() {
            let controllerName = controller.vendorName ?? "Unknown"
            let productName = controller.productCategory
            
            let matches = controllerName.localizedCaseInsensitiveContains(vendorName) ||
                          productName.localizedCaseInsensitiveContains(vendorName) ||
                          vendorName.localizedCaseInsensitiveContains(controllerName)
            
            guard matches else { continue }
            
            guard let battery = controller.battery else {
                return .connectedNoBattery(name: controllerName)
            }
            
            let level = battery.batteryLevel
            if level > 0 {
                return .connected(level: level, name: controllerName)
            } else {
                return .connectedNoBattery(name: controllerName)
            }
        }
        return nil
    }
    
    // MARK: - Convenience: PS5 DualSense
    
    static func readDualSenseBattery() -> ControllerBatteryInfo {
        for controller in GCController.controllers() {
            let name = controller.vendorName ?? ""
            let product = controller.productCategory
            
            let isDualSense = name.localizedCaseInsensitiveContains("Sony") ||
                              product.localizedCaseInsensitiveContains("DualSense") ||
                              product.localizedCaseInsensitiveContains("Dual Sense")
            
            guard isDualSense else { continue }
            
            let displayName = name.isEmpty ? "DualSense" : name
            guard let battery = controller.battery else {
                return .connectedNoBattery(name: displayName)
            }
            if battery.batteryLevel > 0 {
                return .connected(level: battery.batteryLevel, name: displayName)
            }
            return .connectedNoBattery(name: displayName)
        }
        return .notFound
    }
    
    // MARK: - Convenience: PS4 DualShock
    
    static func readDualShockBattery() -> ControllerBatteryInfo {
        for controller in GCController.controllers() {
            let name = controller.vendorName ?? ""
            let product = controller.productCategory
            
            let isDualShock = name.localizedCaseInsensitiveContains("Sony") ||
                              product.localizedCaseInsensitiveContains("DualShock") ||
                              product.localizedCaseInsensitiveContains("Dual Shock")
            
            guard isDualShock else { continue }
            
            let displayName = name.isEmpty ? "DualShock" : name
            guard let battery = controller.battery else {
                return .connectedNoBattery(name: displayName)
            }
            if battery.batteryLevel > 0 {
                return .connected(level: battery.batteryLevel, name: displayName)
            }
            return .connectedNoBattery(name: displayName)
        }
        return .notFound
    }
    
    // MARK: - Convenience: Xbox
    
    static func readXboxBattery() -> ControllerBatteryInfo {
        for controller in GCController.controllers() {
            let name = controller.vendorName ?? ""
            let product = controller.productCategory
            
            let isXbox = name.localizedCaseInsensitiveContains("Microsoft") ||
                         name.localizedCaseInsensitiveContains("Xbox") ||
                         product.localizedCaseInsensitiveContains("Xbox")
            
            guard isXbox else { continue }
            
            let displayName = name.isEmpty ? "Xbox" : name
            guard let battery = controller.battery else {
                return .connectedNoBattery(name: displayName)
            }
            if battery.batteryLevel > 0 {
                return .connected(level: battery.batteryLevel, name: displayName)
            }
            return .connectedNoBattery(name: displayName)
        }
        return .notFound
    }
    
    // MARK: - Alle verbundenen Controller
    
    /// Gibt Battery-Info für alle verbundenen Controller zurück
    static func readAllControllersBattery() -> [ControllerBatteryInfo] {
        var results: [ControllerBatteryInfo] = []
        
        for controller in GCController.controllers() {
            let name = controller.vendorName ?? "Unknown Controller"
            
            guard let battery = controller.battery else {
                results.append(.connectedNoBattery(name: name))
                continue
            }
            
            if battery.batteryLevel > 0 {
                results.append(.connected(level: battery.batteryLevel, name: name))
            } else {
                results.append(.connectedNoBattery(name: name))
            }
        }
        
        return results
    }
}
