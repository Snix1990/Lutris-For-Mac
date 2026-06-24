import SwiftUI
import LutrisForMacCore

// ================================================================
// ConsoleButtonMappingView.swift
// ================================================================
// Eigenständige View für das Button-Remapping in den Console-
// Einstellungen. Verwaltet expandierte Liste, Mapping-Items,
// Add-Sheet und interne Navigation.
// ================================================================

public struct ConsoleButtonMappingView: View {
    @ObservedObject private var remappingManager = RemappingManager.shared
    @EnvironmentObject private var focusManager: ConsoleFocusManager

    @Binding var expanded: Bool
    @State private var showAddMapping = false
    @State private var newSource = "buttonA"
    @State private var newTarget = "buttonX"

    let startIndex: Int

    public init(expanded: Binding<Bool>, startIndex: Int = 0) {
        self._expanded = expanded
        self.startIndex = startIndex
    }

    private var mappingItems: [(name: String, id: UUID, source: String, target: String, isActive: Bool, idx: Int)] {
        remappingManager.mappings.enumerated().map { idx, mapping in
            let srcName = extendedGamepadButtons.first(where: { $0.id == mapping.sourceID })?.displayName ?? mapping.sourceID
            let tgtName = extendedGamepadButtons.first(where: { $0.id == mapping.targetID })?.displayName ?? mapping.targetID
            return (name: srcName, id: mapping.id, source: srcName, target: tgtName, isActive: mapping.isActive, idx: idx)
        }
    }

    private var totalItems: Int {
        1 + (expanded ? mappingItems.count + 1 : 0)
    }

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
                ForEach(Array(mappingItems.enumerated()), id: \.element.id) { offset, item in
                    itemRow(source: item.source, target: item.target,
                            isActive: item.isActive, mappingIdx: item.idx)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .padding(.leading, 48)
                        .background(itemHighlighted(offset: offset) ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .contentShape(Rectangle())
                        .onTapGesture { remappingManager.toggle(remappingManager.mappings[item.idx]) }
                        .id("setting_\(startIndex + 1 + offset)")
                }

                addRow
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .padding(.leading, 48)
                    .background(addHighlighted ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                    .onTapGesture { showAddMapping = true }
                    .id("setting_\(startIndex + 1 + mappingItems.count)")
            }
        }
        .sheet(isPresented: $showAddMapping) { addMappingSheet }
        .onChange(of: expanded) { _, _ in notifyFocusChange() }
        .onChange(of: remappingManager.mappings.count) { _, _ in notifyFocusChange() }
    }

    private func notifyFocusChange() {
        focusManager.itemCountInSection = totalItems
    }

    private func toggleExpanded() {
        withAnimation(.spring(response: 0.3)) { expanded.toggle() }
    }

    // MARK: - Focus

    private var headerHighlighted: Bool {
        let idx = startIndex
        return focusManager.isFocused(section: .allGames, index: idx)
    }

    private func itemHighlighted(offset: Int) -> Bool {
        let idx = startIndex + 1 + offset
        return focusManager.isFocused(section: .allGames, index: idx)
    }

    private var addHighlighted: Bool {
        let idx = startIndex + 1 + mappingItems.count
        return focusManager.isFocused(section: .allGames, index: idx)
    }

    // MARK: - Confirm Handler (wird von ConsoleSettingsView aufgerufen)

    public func handleConfirm(at index: Int) {
        guard index >= startIndex && index < startIndex + totalItems else { return }
        let local = index - startIndex
        if local == 0 {
            toggleExpanded()
        } else if local <= mappingItems.count {
            let idx = local - 1
            guard idx < remappingManager.mappings.count else { return }
            remappingManager.toggle(remappingManager.mappings[idx])
        } else {
            showAddMapping = true
        }
    }

    // MARK: - Back Handler (wird von ConsoleSettingsView aufgerufen)

    public func handleBack() -> Bool {
        guard expanded else { return false }
        withAnimation(.spring(response: 0.3)) { expanded = false }
        return true
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 16) {
            Image(systemName: "arrow.triangle.swap")
                .font(.system(size: 24))
                .foregroundColor(.ps4Pink)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: tr("Button-Mapping"))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                Text(verbatim: trf("%d aktive Zuordnungen", remappingManager.mappings.count))
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    // MARK: - Item Row

    private func itemRow(source: String, target: String, isActive: Bool, mappingIdx: Int) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 18))
                .foregroundColor(isActive ? .ps4Pink : .white.opacity(0.3))
                .frame(width: 32)

            Text(source)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(isActive ? .white : .white.opacity(0.4))
                .frame(width: 60, alignment: .trailing)

            Image(systemName: "arrow.right")
                .foregroundColor(.white.opacity(0.4))

            Text(target)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(isActive ? .white : .white.opacity(0.4))
                .frame(width: 60, alignment: .leading)

            Spacer()

            Circle()
                .fill(isActive ? Color.green : Color.white.opacity(0.2))
                .frame(width: 10, height: 10)

            Button {
                guard mappingIdx < remappingManager.mappings.count else { return }
                remappingManager.remove(remappingManager.mappings[mappingIdx])
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Add Row

    private var addRow: some View {
        HStack(spacing: 16) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(.ps4Pink)
                .frame(width: 32)

            Text(verbatim: tr("Neues Mapping hinzufügen"))
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)

            Spacer()
        }
    }

    // MARK: - Sheet

    private var addMappingSheet: some View {
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
                Button(tr("Abbrechen")) { showAddMapping = false }
                    .buttonStyle(ConsoleButtonStyle(color: .white.opacity(0.2)))
                Button(tr("Hinzufügen")) {
                    remappingManager.add(source: newSource, target: newTarget)
                    showAddMapping = false
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
}
