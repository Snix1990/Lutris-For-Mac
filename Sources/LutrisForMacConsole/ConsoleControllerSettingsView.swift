import SwiftUI
import GameController
import LutrisForMacCore

public struct ConsoleControllerSettingsView: View {
    let onBack: () -> Void
    let consoleState: ConsoleState

    @ObservedObject private var controllerManager = ControllerManager.shared
    @ObservedObject private var layoutService = UIControllerLayoutService.shared
    @ObservedObject private var remappingManager = RemappingManager.shared
    @ObservedObject private var remappingService = RemappingService.shared
    @ObservedObject private var runnerManager = RunnerManager.shared
    @EnvironmentObject private var focusManager: ConsoleFocusManager

    @State private var remappingExpanded = false
    @State private var showAddRemappingSheet = false
    @State private var newSource = "buttonA"
    @State private var newTarget = "buttonX"
    @State private var runnerHIDProfileIDs: [String: UUID] = [:]

    @State private var capturingAction: UIAction? = nil
    @State private var profilePickerRunner: String? = nil

    private var totalItemCount: Int {
        var count = 1
        count += max(controllerManager.connectedControllers.count, 1)
        count += UIAction.allCases.count
        count += runnerManager.runners.count
        count += 1
        if remappingExpanded {
            count += remappingManager.mappings.count
            count += 1
        }
        return count
    }

    public init(onBack: @escaping () -> Void, consoleState: ConsoleState) {
        self.onBack = onBack
        self.consoleState = consoleState
    }

