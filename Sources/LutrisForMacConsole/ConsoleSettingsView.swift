import SwiftUI
import LutrisForMacCore

// ================================================================
// ConsoleSettingsView.swift
// ================================================================
// Controller-navigierbare Einstellungen.
// D-Pad ↑↓ durch Items, A togglet/selectet, B zurück.
// ================================================================

public struct ConsoleSettingsView: View {
    let onBack: () -> Void
    let onExitDesktop: (() -> Void)?
    let consoleState: ConsoleState

    @ObservedObject private var controllerManager = ControllerManager.shared
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

    @State private var profileExpanded = false
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
    private var profileEnd: Int {
        controllerEnd + 1 + (profileExpanded ? RemappingService.shared.profiles.count : 0)
    }
    private var mappingEnd: Int {
        profileEnd + 1 + (remappingExpanded ? RemappingManager.shared.mappings.count + 1 : 0)
    }

    public init(onBack: @escaping () -> Void) {
        self.onBack = onBack
        self.onExitDesktop = nil
        self.consoleState = ConsoleState()
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

                    // ── Controller‑Layout (Profile) ──
                    let cEnd = controllerEnd
                    ConsoleProfileView(
                        expanded: $profileExpanded,
                        startIndex: cEnd
                    )
                    .environmentObject(focusManager)

                    // ── Button-Mapping ──
                    let pEnd = profileEnd
                    ConsoleButtonMappingView(
                        expanded: $remappingExpanded,
                        startIndex: pEnd
                    )
                    .environmentObject(focusManager)

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
        .onChange(of: profileExpanded) { _, _ in updateItemCount() }
        .onChange(of: remappingExpanded) { _, _ in updateItemCount() }
    }

    private func handleBack() {
        // Prüfe zuerst Sub‑Views (könnten expanded sein)
        if profileExpanded {
            withAnimation(.spring(response: 0.3)) { profileExpanded = false }
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
        let pEnd = profileEnd
        let mEnd = mappingEnd

        // Toggle-Bereich [0, tEnd)
        if index < tEnd {
            guard index < toggleItems.count else { return }
            toggleItems[index].toggle.wrappedValue.toggle()
            return
        }

        // Controller-Bereich [tEnd, cEnd)
        if index >= tEnd && index < cEnd {
            return // Controller-Rows haben keine Confirm-Aktion
        }

        // Profile-Bereich [cEnd, pEnd)
        if index >= cEnd && index < pEnd {
            let local = index - cEnd
            if local == 0 {
                withAnimation(.spring(response: 0.3)) { profileExpanded.toggle() }
            } else {
                let profileIdx = local - 1
                let profiles = RemappingService.shared.profiles
                guard profileIdx < profiles.count else { return }
                selectProfile(profiles[profileIdx])
            }
            return
        }

        // Mapping-Bereich [pEnd, mEnd)
        if index >= pEnd && index < mEnd {
            let local = index - pEnd
            if local == 0 {
                withAnimation(.spring(response: 0.3)) { remappingExpanded.toggle() }
            } else if local <= RemappingManager.shared.mappings.count {
                let idx = local - 1
                guard idx < RemappingManager.shared.mappings.count else { return }
                RemappingManager.shared.toggle(RemappingManager.shared.mappings[idx])
            }
            return
        }

        // About-Index (mEnd)
        if index == mEnd { return }

        // Back-to-Desktop (mEnd + 1)
        if index == mEnd + 1 {
            onExitDesktop?()
            return
        }
    }

    private func selectProfile(_ profile: PlatformMappingProfile) {
        let key = "console_selected_profile_id"
        UserDefaults.standard.set(profile.id.uuidString, forKey: key)
        withAnimation(.spring(response: 0.3)) { profileExpanded = false }
        let customMappings = RemappingManager.shared.activeMappings()
        var allMappings = profile.mappings
        for cm in customMappings where cm.isActive {
            if let idx = allMappings.firstIndex(where: { $0.sourceID == cm.sourceID }) {
                allMappings[idx] = cm
            } else {
                allMappings.append(cm)
            }
        }
        RemappingManager.shared.mappings = allMappings
        RemappingManager.shared.save()
    }

    private func updateItemCount() {
        let baseItems = toggleItems.count + max(controllerManager.connectedControllers.count, 1)
        let profileItems = 1 + (profileExpanded ? RemappingService.shared.profiles.count : 0)
        let mappingItems = 1 + (remappingExpanded ? RemappingManager.shared.mappings.count + 1 : 0)
        // +1 für About-Zeile, +1 für Back-to-Desktop
        focusManager.itemCountInSection = baseItems + profileItems + mappingItems + 2
    }

    // MARK: - Section Header

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

    // MARK: - Toggle Row

    private func toggleRow(icon: String, title: String, subtitle: String,
                           toggle: Binding<Bool>, index: Int) -> some View {
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

    // MARK: - Info Row

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

    // MARK: - Desktop Exit Row

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

    // MARK: - Controller Row

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

// MARK: - SettingsToggleItem

private struct SettingsToggleItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
    let toggle: Binding<Bool>
}
