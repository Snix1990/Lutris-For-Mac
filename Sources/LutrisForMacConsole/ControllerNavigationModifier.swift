import SwiftUI
import Combine

// ================================================================
// ControllerNavigationModifier.swift
// ================================================================
// Kapselt die gesamte Controller-Navigation-Boilerplate:
// - KeyboardMonitor (physische Tastatur → Search-Aktivierung)
// - .onReceive für consoleConfirm/Back/SearchToggle/KeyboardPage
// - .onChange für alle ConsoleState/ConsoleFocusManager-Properties
// - Appear/Disappear-Setup
//
// Views rufen nur `.modifier(ControllerNavigationModifier(...))` auf
// und liefern per Closure die view-spezifischen Actions.
// ================================================================

public struct ControllerNavigationModifier: ViewModifier {
    @ObservedObject var consoleState: ConsoleState
    @ObservedObject var focusManager: ConsoleFocusManager
    let gridColumns: Int

    let onConfirm: (ConsoleSection, Int) -> Void
    let onBack: () -> Void
    let onSearchToggle: () -> Void
    let onUpdateFocusState: () -> Void
    let onSearchActiveChanged: (Bool) -> Void

    @State private var keyboardMonitor: Any?

    public init(
        consoleState: ConsoleState,
        focusManager: ConsoleFocusManager,
        gridColumns: Int,
        onConfirm: @escaping (ConsoleSection, Int) -> Void,
        onBack: @escaping () -> Void,
        onSearchToggle: @escaping () -> Void,
        onUpdateFocusState: @escaping () -> Void,
        onSearchActiveChanged: @escaping (Bool) -> Void
    ) {
        self.consoleState = consoleState
        self.focusManager = focusManager
        self.gridColumns = gridColumns
        self.onConfirm = onConfirm
        self.onBack = onBack
        self.onSearchToggle = onSearchToggle
        self.onUpdateFocusState = onUpdateFocusState
        self.onSearchActiveChanged = onSearchActiveChanged
    }

    // MARK: - Body

    public func body(content: Content) -> some View {
        content
            // ── Appear / Disappear ──
            .onAppear {
                focusManager.gridColumnCount = gridColumns
                startKeyboardMonitor()
            }
            .onDisappear {
                stopKeyboardMonitor()
                focusManager.isLinearMode = false
            }

            // ── Grid-Spalten ──
            .onChange(of: gridColumns) { _, newCols in
                focusManager.gridColumnCount = newCols
            }

            // ── Search-Aktivierung ──
            .onChange(of: consoleState.isSearchActive) { _, active in
                focusManager.updateVisibleSections(searchActive: active)
                if active {
                    focusManager.activeSection = .search
                    focusManager.focusedIndex = 0
                    consoleState.layoutType = KeyboardLayoutService.currentLayout()
                }
                onSearchActiveChanged(active)
                onUpdateFocusState()
                if active {
                    startKeyboardMonitor()
                } else {
                    stopKeyboardMonitor()
                }
            }

            // ── Keyboard sichtbar ──
            .onChange(of: consoleState.isKeyboardVisible) { _, visible in
                guard !consoleState.isPhysicalKeyboardActive else { return }
                focusManager.keyboardActive = visible
                focusManager.isKeyboardMode = visible
                if visible {
                    focusManager.loadKeyboardPage(
                        page: consoleState.keyboardPage,
                        shifted: consoleState.isShifted,
                        layout: consoleState.layoutType
                    )
                }
                onUpdateFocusState()
                if visible, focusManager.activeSection == .search {
                    focusManager.focusedIndex = 0
                }
            }

            // ── Keyboard-Seite / Shift ──
            .onChange(of: consoleState.keyboardPage) { _, page in
                focusManager.loadKeyboardPage(page: page, shifted: consoleState.isShifted, layout: consoleState.layoutType)
            }
            .onChange(of: consoleState.isShifted) { _, shifted in
                guard consoleState.isKeyboardVisible else { return }
                focusManager.loadKeyboardPage(page: consoleState.keyboardPage, shifted: shifted, layout: consoleState.layoutType)
            }

            // ── Search-Text / Favorites-Only ──
            .onChange(of: consoleState.searchText) { _, _ in
                onUpdateFocusState()
            }
            .onChange(of: consoleState.showFavoritesOnly) { _, _ in
                onUpdateFocusState()
            }

            // ── Section-Wechsel ──
            .onChange(of: focusManager.activeSection) { _, newSection in
                if newSection == .allGames || newSection == .filter {
                    onUpdateFocusState()
                }
            }

            // ── Receive: Confirm ──
            .onReceive(NotificationCenter.default.publisher(for: .consoleConfirm)) { note in
                guard let sectionRaw = note.userInfo?["section"] as? Int,
                      let section = ConsoleSection(rawValue: sectionRaw),
                      let index = note.userInfo?["index"] as? Int
                else { return }
                onConfirm(section, index)
            }

            // ── Receive: Back ──
            .onReceive(NotificationCenter.default.publisher(for: .consoleBack)) { _ in
                onBack()
            }

            // ── Receive: Search Toggle ──
            .onReceive(NotificationCenter.default.publisher(for: .consoleSearchToggle)) { _ in
                onSearchToggle()
            }

            // ── Receive: Keyboard Page Switch ──
            .onReceive(NotificationCenter.default.publisher(for: .consoleKeyboardPage)) { _ in
                guard !consoleState.isPhysicalKeyboardActive else { return }
                consoleState.switchKeyboardPage()
            }
    }

    // MARK: - Keyboard Monitor

    private func startKeyboardMonitor() {
        guard keyboardMonitor == nil else { return }
        let cs = consoleState
        let fm = focusManager
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape (53) → deactivate search when active, otherwise pass through
            if event.keyCode == 53 {
                if cs.isSearchActive {
                    DispatchQueue.main.async {
                        cs.deactivateSearch()
                        fm.updateVisibleSections(searchActive: false)
                    }
                    return nil
                }
                return event
            }

            guard let chars = event.characters, !chars.isEmpty else { return event }
            let navKeys: Set<UInt16> = [36, 48, 123, 124, 125, 126]
            guard !navKeys.contains(event.keyCode) else { return event }

            if !cs.isSearchActive {
                DispatchQueue.main.async {
                    cs.activateSearch()
                    cs.searchActivatedByController = false
                    cs.isPhysicalKeyboardActive = true
                    cs.searchText = chars
                    fm.updateVisibleSections(searchActive: true)
                    fm.activeSection = .search
                    fm.focusedIndex = 0
                }
                return nil
            }

            if cs.isPhysicalKeyboardActive {
                return event
            } else {
                DispatchQueue.main.async {
                    cs.isPhysicalKeyboardActive = true
                    cs.searchText.append(chars)
                }
                return nil
            }
        }
    }

    private func stopKeyboardMonitor() {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
    }
}
