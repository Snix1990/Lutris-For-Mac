import Foundation

// MARK: - ButtonDefinition

public struct ButtonDefinition: Codable, Identifiable, Hashable {
    public let id: String
    public let displayName: String
    public let category: ButtonCategory

    public enum ButtonCategory: String, Codable, CaseIterable {
        case face, shoulder, trigger, dpad, thumbstick, system
    }
}

// MARK: - Standard Buttons (Extended Gamepad)

public let extendedGamepadButtons: [ButtonDefinition] = [
    ButtonDefinition(id: "buttonA", displayName: "A", category: .face),
    ButtonDefinition(id: "buttonB", displayName: "B", category: .face),
    ButtonDefinition(id: "buttonX", displayName: "X", category: .face),
    ButtonDefinition(id: "buttonY", displayName: "Y", category: .face),
    ButtonDefinition(id: "leftShoulder", displayName: "L1", category: .shoulder),
    ButtonDefinition(id: "rightShoulder", displayName: "R1", category: .shoulder),
    ButtonDefinition(id: "leftTrigger", displayName: "L2", category: .trigger),
    ButtonDefinition(id: "rightTrigger", displayName: "R2", category: .trigger),
    ButtonDefinition(id: "dpadUp", displayName: "DPad ↑", category: .dpad),
    ButtonDefinition(id: "dpadDown", displayName: "DPad ↓", category: .dpad),
    ButtonDefinition(id: "dpadLeft", displayName: "DPad ←", category: .dpad),
    ButtonDefinition(id: "dpadRight", displayName: "DPad →", category: .dpad),
    ButtonDefinition(id: "leftThumbstickButton", displayName: "L3", category: .thumbstick),
    ButtonDefinition(id: "rightThumbstickButton", displayName: "R3", category: .thumbstick),
    ButtonDefinition(id: "buttonMenu", displayName: "Menu", category: .system),
    ButtonDefinition(id: "buttonOptions", displayName: "Options", category: .system),
]

// MARK: - ButtonRemapping

public struct ButtonRemapping: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var sourceID: String
    public var targetID: String
    public var isActive: Bool = true
}

// MARK: - RemappingManager

@MainActor
public final class RemappingManager: ObservableObject {
    public static let shared = RemappingManager()

    @Published public var mappings: [ButtonRemapping] = []

    private let defaultsKey = "buttonRemappings"

    private init() {
        load()
    }

    public func add(source: String, target: String) {
        let mapping = ButtonRemapping(sourceID: source, targetID: target)
        mappings.append(mapping)
        save()
    }

    public func remove(_ mapping: ButtonRemapping) {
        mappings.removeAll { $0.id == mapping.id }
        save()
    }

    public func toggle(_ mapping: ButtonRemapping) {
        guard let idx = mappings.firstIndex(where: { $0.id == mapping.id }) else { return }
        mappings[idx].isActive.toggle()
        save()
    }

    public func activeMappings() -> [ButtonRemapping] {
        mappings.filter(\.isActive)
    }

    public func mapping(for sourceID: String) -> ButtonRemapping? {
        activeMappings().first { $0.sourceID == sourceID }
    }

    // MARK: - Persistence

    public func save() {
        if let data = try? JSONEncoder().encode(mappings) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
        NotificationCenter.default.post(name: .remappingChanged, object: nil)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let loaded = try? JSONDecoder().decode([ButtonRemapping].self, from: data) else {
            mappings = []
            return
        }
        mappings = loaded
    }
}

extension Notification.Name {
    public static let remappingChanged = Notification.Name("remappingChanged")
}
