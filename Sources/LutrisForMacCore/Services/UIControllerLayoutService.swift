import Foundation
import GameController
import OSLog
import Combine

private let log = Logger(subsystem: "net.lutrisformac", category: "UIControllerLayout")

// MARK: - UIControllerLayoutService

@MainActor
public final class UIControllerLayoutService: ObservableObject {
    public static let shared = UIControllerLayoutService()

    // MARK: - Published

    /// Auto-detection toggle (default ON)
    @Published public var autoDetectionEnabled: Bool = true

    /// Per-controller-key layout override (key = vendorName|productCategory)
    @Published public var layoutOverrides: [String: UIControllerLayout] = [:]

    /// Custom UI action → physical button overrides (for custom UI mapping)
    @Published public var customMappings: [UICustomMapping] = []

    /// Currently detected layouts per connected controller (key = controller uniqueID)
    @Published public var detectedLayouts: [String: UIControllerLayout] = [:]

    // MARK: - Persistence Keys

    private let overridesKey = "uiControllerLayoutOverrides"
    private let autoDetectionKey = "uiControllerAutoDetectionEnabled"
    private let customMappingsKey = "uiControllerCustomMappings"

    // MARK: - Init

    private init() {
        load()
    }

    // MARK: - Layout Detection

    /// Determine the best layout for a controller.
    /// 1) If override exists → use it
    /// 2) If auto-detection ON → heuristic
    /// 3) Fallback → .generic
    public func detectLayout(for controller: GCController) -> UIControllerLayout {
        let key = controllerKey(for: controller)
        if let override = layoutOverrides[key] {
            return override
        }
        guard autoDetectionEnabled else { return .generic }
        let detected = Self.detectLayout(
            fromVendorName: controller.vendorName,
            productCategory: controller.productCategory
        )
        return detected
    }

    /// Heuristic-based auto-detection.
    public static func detectLayout(fromVendorName vendorName: String?, productCategory: String) -> UIControllerLayout {
        let vendor = (vendorName ?? "").lowercased()
        let category = productCategory.lowercased()
        let combined = vendor + " " + category

        if combined.contains("playstation")
            || combined.contains("ps4") || combined.contains("ps5")
            || combined.contains("dualsense") || combined.contains("dualshock")
            || combined.contains("sony") {
            return .playstation
        }

        if combined.contains("nintendo")
            || combined.contains("switch")
            || combined.contains("pro controller")
            || combined.contains("joy-con") || combined.contains("joycon") {
            return .nintendo
        }

        if combined.contains("xbox")
            || combined.contains("microsoft") {
            return .xbox
        }

        return .generic
    }

    /// Refresh detected layouts for all currently connected controllers.
    public func refreshDetectedLayouts() {
        var result: [String: UIControllerLayout] = [:]
        for ctrl in GCController.controllers() {
            let key = controllerKey(for: ctrl)
            result[key] = detectLayout(for: ctrl)
        }
        detectedLayouts = result
    }

    // MARK: - Override Management

    public func setOverride(layout: UIControllerLayout, for key: String) {
        layoutOverrides[key] = layout
        save()
        refreshDetectedLayouts()
    }

    public func removeOverride(for key: String) {
        layoutOverrides.removeValue(forKey: key)
        save()
        refreshDetectedLayouts()
    }

    // MARK: - Custom Mapping Management

    public func setCustomMapping(action: UIAction, physicalButtonID: String) {
        if let idx = customMappings.firstIndex(where: { $0.action == action }) {
            customMappings[idx].physicalButtonID = physicalButtonID
            customMappings[idx].isActive = true
        } else {
            let mapping = UICustomMapping(action: action, physicalButtonID: physicalButtonID)
            customMappings.append(mapping)
        }
        save()
    }

    public func removeCustomMapping(action: UIAction) {
        customMappings.removeAll { $0.action == action }
        save()
    }

    public func toggleCustomMapping(action: UIAction) {
        guard let idx = customMappings.firstIndex(where: { $0.action == action }) else { return }
        customMappings[idx].isActive.toggle()
        save()
    }

    /// Get the effective physical button ID for an action, considering custom overrides.
    public func effectivePhysicalButtonID(for action: UIAction, layout: UIControllerLayout) -> String {
        if let custom = customMappings.first(where: { $0.action == action && $0.isActive }) {
            return custom.physicalButtonID
        }
        return layout.physicalButtonID(for: action)
    }

    /// Build the full physical → action map for a given layout + custom overrides.
    public func effectiveActionMap(for layout: UIControllerLayout) -> [String: UIAction] {
        var map = layout.physicalToAction
        for custom in customMappings where custom.isActive {
            // Remove old mapping for this action
            for (physID, action) in map where action == custom.action {
                map.removeValue(forKey: physID)
            }
            // Add new custom mapping
            map[custom.physicalButtonID] = custom.action
        }
        return map
    }

    /// Reset all custom mappings to defaults.
    public func resetCustomMappings() {
        customMappings.removeAll()
        save()
    }

    // MARK: - Controller Key

    public func controllerKey(for controller: GCController) -> String {
        let vendor = controller.vendorName ?? "unknown"
        let category = controller.productCategory
        return "\(vendor)|\(category)"
    }

    // MARK: - Persistence

    private func save() {
        let dict = Dictionary(uniqueKeysWithValues: layoutOverrides.map { ($0.key, $0.value.rawValue) })
        UserDefaults.standard.set(dict, forKey: overridesKey)
        UserDefaults.standard.set(autoDetectionEnabled, forKey: autoDetectionKey)
        if let data = try? JSONEncoder().encode(customMappings) {
            UserDefaults.standard.set(data, forKey: customMappingsKey)
        }
    }

    private func load() {
        autoDetectionEnabled = UserDefaults.standard.object(forKey: autoDetectionKey) as? Bool ?? true

        if let dict = UserDefaults.standard.dictionary(forKey: overridesKey) as? [String: String] {
            layoutOverrides = dict.compactMapValues { UIControllerLayout(rawValue: $0) }
        }

        if let data = UserDefaults.standard.data(forKey: customMappingsKey),
           let loaded = try? JSONDecoder().decode([UICustomMapping].self, from: data) {
            customMappings = loaded
        }

        refreshDetectedLayouts()
    }
}
