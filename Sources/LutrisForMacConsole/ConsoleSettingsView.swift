import SwiftUI
import GameController
import LutrisForMacCore

// ================================================================
// ConsoleSettingsView.swift – Refactored
// ================================================================
// Controller-navigierbare Einstellungen.
// Abschnitte:
//   EINSTELLUNGEN (Toggles)
//   CONTROLLER SETTINGS (Navigation zu ConsoleControllerSettingsView)
//   ABOUT
// ================================================================

public struct ConsoleSettingsView: View {
    let onBack: () -> Void
    let onExitDesktop: (() -> Void)?
    let onOpenControllerSettings: (() -> Void)?
    let consoleState: ConsoleState

    @EnvironmentObject private var focusManager: ConsoleFocusManager

    public init(onBack: @escaping () -> Void, onExitDesktop: (() -> Void)? = nil, onOpenControllerSettings: (() -> Void)? = nil, consoleState: ConsoleState) {
        self.onBack = onBack
        self.onExitDesktop = onExitDesktop
        self.onOpenControllerSettings = onOpenControllerSettings
        self.consoleState = consoleState
    }

    @AppStorage("console_discord_rpc") private var discordRPC = true
    @AppStorage("console_cloud_sync") private var cloudSync = true
    @AppStorage("console_auto_launch") private var autoLaunch = false
    @AppStorage("console_low_power_mode") private var lowPowerMode = false

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

    // ── Action Dispatch (Single Source of Truth, delegiert an testbaren Index-Logic) ──

    private typealias SettingAction = ConsoleSettingsIndexLogic.SettingAction

    private func actionForIndex(_ index: Int) -> SettingAction? {
        ConsoleSettingsIndexLogic.actionForIndex(
            index,
            toggleCount: toggleItems.count,
            controllerSettingsAvailable: onOpenControllerSettings != nil
        )
    }

    private var itemCountFromActions: Int {
        ConsoleSettingsIndexLogic.itemCount(
            toggleCount: toggleItems.count,
            controllerSettingsAvailable: onOpenControllerSettings != nil
        )
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

                    // ── Controller Settings (Navigation) ──
                    if onOpenControllerSettings != nil {
                        sectionHeader(tr("CONTROLLER"))
                        controllerSettingsNavRow(index: toggleItems.count)
                    }

                    // ── About ──
                    sectionHeader(tr("ABOUT"))
                    let aboutIdx = toggleItems.count + (onOpenControllerSettings != nil ? 1 : 0)
                    infoRow(title: tr("LutrisForMac Console"), subtitle: tr("Version 1.0.0"),
                            index: aboutIdx)
                    desktopExitRow(index: aboutIdx + 1)
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
    }

    // MARK: - Controller Settings Navigation Row

    private func controllerSettingsNavRow(index: Int) -> some View {
        let isFocused = focusManager.isFocused(section: .allGames, index: index)
        return HStack(spacing: 16) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 24))
                .foregroundColor(.ps4Pink)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: tr("Controller Settings"))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                let count = ControllerManager.shared.connectedControllers.count
                Text(verbatim: trf("%d Controller verbunden · Layout, HID, Remapping", count))
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(isFocused ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture { onOpenControllerSettings?() }
        .id("setting_\(index)")
    }

    // MARK: - Confirm / Back Handling

    private func handleBack() {
        onBack()
    }

    private func handleConfirm(section: ConsoleSection, index: Int) {
        guard section == .allGames else { return }
        guard let action = actionForIndex(index) else { return }

        switch action {
        case .toggle(let idx):
            guard idx < toggleItems.count else { return }
            toggleItems[idx].toggle.wrappedValue.toggle()

        case .controllerSettings:
            onOpenControllerSettings?()

        case .about:
            break

        case .desktopExit:
            onExitDesktop?()
        }
    }

    private func updateItemCount() {
        focusManager.itemCountInSection = itemCountFromActions
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
}

// MARK: - SettingsToggleItem

private struct SettingsToggleItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
    let toggle: Binding<Bool>
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
