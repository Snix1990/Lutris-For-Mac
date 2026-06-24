import SwiftUI

// ================================================================
// KeyboardNavigation.swift
// ================================================================
// onKeyPress-ViewModifier (macOS 14+) → ConsoleFocusManager.
// Wenn eine physische Tastatur aktiv ist (consoleState?
// vorhanden), werden Return/Space/Tab nicht abgefangen,
// damit das native TextField sie verarbeiten kann.
// ================================================================

struct KeyboardNavigationModifier: ViewModifier {
    @ObservedObject var focusManager: ConsoleFocusManager
    var consoleState: ConsoleState?

    func body(content: Content) -> some View {
        content
            .onKeyPress(.upArrow)    { focusManager.moveUp();    return .handled }
            .onKeyPress(.downArrow)  { focusManager.moveDown();  return .handled }
            .onKeyPress(.leftArrow)  { focusManager.moveLeft();  return .handled }
            .onKeyPress(.rightArrow) { focusManager.moveRight(); return .handled }

            // ── Return: bei physischer Tastatur im Search-Mode das TextField machen lassen ──
            .onKeyPress(.return) {
                if let cs = consoleState, cs.isSearchActive && cs.isPhysicalKeyboardActive {
                    return .ignored
                }
                focusManager.confirm()
                return .handled
            }

            .onKeyPress(.escape) { focusManager.back(); return .handled }

            // ── Tab: bei physischer Tastatur im Search-Mode ignorieren ──
            .onKeyPress(keys: [.tab]) { press in
                if let cs = consoleState, cs.isSearchActive && cs.isPhysicalKeyboardActive {
                    return .ignored
                }
                if press.modifiers.contains(.shift) { focusManager.sectionLeft() }
                else { focusManager.sectionRight() }
                return .handled
            }

            // ── Space: bei physischer Tastatur im Search-Mode an TextField durchreichen ──
            .onKeyPress(.space) {
                if let cs = consoleState, cs.isSearchActive && cs.isPhysicalKeyboardActive {
                    return .ignored
                }
                focusManager.confirm()
                return .handled
            }
    }
}

public extension View {
    func consoleKeyboardNavigation(
        focusManager: ConsoleFocusManager,
        consoleState: ConsoleState? = nil
    ) -> some View {
        modifier(KeyboardNavigationModifier(focusManager: focusManager, consoleState: consoleState))
    }
}
