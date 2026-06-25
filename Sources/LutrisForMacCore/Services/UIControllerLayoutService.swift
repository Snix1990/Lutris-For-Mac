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

    @Published public var autoDetectionEnabled: Bool = true
    @Published public var layoutOverrides: [String: UIControllerLayout] = [:]
    @Published public var customMappings: [UICustomMapping] = []
    @Published public var detectedLayouts: [String: UIControllerLayout] = [:]
    /// Monoton steigender Zähler –每当 er sich ändert, muss
    /// die actionMap in ControllerNavigationSystem neu gebaut werden.
    @Published public var actionMapVersion: UInt64 = 0

    // MARK: - Persistence Keys

    private let overridesKey = "uiControllerLayoutOverrides"
    private let autoDetectionKey = "uiControllerAutoDetectionEnabled"
    private let customMappingsKey = "uiControllerCustomMappings"

    // MARK: - Init

    private init() {
        load()
    }

    // MARK: - Layout Detection

    public func detectLayout(for controller: GCController) -> UIControllerLayout {
        let key = controllerTypeKey(for: controller)
        if let override = layoutOverrides[key] {
            return override
        }
        guard autoDetectionEnabled else { return .generic }
        return Self.detectLayout(
            fromVendorName: controller.vendorName,
            productCategory: controller.productCategory
        )
    }

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

        if combined.contains("xbox") || combined.contains("microsoft") {
            return .xbox
        }

        return .generic
    }

    public func refreshDetectedLayouts() {
        var result: [String: UIControllerLayout] = [:]
        for ctrl in GCController.controllers() {
            let key = controllerTypeKey(for: ctrl)
            result[key] = detectLayout(for: ctrl)
        }
        detectedLayouts = result
        actionMapVersion &+= 1
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

    // MARK: - Custom Mapping Management (type-safe)

    public func setCustomMapping(action: UIAction, physicalButton: PhysicalButton) {
        if let idx = customMappings.firstIndex(where: { $0.action == action }) {
            customMappings[idx].physicalButton = physicalButton
            customMappings[idx].isActive = true
        } else {
            let mapping = UICustomMapping(action: action, physicalButton: physicalButton)
            customMappings.append(mapping)
        }
        save()
        actionMapVersion &+= 1
    }

    public func removeCustomMapping(action: UIAction) {
        customMappings.removeAll { $0.action == action }
        save()
        actionMapVersion &+= 1
    }

    public func toggleCustomMapping(action: UIAction) {
        guard let idx = customMappings.firstIndex(where: { $0.action == action }) else { return }
        customMappings[idx].isActive.toggle()
        save()
        actionMapVersion &+= 1
    }

    /// Returns the effective PhysicalButton for an action (custom override wins).
    public func effectivePhysicalButton(for action: UIAction, layout: UIControllerLayout) -> PhysicalButton {
        if let custom = customMappings.first(where: { $0.action == action && $0.isActive }) {
            return custom.physicalButton
        }
        return layout.physicalButton(for: action)
    }

    /// Build the full action map: PhysicalButton → UIAction (layout defaults + custom overrides).
    public func effectiveActionMap(for layout: UIControllerLayout) -> [PhysicalButton: UIAction] {
        var map = layout.physicalToAction
        for custom in customMappings where custom.isActive {
            // Remove any previous mapping for this action
            for (physID, action) in map where action == custom.action {
                map.removeValue(forKey: physID)
            }
            map[custom.physicalButton] = custom.action
        }
        return map
    }

    /// Build the action map from PhysicalButton→UIAction for a given layout.
    /// Convenience mappings (thumbstick buttons, triggers) are included.
    public func effectiveActionMapWithConvenience(for layout: UIControllerLayout) -> [PhysicalButton: UIAction] {
        var map = effectiveActionMap(for: layout)
        map[.leftThumbstickButton] = .confirm
        map[.rightThumbstickButton] = .back
        map[.leftTrigger] = .moveLeft
        map[.rightTrigger] = .moveRight
        return map
    }

    // MARK: - Reset

    public func resetCustomMappings() {
        customMappings.removeAll()
        save()
        actionMapVersion &+= 1
    }

    // MARK: - Controller Keys

    /// Generiert einen stabilen Typ-Schlüssel (vendor|category), der für Override-Persistenz
    /// und Layout-Detection verwendet wird. Zwei identische Controller teilen sich diesen Key.
    public func controllerTypeKey(for controller: GCController) -> String {
        Self.controllerTypeKey(vendorName: controller.vendorName ?? "unknown", productCategory: controller.productCategory)
    }

    public static func controllerTypeKey(vendorName: String, productCategory: String) -> String {
        "\(vendorName)|\(productCategory)"
    }

    /// Generiert einen instanzspezifischen Schlüssel (vendor|category|#oid) für die
    /// per-Device-Closure-Map. ObjectIdentifier ist über die Lebensdauer der
    /// GCController-Instanz stabil und ändert sich bei neuem Connect.
    public func controllerInstanceKey(for controller: GCController) -> String {
        let oid = ObjectIdentifier(controller)
        return "\(controllerTypeKey(for: controller))|#\(oid.hashValue)"
    }

    @available(*, deprecated, renamed: "controllerTypeKey(for:)")
    public func controllerKey(for controller: GCController) -> String {
        controllerTypeKey(for: controller)
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