    public var body: some View {
        ZStack {
            RetroWaveBackground(speedMultiplier: 1, lowPowerMode: false)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 2) {
                            ScrollController().frame(width: 0, height: 0)

                            sectionHeader(tr("CONTROLLER"))
                            controllerListSection

                            sectionHeader(tr("UI NAVIGATION"))
                            uiNavigationSection

                            sectionHeader(tr("VIRTUAL HID FOR GAMES"))
                            hidForGamesSection

                            sectionHeader(tr("BUTTON-REMAP"))
                            buttonRemappingSection
                        }
                        .padding(.horizontal, 60)
                        .padding(.vertical, 40)
                    }
                    .onChange(of: focusManager.focusedIndex) { _, newIndex in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo("ctrl_setting_\(newIndex)", anchor: .center)
                        }
                    }
                }
            }

            // Profile Picker Overlay
            if let runnerName = profilePickerRunner {
                RunnerProfilePickerView(
                    runnerName: runnerName,
                    currentProfileID: runnerHIDProfileIDs[runnerName],
                    profiles: remappingService.profiles,
                    onSelect: { profileID in
                        if let id = profileID {
                            runnerHIDProfileIDs[runnerName] = id
                        } else {
                            runnerHIDProfileIDs.removeValue(forKey: runnerName)
                        }
                        saveRunnerProfileIDs()
                        profilePickerRunner = nil
                    },
                    onBack: {
                        profilePickerRunner = nil
                    },
                    parentFocusManager: focusManager
                )
                .transition(.opacity)
            }
        }
        .modifier(ControllerNavigationModifier(
            consoleState: consoleState,
            focusManager: focusManager,
            gridColumns: 1,
            onConfirm: { section, index in handleConfirm(index: index) },
            onBack: { handleBack() },
            onSearchToggle: { },
            onUpdateFocusState: { },
            onSearchActiveChanged: { _ in }
        ))
        .onAppear {
            focusManager.isLinearMode = true
            focusManager.activeSection = .allGames
            focusManager.focusedIndex = 0
            focusManager.itemCountInSection = totalItemCount
            loadRunnerProfileIDs()
        }
        .onDisappear {
            focusManager.isLinearMode = false
            ControllerNavigationSystem.shared.cancelCapture()
            capturingAction = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .consoleBack)) { _ in
            if profilePickerRunner != nil {
                profilePickerRunner = nil
                return
            }
            if capturingAction != nil {
                capturingAction = nil
                ControllerNavigationSystem.shared.cancelCapture()
            }
        }
    }

    private var headerBar: some View {
        HStack {
            Button {
                handleBack()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                    Text(verbatim: tr("Controller Settings"))
                        .font(.system(size: 24, weight: .bold))
                }
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(verbatim: trf("%d verbunden", controllerManager.connectedControllers.count))
                .font(.system(size: 16, weight: .light))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 20)
    }

    // MARK: - Controller List

    private var controllerListSection: some View {
        Group {
            if controllerManager.connectedControllers.isEmpty {
                infoRow(title: tr("Kein Controller"), subtitle: tr("Verbinde einen Controller über Bluetooth oder USB"), index: 1)
            } else {
                ForEach(Array(controllerManager.connectedControllers.enumerated()), id: \.offset) { idx, info in
                    controllerRow(info: info, index: 1 + idx)
                }
            }
        }
    }

    // MARK: - UI Navigation (Keybinding)

    private var uiNavigationSection: some View {
        Group {
            let startIdx = 1 + max(controllerManager.connectedControllers.count, 1)
            ForEach(Array(UIAction.allCases.enumerated()), id: \.element) { offset, action in
                let idx = startIdx + offset
                let isFocused = focusManager.isFocused(section: .allGames, index: idx)
                let isCapturing = capturingAction == action
                let currentBinding = layoutService.effectivePhysicalButton(
                    for: action,
                    layout: detectedLayout
                )

                HStack(spacing: 16) {
                    Image(systemName: isCapturing ? "record.circle" : "circlebadge")
                        .font(.system(size: 18))
                        .foregroundColor(isCapturing ? .red : .ps4Pink)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.displayName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                        if isCapturing {
                            Text(verbatim: tr("Drücke einen Button…"))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.red)
                        } else {
                            Text(currentBinding.displayName)
                                .font(.system(size: 12, weight: .light))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }

                    Spacer()

                    if isCapturing {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(isFocused ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
                .onTapGesture { startCapture(action: action) }
                .id("ctrl_setting_\(idx)")
            }
        }
    }

    private var detectedLayout: UIControllerLayout {
        if let first = GCController.controllers().first {
            let key = layoutService.controllerTypeKey(for: first)
            return layoutService.detectedLayouts[key] ?? .generic
        }
        return .generic
    }

    private func startCapture(action: UIAction) {
        guard capturingAction == nil else { return }
        capturingAction = action
        ControllerNavigationSystem.shared.captureNextButton { [layoutService] physical in
            layoutService.setCustomMapping(action: action, physicalButton: physical)
            Task { @MainActor in
                self.capturingAction = nil
            }
        }
    }

    // MARK: - Virtual HID for Games (Runner-Profile)

    private var hidForGamesSection: some View {
        Group {
            let startIdx = calculateHidStartIndex()
            if runnerManager.runners.isEmpty {
                infoRow(title: tr("Keine Runner"), subtitle: tr("Keine Runner gefunden"),
                        index: startIdx)
            } else {
                ForEach(Array(runnerManager.runners.enumerated()), id: \.element.id) { offset, runner in
                    let idx = startIdx + offset
                    let profileID = runnerHIDProfileIDs[runner.name]
                    let isFocused = focusManager.isFocused(section: .allGames, index: idx)

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

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(isFocused ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                    .onTapGesture { profilePickerRunner = runner.name }
                    .id("ctrl_setting_\(idx)")
                }
            }
        }
    }

    private func calculateHidStartIndex() -> Int {
        var idx = 1 + max(controllerManager.connectedControllers.count, 1)
        idx += UIAction.allCases.count
        return idx
    }

    // MARK: - Button Remapping

    private var buttonRemappingSection: some View {
        Group {
            let startIdx = calculateRemappingStartIndex()
            let isFocused = focusManager.isFocused(section: .allGames, index: startIdx)
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
            .id("ctrl_setting_\(startIdx)")

            if remappingExpanded {
                ForEach(Array(remappingManager.mappings.enumerated()), id: \.element.id) { offset, mapping in
                    let idx = startIdx + 1 + offset
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
                    .id("ctrl_setting_\(idx)")
                }

                let addIdx = startIdx + 1 + remappingManager.mappings.count
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
                .id("ctrl_setting_\(addIdx)")
            }
        }
        .sheet(isPresented: $showAddRemappingSheet) {
            addRemappingSheet
        }
    }

    private func calculateRemappingStartIndex() -> Int {
        var idx = 1 + max(controllerManager.connectedControllers.count, 1)
        idx += UIAction.allCases.count
        idx += runnerManager.runners.count
        return idx
    }

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
                }
                .buttonStyle(ConsoleButtonStyle(color: .ps4Pink))
                .disabled(newSource == newTarget)
            }
        }
        .padding(40)
        .frame(width: 480)
        .background(Color.black.opacity(0.95))
    }

    // MARK: - Confirm / Back

    private func handleBack() {
        if profilePickerRunner != nil {
            profilePickerRunner = nil
            return
        }
        if capturingAction != nil {
            capturingAction = nil
            ControllerNavigationSystem.shared.cancelCapture()
            return
        }
        if remappingExpanded { withAnimation(.spring(response: 0.3)) { remappingExpanded = false }; return }
        onBack()
    }

    private func handleConfirm(index: Int) {
        let sections = computeSections()
        guard index < sections.count else { return }
        switch sections[index] {
        case .header:
            break
        case .controllerInfo:
            break
        case .uiNavBinding(let action):
            startCapture(action: action)
        case .hidRunnerItem(let idx):
            guard idx < runnerManager.runners.count else { return }
            profilePickerRunner = runnerManager.runners[idx].name
        case .remappingHeader:
            withAnimation(.spring(response: 0.3)) { remappingExpanded.toggle() }
        case .remappingItem(let idx):
            guard idx < remappingManager.mappings.count else { return }
            remappingManager.toggle(remappingManager.mappings[idx])
        case .remappingAdd:
            showAddRemappingSheet = true
        }
    }

    private enum ControllerSection: Equatable {
        case header
        case controllerInfo(Int)
        case uiNavBinding(UIAction)
        case hidRunnerItem(Int)
        case remappingHeader
        case remappingItem(Int)
        case remappingAdd
    }

    private func computeSections() -> [ControllerSection] {
        var sections: [ControllerSection] = [.header]
        let ctrlCount = max(controllerManager.connectedControllers.count, 1)
        for i in 0..<ctrlCount {
            sections.append(.controllerInfo(i))
        }
        for action in UIAction.allCases {
            sections.append(.uiNavBinding(action))
        }
        for i in 0..<runnerManager.runners.count {
            sections.append(.hidRunnerItem(i))
        }
        sections.append(.remappingHeader)
        if remappingExpanded {
            for i in 0..<remappingManager.mappings.count {
                sections.append(.remappingItem(i))
            }
            sections.append(.remappingAdd)
        }
        return sections
    }

    // MARK: - Rows

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
        .id("ctrl_setting_\(index)")
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
        .id("ctrl_setting_\(index)")
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
}
