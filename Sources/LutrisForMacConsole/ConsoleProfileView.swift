import SwiftUI
import LutrisForMacCore

// ================================================================
// ConsoleProfileView.swift
// ================================================================
// Plattform‑Profile‑Picker für die Console‑Einstellungen.
// Listet alle Built‑in‑ + User‑Profile, ein Tippen aktiviert sofort.
// ================================================================

public struct ConsoleProfileView: View {
    @ObservedObject private var remappingService = RemappingService.shared
    @EnvironmentObject private var focusManager: ConsoleFocusManager

    @Binding var expanded: Bool

    let startIndex: Int

    @AppStorage("console_selected_profile_id")
    private var selectedProfileIDString: String = ""

    public init(expanded: Binding<Bool>, startIndex: Int = 0) {
        self._expanded = expanded
        self.startIndex = startIndex
    }

    /// Der aktuell ausgewählte Profil‑Name
    private var selectedProfileName: String {
        guard let id = selectedProfileUUID,
              let profile = remappingService.profiles.first(where: { $0.id == id }) else {
            return tr("Kein Profil")
        }
        return profile.name
    }

    private var selectedProfileUUID: UUID? {
        UUID(uuidString: selectedProfileIDString)
    }

    private var profiles: [PlatformMappingProfile] {
        remappingService.profiles
    }

    private var profileCount: Int {
        expanded ? profiles.count : 0
    }

    private func isSelected(_ profile: PlatformMappingProfile) -> Bool {
        profile.id == selectedProfileUUID
    }

    private func select(_ profile: PlatformMappingProfile) {
        selectedProfileIDString = profile.id.uuidString
        withAnimation(.spring(response: 0.3)) { expanded = false }
        apply(profile)
    }

    private func apply(_ profile: PlatformMappingProfile) {
        // Profile + aktuelle Custom‑Mappings kombinieren
        let customMappings = RemappingManager.shared.activeMappings()
        var allMappings = profile.mappings
        for cm in customMappings where cm.isActive {
            if let idx = allMappings.firstIndex(where: { $0.sourceID == cm.sourceID }) {
                allMappings[idx] = cm  // Custom überschreibt
            } else {
                allMappings.append(cm)
            }
        }
        // Update RemappingManager with merged mappings for navigation.
    RemappingManager.shared.mappings = allMappings
    RemappingManager.shared.save()
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 2) {
                headerRow
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(headerHighlighted ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                    .onTapGesture { toggleExpanded() }
                    .id("setting_\(startIndex)")

            if expanded {
                ForEach(Array(profiles.enumerated()), id: \.element.id) { offset, profile in
                    profileRow(profile: profile, offset: offset)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .padding(.leading, 48)
                        .background(profileHighlighted(offset: offset) ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .contentShape(Rectangle())
                        .onTapGesture { select(profile) }
                        .id("setting_\(startIndex + 1 + offset)")
                }
            }
        }
        .onAppear {
            guard selectedProfileIDString.isEmpty else { return }
            // Erstes verfügbares Profil als Default (plattform-unabhängig)
            if let first = profiles.first {
                select(first)
            }
        }
    }

    // MARK: - Focus

    private var headerHighlighted: Bool {
        focusManager.isFocused(section: .allGames, index: startIndex)
    }

    private func profileHighlighted(offset: Int) -> Bool {
        focusManager.isFocused(section: .allGames, index: startIndex + 1 + offset)
    }

    private func toggleExpanded() {
        withAnimation(.spring(response: 0.3)) { expanded.toggle() }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 16) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 24))
                .foregroundColor(.ps4Pink)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: tr("Controller‑Layout"))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                Text(selectedProfileName)
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    // MARK: - Profile Row

    private func profileRow(profile: PlatformMappingProfile, offset: Int) -> some View {
        let selected = isSelected(profile)
        return HStack(spacing: 16) {
            platformIcon(profile.platform)
                .font(.system(size: 22))
                .foregroundColor(selected ? .ps4Pink : .white.opacity(0.4))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(selected ? .white : .white.opacity(0.6))
                Text(buttonSummary(profile))
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(.white.opacity(0.35))
            }

            Spacer()

            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.ps4Pink)
            }
        }
    }

    // MARK: - Controller Actions (wird von ConsoleSettingsView aufgerufen)

    public func handleConfirm(at index: Int) {
        guard index >= startIndex && index < startIndex + 1 + profileCount else { return }
        let local = index - startIndex
        if local == 0 {
            toggleExpanded()
        } else {
            let profileIdx = local - 1
            guard profileIdx < profiles.count else { return }
            select(profiles[profileIdx])
        }
    }

    public func handleBack() -> Bool {
        guard expanded else { return false }
        withAnimation(.spring(response: 0.3)) { expanded = false }
        return true
    }

    // MARK: - Helpers

    private func platformIcon(_ platform: ControllerPlatform) -> Image {
        switch platform {
        case .nintendo:     return Image(systemName: "n.square.fill")
        case .playstation:  return Image(systemName: "p.square.fill")
        case .xbox:         return Image(systemName: "x.square.fill")
        case .steam:        return Image(systemName: "s.square.fill")
        case .custom:       return Image(systemName: "gearshape.fill")
        }
    }

    private func buttonSummary(_ profile: PlatformMappingProfile) -> String {
        let swaps = profile.mappings.filter { $0.isActive }
        if swaps.isEmpty { return tr("Standard (keine Änderungen)") }
        return swaps.map { m in
            let src = extendedGamepadButtons.first(where: { $0.id == m.sourceID })?.displayName ?? m.sourceID
            let dst = extendedGamepadButtons.first(where: { $0.id == m.targetID })?.displayName ?? m.targetID
            return "\(src)↔\(dst)"
        }.joined(separator: ", ")
    }
}
