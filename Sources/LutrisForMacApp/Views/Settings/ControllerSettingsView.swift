import SwiftUI
import LutrisForMacCore

// ================================================================
// ControllerSettingsView.swift – Refactored
// ================================================================
// Zwei Tabs:
//   1. "UI Navigation"   – Layout-Auswahl, Auto-Detection, Custom Mapping
//   2. "Virtual HID for Games" – Runner-spezifische Profile, Backend
// ================================================================

struct ControllerSettingsView: View {
    @StateObject private var controllerManager = ControllerManager.shared
    @StateObject private var remappingManager = RemappingManager.shared
    @StateObject private var layoutService = UIControllerLayoutService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
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

            Divider()

            // Tab-View
            TabView {
                uiNavigationTab
                    .tabItem { Label { LText("UI Navigation") } icon: { Image(systemName: "rectangle.3.group") } }

                virtualHIDTab
                    .tabItem { Label { LText("Virtual HID for Games") } icon: { Image(systemName: "arrow.triangle.swap") } }
            }
            .frame(minHeight: 350)

            Divider()

            HStack {
                if !controllerManager.lastActivity.isEmpty {
                    Text(verbatim: trf("Letzte Aktivität: %@", controllerManager.lastActivity))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button { controllerManager.refresh() } label: { LText("Aktualisieren") }
                Button { dismiss() } label: { LText("Schliessen") }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 520, minHeight: 520)
    }

    // MARK: - Tab 1: UI Navigation

