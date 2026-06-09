import SwiftUI

struct ControllerSettingsView: View {
    @StateObject private var controllerManager = ControllerManager.shared
    @StateObject private var remappingManager = RemappingManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showAddMapping = false
    @State private var newSource = "buttonA"
    @State private var newTarget = "buttonB"

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controllerList
            Divider()
            remappingSection
            Divider()

            if !controllerManager.lastActivity.isEmpty {
                Text(verbatim: trf("Letzte Aktivität: %@", controllerManager.lastActivity))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }

            HStack {
                Button { controllerManager.refresh() } label: { LText("Aktualisieren") }
                Spacer()
                Button { dismiss() } label: { LText("Schliessen") }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 420, minHeight: 400)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "gamecontroller")
                .font(.title2)
            LText("Controller")
                .font(.title2)
                .bold()
            Spacer()
            Text(verbatim: trf("%d verbunden", controllerManager.connectedControllers.count))
                .foregroundColor(.secondary)
        }
        .padding()
    }

    // MARK: - Controller List

    private var controllerList: some View {
        List {
            if controllerManager.connectedControllers.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        LText("Kein Controller verbunden")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        LText("Verbinde einen Controller via Bluetooth oder USB")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                }
            } else {
                Section(header: Text(verbatim: tr("Verbunden"))) {
                    ForEach(controllerManager.connectedControllers) { controller in
                        HStack(spacing: 12) {
                            Image(systemName: controllerIcon(controller.category))
                                .font(.title3)
                                .foregroundColor(.accentColor)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(controller.vendorName)
                                    .font(.headline)
                                HStack(spacing: 6) {
                                    Text(controller.category.rawValue)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(controller.productCategory)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            if let battery = controller.batteryLevel {
                                batteryIcon(battery, state: controller.batteryState)
                            }

                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .listStyle(.bordered)
        .alternatingRowBackgrounds()
    }

    // MARK: - Remapping Section

    private var remappingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.triangle.swap")
                    .foregroundColor(.accentColor)
                LText("Button-Remapping")
                    .font(.headline)
                Spacer()
                Button { showAddMapping = true } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
                .helpLText("Neues Mapping hinzufügen")
            }
            .padding(.horizontal)
            .padding(.top, 8)

            if remappingManager.mappings.isEmpty {
                HStack {
                    Spacer()
                    LText("Keine Mappings definiert")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 6)
            } else {
                List {
                    ForEach(remappingManager.mappings) { mapping in
                        let sourceName = extendedGamepadButtons.first(where: { $0.id == mapping.sourceID })?.displayName ?? mapping.sourceID
                        let targetName = extendedGamepadButtons.first(where: { $0.id == mapping.targetID })?.displayName ?? mapping.targetID
                        HStack {
                            Toggle(isOn: binding(for: mapping)) { }
                            Text(sourceName)
                                .font(.body)
                                .frame(width: 60, alignment: .trailing)
                            Image(systemName: "arrow.right")
                                .foregroundColor(.secondary)
                            Text(targetName)
                                .font(.body)
                                .frame(width: 60, alignment: .leading)
                            Spacer()
                            Menu {
                                Section(header: Text(verbatim: "Ziel ändern")) {
                                    ForEach(extendedGamepadButtons.filter { $0.id != mapping.sourceID }) { btn in
                                        Button(btn.displayName) {
                                            remapTarget(mapping, to: btn.id)
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)

                            Button {
                                remappingManager.remove(mapping)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.plain)
                .frame(height: CGFloat(min(remappingManager.mappings.count, 6)) * 36)
            }
        }
        .sheet(isPresented: $showAddMapping) {
            addMappingSheet
        }
    }

    private var addMappingSheet: some View {
        VStack(spacing: 16) {
            LText("Neues Button-Mapping")
                .font(.headline)
            HStack {
                VStack(alignment: .leading) {
                    LText("Quelle").font(.caption)
                    Picker("", selection: $newSource) {
                        ForEach(extendedGamepadButtons) { btn in
                            Text(btn.displayName).tag(btn.id)
                        }
                    }
                    .labelsHidden()
                }
                Image(systemName: "arrow.right")
                    .padding(.top, 12)
                VStack(alignment: .leading) {
                    LText("Ziel").font(.caption)
                    Picker("", selection: $newTarget) {
                        ForEach(extendedGamepadButtons.filter { $0.id != newSource }) { btn in
                            Text(btn.displayName).tag(btn.id)
                        }
                    }
                    .labelsHidden()
                }
            }
            HStack {
                Button(tr("Abbrechen")) { showAddMapping = false }
                Button(tr("Hinzufügen")) {
                    remappingManager.add(source: newSource, target: newTarget)
                    showAddMapping = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 320)
    }

    // MARK: - Helpers

    private func binding(for mapping: ButtonRemapping) -> Binding<Bool> {
        Binding(
            get: { mapping.isActive },
            set: { _ in remappingManager.toggle(mapping) }
        )
    }

    private func remapTarget(_ mapping: ButtonRemapping, to newTargetID: String) {
        guard let idx = remappingManager.mappings.firstIndex(where: { $0.id == mapping.id }) else { return }
        remappingManager.mappings[idx].targetID = newTargetID
        remappingManager.save()
    }

    // MARK: - Icons

    private func controllerIcon(_ category: ControllerManager.ControllerInfo.ControllerCategory) -> String {
        switch category {
        case .extended: return "gamecontroller.fill"
        case .micro: return "rectangle.3.group.fill"
        case .standard: return "gamecontroller"
        case .unknown: return "questionmark"
        }
    }

    private func batteryIcon(_ level: Float, state: ControllerManager.ControllerInfo.BatteryState) -> some View {
        let icon: String
        let color: Color
        switch level {
        case 0.75...1.0:
            icon = "battery.100"
            color = .green
        case 0.5..<0.75:
            icon = "battery.75"
            color = .green
        case 0.25..<0.5:
            icon = "battery.50"
            color = .orange
        case 0.1..<0.25:
            icon = "battery.25"
            color = .red
        default:
            icon = "battery.0"
            color = .red
        }
        return HStack(spacing: 4) {
            if state == .charging {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.yellow)
                    .font(.caption2)
            }
            Image(systemName: icon)
                .foregroundColor(color)
            Text(verbatim: "\(Int(level * 100))%")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
