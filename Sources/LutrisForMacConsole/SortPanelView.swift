import SwiftUI
import LutrisForMacCore

struct SortPanelView: View {
    @ObservedObject var consoleState: ConsoleState
    @ObservedObject var focusManager: ConsoleFocusManager
    let onClose: () -> Void

    private var sortOptions: [SortOption] { SortOption.allCases }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(verbatim: tr("SORTIEREN"))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                Spacer()

                HStack(spacing: 6) {
                    Text(consoleState.sortAscending ? tr("Aufsteigend") : tr("Absteigend"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))

                    Button(action: {
                        withAnimation(.spring(response: 0.25)) {
                            consoleState.sortAscending.toggle()
                        }
                    }) {
                        Image(systemName: consoleState.sortAscending
                              ? "arrow.up.circle.fill"
                              : "arrow.down.circle.fill")
                            .font(.system(size: 20))
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(sortOptions.enumerated()), id: \.offset) { offset, option in
                        let isSelected = consoleState.sortOption == option
                        let isFocused = focusManager.isFocused(section: .filter, index: offset)
                        Button(action: {
                            withAnimation(.spring(response: 0.25)) {
                                consoleState.sortOption = option
                            }
                        }) {
                            Text(option.displayName)
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
}
