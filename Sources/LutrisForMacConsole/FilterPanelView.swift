import SwiftUI
import LutrisForMacCore

struct FilterPanelView: View {
    @ObservedObject var consoleState: ConsoleState
    @ObservedObject var focusManager: ConsoleFocusManager
    let availableCategories: [String]
    let availablePlatforms: [String]
    let availableRunners: [String]
    let onClose: () -> Void

    private var flatFilterItems: [FilterPanelView.FilterItem] {
        var items: [FilterPanelView.FilterItem] = []
        for cat in availableCategories {
            items.append(FilterItem(
                kind: .category, label: cat,
                isSelected: consoleState.selectedCategory == cat
            ))
        }
        for plat in availablePlatforms {
            items.append(FilterItem(
                kind: .platform, label: plat,
                isSelected: consoleState.selectedPlatform == plat
            ))
        }
        for run in availableRunners {
            items.append(FilterItem(
                kind: .runner, label: run,
                isSelected: consoleState.selectedRunner == run
            ))
        }
        return items
    }

    private struct FilterItem: Identifiable {
        let id = UUID()
        let kind: FilterKind
        let label: String
        let isSelected: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(verbatim: tr("FILTER"))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                Spacer()

                if consoleState.filterActive {
                    Button(action: {
                        consoleState.clearAllFilters()
                    }) {
                        Text(verbatim: tr("Alle löschen"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.ps4Pink)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            if !availableCategories.isEmpty {
                filterChipRow(
                    kind: .category,
                    items: availableCategories,
                    selected: $consoleState.selectedCategory,
                    onClear: { consoleState.clearCategoryFilter() },
                    startIndex: 0
                )
            }

            if !availablePlatforms.isEmpty {
                filterChipRow(
                    kind: .platform,
                    items: availablePlatforms,
                    selected: $consoleState.selectedPlatform,
                    onClear: { consoleState.clearPlatformFilter() },
                    startIndex: availableCategories.isEmpty ? 0 : availableCategories.count
                )
            }

            if !availableRunners.isEmpty {
                filterChipRow(
                    kind: .runner,
                    items: availableRunners,
                    selected: $consoleState.selectedRunner,
                    onClear: { consoleState.clearRunnerFilter() },
                    startIndex: (availableCategories.isEmpty ? 0 : availableCategories.count)
                        + (availablePlatforms.isEmpty ? 0 : availablePlatforms.count)
                )
            }

            if availableCategories.isEmpty && availablePlatforms.isEmpty && availableRunners.isEmpty {
                HStack {
                    Spacer()
                    Text(verbatim: tr("Keine Filter verfügbar"))
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.vertical, 20)
                    Spacer()
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func filterChipRow(kind: FilterKind, items: [String], selected: Binding<String?>, onClear: @escaping () -> Void, startIndex: Int = 0) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(kind.displayTitle)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                if selected.wrappedValue != nil {
                    Button(action: onClear) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.ps4Pink)
                    }
                    .buttonStyle(.plain)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                        let chipIndex = startIndex + offset
                        let isSelected = selected.wrappedValue == item
                        let isFocused = focusManager.isFocused(section: .filter, index: chipIndex)
                        Button(action: {
                            withAnimation(.spring(response: 0.25)) {
                                if isSelected {
                                    onClear()
                                } else {
                                    selected.wrappedValue = item
                                }
                            }
                        }) {
                            Text(item)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                                .padding(.vertical, 6)
                                .padding(.horizontal, 14)
                                .background(isSelected
                                    ? (isFocused ? Color.ps4Pink.opacity(0.5) : Color.ps4Pink.opacity(0.3))
                                    : (isFocused ? Color.white.opacity(0.2) : Color.white.opacity(0.08)))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(isFocused ? Color.ps4Pink : (isSelected ? Color.ps4Pink : Color.clear), lineWidth: isFocused ? 2 : 1.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