    private var uiNavigationTab: some View {
        Form {
            Section {
                Toggle(isOn: $layoutService.autoDetectionEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        LText("Automatisch erkennen")
                        LText("Erkennt Controller-Typ anhand des Herstellernamens")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: layoutService.autoDetectionEnabled) { _, _ in
                    layoutService.refreshDetectedLayouts()
                }
            }

            Section(header: Text(verbatim: tr("Controller-Profile"))) {
                if controllerManager.connectedControllers.isEmpty {
                    HStack {
                        Spacer()
                        LText("Kein Controller verbunden")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    ForEach(controllerManager.connectedControllers) { info in
                        let key = "\(info.vendorName)|\(info.productCategory)"
                        let detected = layoutService.detectedLayouts[key] ?? .generic
                        HStack {
                            Image(systemName: "gamecontroller.fill")
                                .foregroundColor(.accentColor)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(info.vendorName)
                                    .font(.body)
                                Text(verbatim: "\(info.productCategory) → \(tr(layoutName(detected)))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Picker("", selection: Binding(
                                get: { layoutService.layoutOverrides[key] ?? detected },
                                set: { newValue in
                                    if newValue == detected {
                                        layoutService.removeOverride(for: key)
                                    } else {
                                        layoutService.setOverride(layout: newValue, for: key)
                                    }
                                }
                            )) {
                                ForEach(UIControllerLayout.allCases, id: \.self) { layout in
                                    Text(verbatim: layoutName(layout)).tag(layout)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 140)
                        }
                    }
                }
            }

            Section(header: Text(verbatim: tr("Eigene Button-Zuordnung"))) {
                customMappingList
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func layoutName(_ layout: UIControllerLayout) -> String {
        switch layout {
        case .xbox: return "Xbox"
        case .playstation: return "PlayStation"
        case .nintendo: return "Nintendo Switch"
        case .generic: return "Generic"
        }
    }

    // MARK: - Custom UI Mapping

    private var customMappingList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if layoutService.customMappings.isEmpty {
                HStack {
                    Spacer()
                    LText("Keine eigenen Zuordnungen – Standard-Layout wird verwendet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 6)
            } else {
                List {
                    ForEach(layoutService.customMappings) { mapping in
                        let actionName = mapping.action.displayName
                        let physName = mapping.physicalButton.displayName
                        HStack {
                            Toggle(isOn: Binding(
                                get: { mapping.isActive },
                                set: { _ in layoutService.toggleCustomMapping(action: mapping.action) }
                            )) { EmptyView() }
                            .toggleStyle(.switch)
                            .labelsHidden()
                            Text(actionName)
                                .font(.body)
                            Spacer()
                            Text(physName)
                                .font(.body)
                                .foregroundColor(.secondary)
                            Button {
                                layoutService.removeCustomMapping(action: mapping.action)
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
                .frame(height: min(CGFloat(layoutService.customMappings.count) * 36, 150))
            }

            HStack {
                Menu {
                    ForEach(UIAction.allCases, id: \.self) { action in
                        Button(action.displayName) {
                            showActionPicker = action
                        }
                    }
                } label: {
                    Label { LText("Zuordnung hinzufügen") } icon: { Image(systemName: "plus.circle") }
                }

                Spacer()

                if !layoutService.customMappings.isEmpty {
                    Button(role: .destructive) {
                        layoutService.resetCustomMappings()
                    } label: {
                        LText("Zurücksetzen")
                    }
                    .font(.caption)
                }
            }
        }
        .sheet(item: $showActionPicker) { action in
            customMappingSheet(for: action)
        }
    }

    @State private var showActionPicker: UIAction?

    private func customMappingSheet(for action: UIAction) -> some View {
        VStack(spacing: 16) {
            Text(verbatim: trf("Mapping für: %@", action.displayName))
                .font(.headline)

            LText("Wähle den physischen Button für diese UI-Aktion:")
                .font(.subheadline)

            let currentPhys = layoutService.customMappings.first(where: { $0.action == action })?.physicalButton
                ?? layoutService.effectivePhysicalButton(for: action, layout: .generic)

            Picker("", selection: Binding(
                get: { currentPhys },
                set: { newValue in
                    layoutService.setCustomMapping(action: action, physicalButton: newValue)
                    showActionPicker = nil
                }
            )) {
                ForEach(PhysicalButton.allCases, id: \.self) { phys in
                    Text(verbatim: phys.displayName).tag(phys)
                }
            }
            .labelsHidden()
            .pickerStyle(.radioGroup)

            HStack {
                Button(tr("Abbrechen")) { showActionPicker = nil }
                Button(tr("Übernehmen")) { showActionPicker = nil }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top)
        }
        .padding()
        .frame(width: 360, height: 400)
    }

    // MARK: - Tab 2: Virtual HID for Games

    @State private var selectedRunnerForHID: String = ""
    @State private var runnerHIDProfileIDs: [String: UUID] = [:]

    private var virtualHIDTab: some View {
        Form {
            Section(header: Text(verbatim: tr("HID Remapper Backend"))) {
                Picker(selection: Binding(
                    get: { HIDRemapper.shared.backend },
                    set: { HIDRemapper.shared.backend = $0 }
                )) {
                    Text("In-App (GCController)").tag(HIDRemapperBackend.gcController)
                    Text("Systemweit (IOKit)").tag(HIDRemapperBackend.ioKit)
                    Text("Deaktiviert (PassThrough)").tag(HIDRemapperBackend.passThrough)
                } label: {
                    LText("Backend")
                }
                .pickerStyle(.menu)

                LText("GCController: Nur in der App. IOKit: Systemweit sichtbar (für Emulatoren).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text(verbatim: tr("Pro Runner: HID-Profile"))) {
                VStack(alignment: .leading, spacing: 12) {
                    LText("Wähle pro Runner ein Remapping-Profil. Beim Spielstart wird das Profil automatisch aktiviert.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    let runners = RunnerManager.shared.runners

                    if runners.isEmpty {
                        HStack {
                            Spacer()
                            LText("Keine Runner gefunden")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    } else {
                        List {
                            ForEach(runners) { runner in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(runner.displayName)
                                            .font(.body)
                                        Text(runner.category.rawValue)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    let profileID = runnerMappingProfileID(for: runner.name)
                                    Picker("", selection: Binding(
                                        get: { profileID ?? UUID() },
                                        set: { newID in
                                            setRunnerMappingProfileID(runnerName: runner.name, profileID: newID)
                                        }
                                    )) {
                                        Text(verbatim: tr("Kein Profil (Passthrough)")).tag(UUID())
                                        ForEach(RemappingService.shared.profiles) { profile in
                                            Text(profile.name).tag(profile.id)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 180)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .listStyle(.plain)
                        .frame(height: min(CGFloat(runners.count) * 44, 200))
                    }
                }
            }

            Section(header: Text(verbatim: tr("Button-Remapping (Global)"))) {
                globalRemappingSection
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            loadRunnerProfileIDs()
        }
    }

    // MARK: - Runner HID Profile Persistence

    private func runnerMappingProfileID(for runnerName: String) -> UUID? {
        runnerHIDProfileIDs[runnerName]
    }

    private func setRunnerMappingProfileID(runnerName: String, profileID: UUID) {
        if profileID == UUID() {
            runnerHIDProfileIDs.removeValue(forKey: runnerName)
        } else {
            runnerHIDProfileIDs[runnerName] = profileID
        }
        saveRunnerProfileIDs()
    }

    private func loadRunnerProfileIDs() {
        guard let data = UserDefaults.standard.data(forKey: "runnerHIDProfileIDs"),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        runnerHIDProfileIDs = dict.compactMapValues { UUID(uuidString: $0) }
    }

    private func saveRunnerProfileIDs() {
        let dict = Dictionary(uniqueKeysWithValues: runnerHIDProfileIDs.map { ($0.key, $0.value.uuidString) })
        guard let data = try? JSONEncoder().encode(dict) else { return }
        UserDefaults.standard.set(data, forKey: "runnerHIDProfileIDs")
    }

    // MARK: - Global Remapping (existing)

    @State private var showAddMapping = false
    @State private var newSource = "buttonA"
    @State private var newTarget = "buttonB"

    private var globalRemappingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                                Section(header: Text(verbatim: tr("Ziel ändern"))) {
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

            Button { showAddMapping = true } label: {
                Label { LText("Neues Mapping hinzufügen") } icon: { Image(systemName: "plus.circle") }
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
}

extension UIAction: Identifiable {
    public var id: String { rawValue }
}
