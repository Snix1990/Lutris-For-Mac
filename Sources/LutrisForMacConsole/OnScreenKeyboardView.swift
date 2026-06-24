import SwiftUI
import LutrisForMacCore

// ================================================================
// OnScreenKeyboardView.swift
// ================================================================
// Controller-bedienbare On-Screen-Tastatur für den Console-Mode.
// Zeigt je nach page Buchstaben oder Sonderzeichen an.
// Shift-Taste toggle Groß-/Kleinschreibung (highlighted wenn aktiv).
// L1/R1 wechseln die Seite. Navigation via D-Pad / L-Stick.
// ================================================================

public struct OnScreenKeyboardView: View {
    let keyboardRows: [[String]]
    let focusedIndex: Int         // Flat index im search-section (0=searchBar, 1+ = keys)
    let keyboardPage: Int
    let isShifted: Bool
    let layoutType: KeyboardLayoutType
    let onKeyPressed: (String) -> Void

    @State private var pageLabelOpacity: Double = 0

    public init(
        keyboardRows: [[String]],
        focusedIndex: Int,
        keyboardPage: Int,
        isShifted: Bool = false,
        layoutType: KeyboardLayoutType = .qwerty,
        onKeyPressed: @escaping (String) -> Void
    ) {
        self.keyboardRows = keyboardRows
        self.focusedIndex = focusedIndex
        self.keyboardPage = keyboardPage
        self.isShifted = isShifted
        self.layoutType = layoutType
        self.onKeyPressed = onKeyPressed
    }

    public var body: some View {
        VStack(spacing: 12) {
            // ── Page Indicator ──
            Text(pageLabel)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
                .opacity(pageLabelOpacity)
                .onAppear {
                    withAnimation(.easeIn(duration: 0.4)) {
                        pageLabelOpacity = 1
                    }
                }

            // ── Keyboard Rows ──
            ForEach(Array(keyboardRows.enumerated()), id: \.offset) { rowIdx, row in
                HStack(spacing: 8) {
                    ForEach(Array(row.enumerated()), id: \.offset) { colIdx, key in
                        keyboardKeyView(key: key, row: rowIdx, col: colIdx)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, 60)
        .padding(.vertical, 16)
    }

    // MARK: - Page Label

    private var pageLabel: String {
        if keyboardPage == 1 { return "1#+" }
        return isShifted ? "ABC" : "abc"
    }

    // MARK: - Key View

    private func keyboardKeyView(key: String, row: Int, col: Int) -> some View {
        let isFocused = isKeyFocused(row: row, col: col)
        let isSpecial = KeyboardLayoutService.isSpecialKey(key)
        let displayText = isSpecial ? KeyboardLayoutService.displayText(for: key) : key
        let isShiftKey = key == "_shift"
        let shiftActive = isShiftKey && isShifted

        return Button(action: { onKeyPressed(key) }) {
            Text(displayText)
                .font(.system(
                    size: isSpecial ? 22 : 20,
                    weight: isSpecial ? .light : .regular,
                    design: isSpecial ? .default : .monospaced
                ))
                .foregroundColor(keyColor(for: key, isFocused: isFocused, shiftActive: shiftActive))
                .frame(
                    width: keyWidth(for: key),
                    height: 48
                )
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(keyBackground(for: key, isFocused: isFocused, shiftActive: shiftActive))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(keyBorder(for: key, isFocused: isFocused, shiftActive: shiftActive),
                                lineWidth: 2)
                )
                .scaleEffect(isFocused ? 1.08 : 1.0)
                .shadow(
                    color: isFocused ? Color.ps4Pink.opacity(0.4) : .clear,
                    radius: isFocused ? 10 : 0
                )
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isFocused)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: shiftActive)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Focus Check

    private func isKeyFocused(row: Int, col: Int) -> Bool {
        let flat = KeyboardLayoutService.flatIndexForKeyboard(row: row, col: col, rows: keyboardRows)
        return focusedIndex == flat
    }

    // MARK: - Styling

    private func keyColor(for key: String, isFocused: Bool, shiftActive: Bool) -> Color {
        if isFocused { return .white }
        if shiftActive { return Color.ps4Pink }
        if KeyboardLayoutService.isSpecialKey(key) {
            switch key {
            case "_done":   return Color.ps4Pink
            case "_backspace", "_shift": return .white.opacity(0.7)
            default:        return .white.opacity(0.8)
            }
        }
        return .white.opacity(0.9)
    }

    private func keyBackground(for key: String, isFocused: Bool, shiftActive: Bool) -> Color {
        if isFocused { return Color.ps4Pink }
        if shiftActive { return Color.ps4Pink.opacity(0.25) }
        return Color.white.opacity(0.08)
    }

    private func keyBorder(for key: String, isFocused: Bool, shiftActive: Bool) -> Color {
        if isFocused || shiftActive { return Color.ps4Pink }
        return .clear
    }

    private func keyWidth(for key: String) -> CGFloat {
        switch key {
        case "_space":   return 280
        case "_done":    return 120
        case "_backspace": return 100
        case "_shift":   return 60
        default:         return 52
        }
    }
}
