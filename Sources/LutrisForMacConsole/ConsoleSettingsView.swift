import SwiftUI
import GameController
import LutrisForMacCore

// ================================================================
// ConsoleSettingsView.swift – Refactored
// ================================================================
// Controller-navigierbare Einstellungen.
// Abschnitte:
//   EINSTELLUNGEN (Toggles)
//   CONTROLLER (Liste verbundener Controller)
//   UI NAVIGATION (Layout, Auto-Detection, Custom Mapping)
//   VIRTUAL HID FOR GAMES (Runner-spezifische Profile)
//   BUTTON-REMAP (Globale HID-Remappings)
//   ABOUT
// ================================================================

public struct ConsoleSettingsView: View {
    let onBack: () -> Void
    let onExitDesktop: (() -> Void)?
    let consoleState: ConsoleState

    @ObservedObject private var controllerManager = ControllerManager.shared
    @ObservedObject private var layoutService = UIControllerLayoutService.shared
    @ObservedObject private var remappingManager = RemappingManager.shared
    @ObservedObject private var remappingService = RemappingService.shared
    @EnvironmentObject private var focusManager: ConsoleFocusManager

    public init(onBack: @escaping () -> Void, onExitDesktop: (() -> Void)? = nil, consoleState: ConsoleState) {
        self.onBack = onBack
        self.onExitDesktop = onExitDesktop
        self.consoleState = consoleState
    }

    @AppStorage("console_discord_rpc") private var discordRPC = true
    @AppStorage("console_cloud_sync") private var cloudSync = true
    @AppStorage("console_auto_launch") private var autoLaunch = false
    @AppStorage("console_low_power_mode") private var lowPowerMode = false

    // Expandable sections
    @State private var uiNavExpanded = false
    @State private var uiCustomExpanded = false
    @State private var hidRunnerExpanded = false
    @State private var remappingExpanded = false

    private var toggleItems: [SettingsToggleItem] {
        [
            SettingsToggleItem(id: "discordRPC", icon: "antenna.radiowaves.left.and.right",
                               title: tr("Discord RPC"), subtitle: tr("Zeige deinen aktuellen Spielstatus in Discord"),
                               toggle: $discordRPC),
            SettingsToggleItem(id: "cloudSync", icon: "icloud.fill",
                               title: tr("Cloud Sync"), subtitle: tr("Automatisch mit WebDAV/SMB synchronisieren"),
                               toggle: $cloudSync),
            SettingsToggleItem(id: "autoLaunch", icon: "power",
                               title: tr("Autostart"), subtitle: tr("Console-Modus beim Systemstart öffnen"),
                               toggle: $autoLaunch),
            SettingsToggleItem(id: "lowPowerMode", icon: "bolt.slash.fill",
                               title: tr("Low Power Mode"), subtitle: tr("Animationen reduzieren und Strom sparen"),
                               toggle: $lowPowerMode),
        ]
    }

    // ── Index-Berechnungen ──
    private var toggleEnd: Int { toggleItems.count }
    private var controllerCount: Int { max(controllerManager.connectedControllers.count, 1) }
    private var controllerEnd: Int { toggleEnd + controllerCount }

    // UI Navigation: 1 Header + ggf. Layout-Picker pro Controller + Custom Mapping Header + items
    private var uiNavCount: Int {
        let controllers = controllerManager.connectedControllers.count
        let customMappingCount = layoutService.customMappings.count
        let customItems = 1 + (uiCustomExpanded ? customMappingCount + 1 : 0) // header + items + add-button
        return 1 + (uiNavExpanded ? controllers + customItems : 0)
    }
    private var uiNavEnd: Int { controllerEnd + uiNavCount }

    // HID Runner: 1 Header + ggf. Runner-Profile
    private var runnerCount: Int { RunnerManager.shared.runners.count }
    private var hidRunnerEnd: Int {
        uiNavEnd + 1 + (hidRunnerExpanded ? runnerCount : 0)
    }

