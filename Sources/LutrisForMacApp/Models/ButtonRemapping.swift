import Foundation

// MARK: - ButtonDefinition

struct ButtonDefinition: Codable, Identifiable, Hashable {
    let id: String
    let displayName: String
    let category: ButtonCategory

    enum ButtonCategory: String, Codable, CaseIterable {
        case face, shoulder, trigger, dpad, thumbstick, system
    }
}

// MARK: - Standard Buttons (Extended Gamepad)

let extendedGamepadButtons: [ButtonDefinition] = [
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

struct ButtonRemapping: Codable, Identifiable, Equatable {
    var id = UUID()
    var sourceID: String
    var targetID: String
    var isActive: Bool = true
}

// MARK: - RemappingManager

@MainActor
final class RemappingManager: ObservableObject {
    static let shared = RemappingManager()

    @Published var mappings: [ButtonRemapping] = []

    private let defaultsKey = "buttonRemappings"

    private init() {
        load()
    }

    func add(source: String, target: String) {
        let mapping = ButtonRemapping(sourceID: source, targetID: target)
        mappings.append(mapping)
        save()
    }

    func remove(_ mapping: ButtonRemapping) {
        mappings.removeAll { $0.id == mapping.id }
        save()
    }

    func toggle(_ mapping: ButtonRemapping) {
        guard let idx = mappings.firstIndex(where: { $0.id == mapping.id }) else { return }
        mappings[idx].isActive.toggle()
        save()
    }

    func activeMappings() -> [ButtonRemapping] {
        mappings.filter(\.isActive)
    }

    func mapping(for sourceID: String) -> ButtonRemapping? {
        activeMappings().first { $0.sourceID == sourceID }
    }

    // MARK: - Persistence

    func save() {
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
    static let remappingChanged = Notification.Name("remappingChanged")
}