    // Remapping: 1 Header + ggf. Items + Add-Button
    private var mappingEnd: Int {
        hidRunnerEnd + 1 + (remappingExpanded ? remappingManager.mappings.count + 1 : 0)
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ScrollController().frame(width: 0, height: 0)

                    // ── Toggles ──
                    sectionHeader(tr("EINSTELLUNGEN"))
                    ForEach(Array(toggleItems.enumerated()), id: \.element.id) { idx, item in
                        toggleRow(icon: item.icon, title: item.title,
                                  subtitle: item.subtitle, toggle: item.toggle,
                                  index: idx)
                    }

                    // ── Controller ──
                    sectionHeader(tr("CONTROLLER"))
                    if controllerManager.connectedControllers.isEmpty {
                        infoRow(title: tr("Kein Controller"), subtitle: tr("Verbinde einen Controller über Bluetooth oder USB"),
                                index: toggleItems.count)
                    } else {
                        ForEach(Array(controllerManager.connectedControllers.enumerated()), id: \.offset) { idx, info in
                            controllerRow(info: info, index: toggleItems.count + idx)
                        }
                    }

                    // ── UI Navigation ──
                    let cEnd = controllerEnd
                    uiNavigationSection(startIndex: cEnd)

                    // ── Virtual HID for Games (Runner-Profile) ──
                    let uiEnd = uiNavEnd
                    hidForGamesSection(startIndex: uiEnd)

                    // ── Button-Remapping (Global) ──
                    let hEnd = hidRunnerEnd
                    buttonRemappingSection(startIndex: hEnd)

                    // ── About ──
                    sectionHeader(tr("ABOUT"))
                    infoRow(title: tr("LutrisForMac Console"), subtitle: tr("Version 1.0.0"),
                            index: mappingEnd)
                    desktopExitRow(index: mappingEnd + 1)
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 40)
            }
            .onChange(of: focusManager.focusedIndex) { _, newIndex in
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo("setting_\(newIndex)", anchor: .center)
                }
            }
        }
        }
        .modifier(ControllerNavigationModifier(
            consoleState: consoleState,
            focusManager: focusManager,
            gridColumns: 1,
            onConfirm: { section, index in handleConfirm(section: section, index: index) },
            onBack: { handleBack() },
            onSearchToggle: { },
            onUpdateFocusState: { },
            onSearchActiveChanged: { _ in }
        ))
        .onAppear {
            focusManager.isLinearMode = true
            focusManager.activeSection = .allGames
            focusManager.focusedIndex = 0
            updateItemCount()
        }
        .onDisappear {
            focusManager.isLinearMode = false
        }
        .onChange(of: uiNavExpanded) { _, _ in updateItemCount() }
        .onChange(of: uiCustomExpanded) { _, _ in updateItemCount() }
        .onChange(of: hidRunnerExpanded) { _, _ in updateItemCount() }
        .onChange(of: remappingExpanded) { _, _ in updateItemCount() }
    }

    // MARK: - UI Navigation Section

    private func uiNavigationSection(startIndex: Int) -> some View {
        Group {
            let isFocused = focusManager.isFocused(section: .allGames, index: startIndex)
            HStack(spacing: 16) {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 24))
                    .foregroundColor(.ps4Pink)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: tr("UI Navigation"))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                    Text(currentLayoutSummary)
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(.white.opacity(0.5))
                }

                Spacer()

                Image(systemName: uiNavExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(isFocused ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.spring(response: 0.3)) { uiNavExpanded.toggle() } }
            .id("setting_\(startIndex)")

            if uiNavExpanded {
                // Auto-Detection Toggle
                let autoIdx = startIndex + 1
                autoDetectionRow(index: autoIdx)

                // Layout per Controller
                let layoutStart = autoIdx + 1
                ForEach(Array(controllerManager.connectedControllers.enumerated()), id: \.offset) { offset, info in
                    let idx = layoutStart + offset
                    let key = "\(info.vendorName)|\(info.productCategory)"
                    let detected = layoutService.detectedLayouts[key] ?? .generic
                    let isFocused2 = focusManager.isFocused(section: .allGames, index: idx)

                    HStack(spacing: 16) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.ps4Pink)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(info.vendorName)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                            Text(verbatim: "\(info.productCategory) → \(layoutDisplayName(detected))")
                                .font(.system(size: 12, weight: .light))
                                .foregroundColor(.white.opacity(0.5))
                        }

                        Spacer()

                        // Layout-Picker
                        let currentOverride = layoutService.layoutOverrides[key]
                        Picker("", selection: Binding(
                            get: { currentOverride ?? detected },
                            set: { newLayout in
                                if newLayout == detected {
                                    layoutService.removeOverride(for: key)
                                } else {
                                    layoutService.setOverride(layout: newLayout, for: key)
                                }
                                updateItemCount()
                            }
                        )) {
                            ForEach(UIControllerLayout.allCases, id: \.self) { layout in
                                Text(verbatim: layoutDisplayName(layout)).tag(layout)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 120)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .padding(.leading, 48)
                    .background(isFocused2 ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .id("setting_\(idx)")
                }

                // Custom Mapping sub-section
                let customHeaderIdx = layoutStart + controllerManager.connectedControllers.count
                customMappingSection(startIndex: customHeaderIdx)
            }
        }
    }

    private var currentLayoutSummary: String {
        if let first = GCController.controllers().first {
            let key = layoutService.controllerKey(for: first)
            let layout = layoutService.detectedLayouts[key] ?? .generic
            return "\(layoutDisplayName(layout)) – \(layoutService.customMappings.count) eigene Zuordnungen"
        }
        return tr("Kein Controller")
    }

    private func layoutDisplayName(_ layout: UIControllerLayout) -> String {
        switch layout {
        case .xbox: return "Xbox"
        case .playstation: return "PlayStation"
        case .nintendo: return "Nintendo Switch"
        case .generic: return "Generic"
        }
    }

    private func autoDetectionRow(index: Int) -> some View {
        let isFocused = focusManager.isFocused(section: .allGames, index: index)
        return HStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundColor(.ps4Pink)
                .frame(width: 24)

            Text(verbatim: tr("Automatisch erkennen"))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)

            Spacer()

            Toggle("", isOn: Binding(
                get: { layoutService.autoDetectionEnabled },
                set: { newValue in
                    layoutService.autoDetectionEnabled = newValue
                    layoutService.refreshDetectedLayouts()
                }
            ))
            .toggleStyle(.switch)
            .tint(.ps4Pink)
            .labelsHidden()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .padding(.leading, 48)
        .background(isFocused ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .id("setting_\(index)")
    }

    // MARK: - Custom UI Mapping (Edit)

    private func customMappingSection(startIndex: Int) -> some View {
        Group {
            let isFocused = focusManager.isFocused(section: .allGames, index: startIndex)
            HStack(spacing: 16) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 18))
                    .foregroundColor(.ps4Pink)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: tr("Eigene Button-Zuordnung"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    Text(verbatim: trf("%d aktive Zuordnungen", layoutService.customMappings.count))
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(.white.opacity(0.5))
                }

                Spacer()

                Image(systemName: uiCustomExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .padding(.leading, 48)
            .background(isFocused ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.spring(response: 0.3)) { uiCustomExpanded.toggle() } }
            .id("setting_\(startIndex)")

            if uiCustomExpanded {
                ForEach(Array(layoutService.customMappings.enumerated()), id: \.element.id) { offset, mapping in
                    let idx = startIndex + 1 + offset
                    let physName = physicalButtonDisplayNames[mapping.physicalButtonID] ?? mapping.physicalButtonID
                    let isFocused2 = focusManager.isFocused(section: .allGames, index: idx)
                    HStack(spacing: 16) {
                        Toggle("", isOn: Binding(
                            get: { mapping.isActive },
                            set: { _ in layoutService.toggleCustomMapping(action: mapping.action) }
                        ))
                        .toggleStyle(.switch)
                        .tint(.ps4Pink)
                        .labelsHidden()

                        Text(mapping.action.displayName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 160, alignment: .leading)

                        Image(systemName: "arrow.right")
                            .foregroundColor(.white.opacity(0.4))

                        Text(physName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)

                        Spacer()

                        Button {
                            layoutService.removeCustomMapping(action: mapping.action)
                            updateItemCount()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .padding(.leading, 64)
                    .background(isFocused2 ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .id("setting_\(idx)")
                }

                // Add-Mapping Button
                let addIdx = startIndex + 1 + layoutService.customMappings.count
                let isAddFocused = focusManager.isFocused(section: .allGames, index: addIdx)
                HStack(spacing: 16) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.ps4Pink)
                        .frame(width: 24)

                    Text(verbatim: tr("Neue Zuordnung"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .padding(.leading, 64)
                .background(isAddFocused ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
                .onTapGesture { showCustomUIMappingSheet = true }
                .id("setting_\(addIdx)")

                // Reset-Button
                if !layoutService.customMappings.isEmpty {
                    let resetIdx = addIdx + 1
                    let isResetFocused = focusManager.isFocused(section: .allGames, index: resetIdx)
                    HStack(spacing: 16) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 18))
                            .foregroundColor(.red.opacity(0.7))
                            .frame(width: 24)

                        Text(verbatim: tr("Zurücksetzen"))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.red.opacity(0.7))

                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .padding(.leading, 64)
                    .background(isResetFocused ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        layoutService.resetCustomMappings()
                        updateItemCount()
                    }
                    .id("setting_\(resetIdx)")
                }
            }
        }
        .sheet(isPresented: $showCustomUIMappingSheet) {
            customUIMappingSheet
        }
    }

    @State private var showCustomUIMappingSheet = false
    @State private var selectedUIAction: UIAction = .confirm
    @State private var selectedPhysicalButton: String = "buttonA"

    private var customUIMappingSheet: some View {
        VStack(spacing: 24) {
            Text(verbatim: tr("Neue Button-Zuordnung"))
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)

            Text(verbatim: tr("Wähle UI-Aktion und physischen Button"))
                .font(.system(size: 18, weight: .light))
                .foregroundColor(.white.opacity(0.6))

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: tr("UI-Aktion"))
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundColor(.ps4Pink)

                    Picker("", selection: $selectedUIAction) {
                        ForEach(UIAction.allCases, id: \.self) { action in
                            Text(action.displayName).tag(action)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                }

                Image(systemName: "arrow.down")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.4))

                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: tr("Physischer Button"))
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundColor(.ps4Pink)

                    Picker("", selection: $selectedPhysicalButton) {
                        ForEach(allPhysicalButtons, id: \.self) { btnID in
                            Text(verbatim: physicalButtonDisplayNames[btnID] ?? btnID).tag(btnID)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(32)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            HStack(spacing: 20) {
                Button(tr("Abbrechen")) { showCustomUIMappingSheet = false }
                    .buttonStyle(ConsoleButtonStyle(color: .white.opacity(0.2)))
                Button(tr("Hinzufügen")) {
                    layoutService.setCustomMapping(action: selectedUIAction, physicalButtonID: selectedPhysicalButton)
                    showCustomUIMappingSheet = false
                    updateItemCount()
                }
                .buttonStyle(ConsoleButtonStyle(color: .ps4Pink))
            }
        }
        .padding(40)
        .frame(width: 480)
        .background(Color.black.opacity(0.95))
    }

    // MARK: - Virtual HID for Games (Runner-Profile)

    @State private var runnerHIDProfileIDs: [String: UUID] = [:]

    private func hidForGamesSection(startIndex: Int) -> some View {
        Group {
            let isFocused = focusManager.isFocused(section: .allGames, index: startIndex)
            HStack(spacing: 16) {
                Image(systemName: "arrow.triangle.swap")
                    .font(.system(size: 24))
                    .foregroundColor(.ps4Pink)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: tr("Virtual HID for Games"))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                    let active = runnerHIDProfileIDs.count
                    Text(verbatim: trf("%d Runner mit Profil", active))
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(.white.opacity(0.5))
                }

                Spacer()

                Image(systemName: hidRunnerExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(isFocused ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.spring(response: 0.3)) { hidRunnerExpanded.toggle() } }
            .id("setting_\(startIndex)")

            if hidRunnerExpanded {
                let runners = RunnerManager.shared.runners
                if runners.isEmpty {
                    infoRow(title: tr("Keine Runner"), subtitle: tr("Keine Runner gefunden"),
                            index: startIndex + 1)
                } else {
                    ForEach(Array(runners.enumerated()), id: \.element.id) { offset, runner in
                        let idx = startIndex + 1 + offset
                        let profileID = runnerHIDProfileIDs[runner.name]
                        let isFocused2 = focusManager.isFocused(section: .allGames, index: idx)

                        HStack(spacing: 16) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.ps4Pink)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(runner.displayName)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                if let pid = profileID,
                                   let profile = remappingService.profiles.first(where: { $0.id == pid }) {
                                    Text(profile.name)
                                        .font(.system(size: 12, weight: .light))
                                        .foregroundColor(.white.opacity(0.5))
                                } else {
                                    Text(verbatim: tr("Kein Profil (Passthrough)"))
                                        .font(.system(size: 12, weight: .light))
                                        .foregroundColor(.white.opacity(0.35))
                                }
                            }

                            Spacer()

                            Picker("", selection: Binding(
                                get: { profileID ?? UUID() },
                                set: { newID in
                                    if newID == UUID() {
                                        runnerHIDProfileIDs.removeValue(forKey: runner.name)
                                    } else {
                                        runnerHIDProfileIDs[runner.name] = newID
                                    }
                                    saveRunnerProfileIDs()
                                    updateItemCount()
                                }
                            )) {
                                Text(verbatim: tr("Kein Profil")).tag(UUID())
                                ForEach(remappingService.profiles) { profile in
                                    Text(profile.name).tag(profile.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 160)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .padding(.leading, 48)
                        .background(isFocused2 ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .id("setting_\(idx)")
                    }
                }
            }
        }
    }

    private func saveRunnerProfileIDs() {
        let dict = Dictionary(uniqueKeysWithValues: runnerHIDProfileIDs.map { ($0.key, $0.value.uuidString) })
        guard let data = try? JSONEncoder().encode(dict) else { return }
        UserDefaults.standard.set(data, forKey: "runnerHIDProfileIDs")
    }

    // MARK: - Button Remapping (Existing)

    private func buttonRemappingSection(startIndex: Int) -> some View {
        Group {
            let isFocused = focusManager.isFocused(section: .allGames, index: startIndex)
            HStack(spacing: 16) {
                Image(systemName: "arrow.triangle.swap")
                    .font(.system(size: 24))
                    .foregroundColor(.ps4Pink)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: tr("Button-Remapping (Global)"))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                    Text(verbatim: trf("%d aktive Zuordnungen", remappingManager.mappings.count))
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(.white.opacity(0.5))
                }

                Spacer()

                Image(systemName: remappingExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(isFocused ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.spring(response: 0.3)) { remappingExpanded.toggle() } }
            .id("setting_\(startIndex)")

            if remappingExpanded {
                ForEach(Array(remappingManager.mappings.enumerated()), id: \.element.id) { offset, mapping in
                    let idx = startIndex + 1 + offset
                    let srcName = extendedGamepadButtons.first(where: { $0.id == mapping.sourceID })?.displayName ?? mapping.sourceID
                    let tgtName = extendedGamepadButtons.first(where: { $0.id == mapping.targetID })?.displayName ?? mapping.targetID
                    let isFocused2 = focusManager.isFocused(section: .allGames, index: idx)
                    HStack(spacing: 16) {
                        Toggle("", isOn: Binding(
                            get: { mapping.isActive },
                            set: { _ in remappingManager.toggle(mapping) }
                        ))
                        .toggleStyle(.switch)
                        .tint(.ps4Pink)
                        .labelsHidden()

                        Text(srcName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 50, alignment: .trailing)

                        Image(systemName: "arrow.right")
                            .foregroundColor(.white.opacity(0.4))

                        Text(tgtName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 50, alignment: .leading)

                        Spacer()

                        Circle()
                            .fill(mapping.isActive ? Color.green : Color.white.opacity(0.2))
                            .frame(width: 10, height: 10)

                        Button {
                            remappingManager.remove(mapping)
                            updateItemCount()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .padding(.leading, 48)
                    .background(isFocused2 ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .id("setting_\(idx)")
                }

                // Add Button
                let addIdx = startIndex + 1 + remappingManager.mappings.count
                let isAddFocused = focusManager.isFocused(section: .allGames, index: addIdx)
                HStack(spacing: 16) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.ps4Pink)
                        .frame(width: 24)

                    Text(verbatim: tr("Neues Mapping hinzufügen"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .padding(.leading, 64)
                .background(isAddFocused ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
                .onTapGesture { showAddRemappingSheet = true }
                .id("setting_\(addIdx)")
            }
        }
        .sheet(isPresented: $showAddRemappingSheet) {
            addRemappingSheet
        }
    }

    @State private var showAddRemappingSheet = false
    @State private var newSource = "buttonA"
    @State private var newTarget = "buttonX"

    private var addRemappingSheet: some View {
        VStack(spacing: 24) {
            Text(verbatim: tr("Neues Button-Mapping"))
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)

            Text(verbatim: tr("Wähle Quelle und Ziel-Button"))
                .font(.system(size: 18, weight: .light))
                .foregroundColor(.white.opacity(0.6))

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: tr("Quelle (drückst du)"))
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundColor(.ps4Pink)

                    Picker("", selection: $newSource) {
                        ForEach(extendedGamepadButtons) { btn in
                            HStack {
                                Image(systemName: categoryIcon(btn.category))
                                Text(btn.displayName)
                            }
                            .tag(btn.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                }

                Image(systemName: "arrow.down")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.4))

                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: tr("Ziel (soll ausgelöst werden)"))
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundColor(.ps4Pink)

                    Picker("", selection: $newTarget) {
                        ForEach(extendedGamepadButtons.filter { $0.id != newSource }) { btn in
                            HStack {
                                Image(systemName: categoryIcon(btn.category))
                                Text(btn.displayName)
                            }
                            .tag(btn.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(32)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            HStack(spacing: 20) {
                Button(tr("Abbrechen")) { showAddRemappingSheet = false }
                    .buttonStyle(ConsoleButtonStyle(color: .white.opacity(0.2)))
                Button(tr("Hinzufügen")) {
                    remappingManager.add(source: newSource, target: newTarget)
                    showAddRemappingSheet = false
                    updateItemCount()
                }
                .buttonStyle(ConsoleButtonStyle(color: .ps4Pink))
                .disabled(newSource == newTarget)
            }
        }
        .padding(40)
        .frame(width: 480)
        .background(Color.black.opacity(0.95))
    }

    private func categoryIcon(_ category: ButtonDefinition.ButtonCategory) -> String {
        switch category {
        case .face:      return "circle.fill"
        case .shoulder:  return "rectangle.fill"
        case .trigger:   return "rectangle.3.group.fill"
        case .dpad:      return "plus.square.fill"
        case .thumbstick: return "circle.circle.fill"
        case .system:    return "gearshape.fill"
        }
    }

    // MARK: - Confirm / Back Handling

    private func handleBack() {
        if uiNavExpanded {
            withAnimation(.spring(response: 0.3)) { uiNavExpanded = false }
            return
        }
        if uiCustomExpanded {
            withAnimation(.spring(response: 0.3)) { uiCustomExpanded = false }
            return
        }
        if hidRunnerExpanded {
            withAnimation(.spring(response: 0.3)) { hidRunnerExpanded = false }
            return
        }
        if remappingExpanded {
            withAnimation(.spring(response: 0.3)) { remappingExpanded = false }
            return
        }
        onBack()
    }

    private func handleConfirm(section: ConsoleSection, index: Int) {
        guard section == .allGames else { return }

        let tEnd = toggleEnd
        let cEnd = controllerEnd
        let uEnd = uiNavEnd
        let hEnd = hidRunnerEnd
        let mEnd = mappingEnd

        // Toggle-Bereich [0, tEnd)
        if index < tEnd {
            guard index < toggleItems.count else { return }
            toggleItems[index].toggle.wrappedValue.toggle()
            return
        }

        // Controller-Bereich [tEnd, cEnd)
        if index >= tEnd && index < cEnd {
            return
        }

        // UI Navigation [cEnd, uEnd)
        if index >= cEnd && index < uEnd {
            handleUINavigationConfirm(localIndex: index - cEnd)
            return
        }

        // HID Runner [uEnd, hEnd)
        if index >= uEnd && index < hEnd {
            let local = index - uEnd
            if local == 0 {
                withAnimation(.spring(response: 0.3)) { hidRunnerExpanded.toggle() }
                updateItemCount()
            }
            return
        }

        // Remapping [hEnd, mEnd)
        if index >= hEnd && index < mEnd {
            let local = index - hEnd
            if local == 0 {
                withAnimation(.spring(response: 0.3)) { remappingExpanded.toggle() }
                updateItemCount()
            } else if local <= remappingManager.mappings.count {
                let idx = local - 1
                guard idx < remappingManager.mappings.count else { return }
                remappingManager.toggle(remappingManager.mappings[idx])
            } else {
                showAddRemappingSheet = true
            }
            return
        }

        // About-Index (mEnd)
        if index == mEnd { return }
        // Back-to-Desktop (mEnd + 1)
        if index == mEnd + 1 { onExitDesktop?(); return }
    }

    private func handleUINavigationConfirm(localIndex: Int) {
        if localIndex == 0 {
            withAnimation(.spring(response: 0.3)) { uiNavExpanded.toggle() }
            updateItemCount()
            return
        }
        guard uiNavExpanded else { return }

        // Auto-Detection Toggle is at localIndex 1
        if localIndex == 1 {
            layoutService.autoDetectionEnabled.toggle()
            layoutService.refreshDetectedLayouts()
            return
        }

        // Controller layouts
        let controllerCount = controllerManager.connectedControllers.count
        let autoIdx = 1
        let layoutStart = autoIdx + 1

        if localIndex >= layoutStart && localIndex < layoutStart + controllerCount {
            return // Layout picker handles change via Binding
        }

        // Custom mapping header
        let customHeaderIdx = layoutStart + controllerCount
        if localIndex == customHeaderIdx {
            withAnimation(.spring(response: 0.3)) { uiCustomExpanded.toggle() }
            updateItemCount()
            return
        }

        // Custom mapping items
        if uiCustomExpanded {
            let customStart = customHeaderIdx + 1
            let customCount = layoutService.customMappings.count
            let subLocal = localIndex - customStart
            if subLocal >= 0 && subLocal < customCount {
                let mappings = layoutService.customMappings
                guard subLocal < mappings.count else { return }
                layoutService.toggleCustomMapping(action: mappings[subLocal].action)
                return
            }
            if subLocal == customCount {
                showCustomUIMappingSheet = true
                return
            }
            if subLocal == customCount + 1 {
                layoutService.resetCustomMappings()
                updateItemCount()
                return
            }
        }
    }

    private func updateItemCount() {
        let baseItems = toggleItems.count + max(controllerManager.connectedControllers.count, 1)
        let uiNavItems = uiNavCount
        let hidItems = 1 + (hidRunnerExpanded ? runnerCount : 0)
        let remappingItems = 1 + (remappingExpanded ? remappingManager.mappings.count + 1 : 0)
        // +1 für About, +1 für Back-to-Desktop
        focusManager.itemCountInSection = baseItems + uiNavItems + hidItems + remappingItems + 2
    }

    // MARK: - Rows (existing styles)

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
            Spacer()
        }
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    private func toggleRow(icon: String, title: String, subtitle: String, toggle: Binding<Bool>, index: Int) -> some View {
        let isFocused = focusManager.isFocused(section: .allGames, index: index)
        return HoverReader { isHovered in
            let highlighted = isFocused || isHovered
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(.ps4Pink)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                Toggle("", isOn: toggle)
                    .toggleStyle(.switch)
                    .tint(.ps4Pink)
                    .labelsHidden()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(highlighted ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .id("setting_\(index)")
    }

    private func infoRow(title: String, subtitle: String, index: Int) -> some View {
        let isFocused = focusManager.isFocused(section: .allGames, index: index)
        return HStack(spacing: 16) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(.ps4Pink)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 18, weight: .medium)).foregroundColor(.white)
                Text(subtitle).font(.system(size: 14, weight: .light)).foregroundColor(.white.opacity(0.5))
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(isFocused ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .id("setting_\(index)")
    }

    private func desktopExitRow(index: Int) -> some View {
        let isFocused = focusManager.isFocused(section: .allGames, index: index)
        return HoverReader { isHovered in
            let highlighted = isFocused || isHovered
            HStack(spacing: 16) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 24))
                    .foregroundColor(.ps4Pink)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: tr("Zurück zum Desktop"))
                        .font(.system(size: 18, weight: .medium)).foregroundColor(.white)
                    Text(verbatim: tr("Console-Modus schließen und zur Desktop-App wechseln"))
                        .font(.system(size: 14, weight: .light)).foregroundColor(.white.opacity(0.5))
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(highlighted ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .onTapGesture { onExitDesktop?() }
        }
        .id("setting_\(index)")
    }

    private func controllerRow(info: ControllerManager.ControllerInfo, index: Int) -> some View {
        let isFocused = focusManager.isFocused(section: .allGames, index: index)
        return HStack(spacing: 16) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 24))
                .foregroundColor(.ps4Pink)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(info.vendorName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                if let battery = info.batteryLevel, battery > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "battery.100.fill").font(.system(size: 12))
                        Text("\(Int(battery * 100))%").font(.system(size: 14, weight: .light))
                    }
                    .foregroundColor(.green)
                }
            }
            Spacer()
            Circle().fill(Color.green).frame(width: 10, height: 10)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(isFocused ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .id("setting_\(index)")
    }
}

// MARK: - SettingsToggleItem

private struct SettingsToggleItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
    let toggle: Binding<Bool>
}

// MARK: - ConsoleButtonStyle

public struct ConsoleButtonStyle: ButtonStyle {
    let color: Color

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .semibold))
            .padding(.vertical, 14)
            .padding(.horizontal, 32)
            .background(configuration.isPressed ? color.opacity(0.6) : color)
            .foregroundColor(.white)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2), value: configuration.isPressed)
    }
}

// MARK: - HoverReader

private struct HoverReader<Content: View>: View {
    @State var isHovered = false
    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        content(isHovered)
            .onHover { isHovered = $0 }
    }
}
