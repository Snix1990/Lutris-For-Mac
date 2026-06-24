import SwiftUI
import Combine

// MARK: - Section Definition

public enum ConsoleSection: Int, CaseIterable, Hashable, Sendable {
    case topBar       // Library | Settings | …
    case search       // Search bar + On-Screen Keyboard
    case hero         // "Continue Playing"
    case recent       // Horizontale Recent-Reihe
    case allGames     // Haupt-Grid
    case filter       // Filter-Panel (Kategorie, Plattform, Runner)
}

// MARK: - ConsoleFocusManager

@MainActor
public final class ConsoleFocusManager: ObservableObject {
    // ── Published State ──
    @Published public var activeSection: ConsoleSection = .topBar
    @Published public var focusedIndex: Int = 0
    @Published public var itemCountInSection: Int = 0
    @Published public var gridColumnCount: Int = 4
    /// Lineare Navigation (1‑Spalte) für Settings/Detail‑Screens
    @Published public var isLinearMode: Bool = false
    /// Merkt sich den letzten fokussierten Index der TopBar,
    /// damit die NavBar beim Wechsel zu .filter/.search nicht ihr Aussehen ändert.
    @Published public var lastTopBarFocusIndex: Int = 0
    /// Anzahl der TopBar-Tabs (wird vom View gesetzt)
    public var topBarItemCount: Int = 3

    /// Sichtbare Sections – dynamisch (hero/recent können fehlen)
    public var visibleSections: [ConsoleSection] = ConsoleSection.allCases

    // ── Keyboard State ──
    @Published public var keyboardRows: [[String]] = []
    @Published public var keyboardPage: Int = 0
    @Published public var isKeyboardMode: Bool = false
    @Published public var keyboardActive: Bool = false   // true wenn Keyboard sichtbar+fokussiert

    /// Helper: ist der Suchmodus aktiv und die Tastatur offen?
    public var isKeyboardVisible: Bool {
        isKeyboardMode && keyboardActive
    }

    // ── Internals ──
    private var rememberedColumn: Int = 0
    private var lastInputTime: Date = .distantPast
    public let debounceInterval: TimeInterval = 0.2

    // ── Input-Guard ──
    @discardableResult
    public func consumeInput() -> Bool {
        let now = Date()
        let canConsume = now.timeIntervalSince(lastInputTime) >= debounceInterval
        guard canConsume else { return false }
        lastInputTime = now
        return true
    }

    // ── Sichtbarkeit updaten ──
    public func updateVisibleSections(searchActive: Bool) {
        if searchActive {
            visibleSections = [.topBar, .search, .allGames]
        } else {
            visibleSections = ConsoleSection.allCases
        }
        // Sicherstellen, dass activeSection gültig ist
        if !visibleSections.contains(activeSection) {
            activeSection = visibleSections.first ?? .topBar
            focusedIndex = 0
        }
    }

    // ── Section Navigation (L1 / R1) ──

    public func sectionLeft() {
        guard visibleSections.count > 1 else { return }
        // Im Keyboard-Modus schaltet L1/R1 die Seite, nicht die Section
        if isKeyboardMode && keyboardActive {
            switchKeyboardPage()
            return
        }
        rememberedColumn = focusedIndex
        if activeSection == .topBar { lastTopBarFocusIndex = focusedIndex }
        let currentIdx = visibleSections.firstIndex(of: activeSection) ?? 0
        let prevIdx = (currentIdx - 1 + visibleSections.count) % visibleSections.count
        activeSection = visibleSections[prevIdx]
        focusedIndex = 0
        if activeSection == .topBar { lastTopBarFocusIndex = focusedIndex }
        updateItemCountForCurrentSection()
    }

    public func sectionRight() {
        guard visibleSections.count > 1 else { return }
        if isKeyboardMode && keyboardActive {
            switchKeyboardPage()
            return
        }
        rememberedColumn = focusedIndex
        if activeSection == .topBar { lastTopBarFocusIndex = focusedIndex }
        let currentIdx = visibleSections.firstIndex(of: activeSection) ?? 0
        let nextIdx = (currentIdx + 1) % visibleSections.count
        activeSection = visibleSections[nextIdx]
        focusedIndex = 0
        if activeSection == .topBar { lastTopBarFocusIndex = focusedIndex }
        updateItemCountForCurrentSection()
    }

    // ── Keyboard-Page wechseln ──
    public func switchKeyboardPage() {
        guard !keyboardRows.isEmpty else { return }
        NotificationCenter.default.post(name: .consoleKeyboardPage, object: nil)
    }

    // ── D-Pad Navigation ──

    public func moveUp() {
        switch activeSection {
        case .allGames:
            if isLinearMode {
                if focusedIndex > 0 { focusedIndex -= 1 }
            } else {
                let cols = max(gridColumnCount, 1)
                let target = focusedIndex - cols
                if target >= 0 { focusedIndex = target; rememberedColumn = focusedIndex % cols }
                else { sectionLeft() }
            }

        case .search:
            if keyboardActive {
                // Keyboard-Grid: nach oben
                if let pos = keyboardPosition(for: focusedIndex) {
                    let cols = currentKeyboardColumnCount()
                    guard cols > 0 else { return }
                    let targetRow = pos.row - 1
                    if targetRow >= 0 {
                        let targetCol = min(pos.col, keyboardRows[targetRow].count - 1)
                        focusedIndex = flatIndexForKeyboard(row: targetRow, col: targetCol)
                    } else {
                        // Ganz oben → zurück zur Search-Bar (index 0)
                        focusedIndex = 0
                        keyboardActive = false
                    }
                }
            } else {
                // Search-Bar fokussiert → nichts
            }

        case .topBar: break
        case .hero, .recent: sectionLeft()
        case .filter: break
        }
    }

    public func moveDown() {
        switch activeSection {
        case .allGames:
            if isLinearMode {
                if focusedIndex < itemCountInSection - 1 { focusedIndex += 1 }
            } else {
                let cols = max(gridColumnCount, 1)
                let target = focusedIndex + cols
                if target < itemCountInSection { focusedIndex = target; rememberedColumn = focusedIndex % cols }
                else { sectionRight() }
            }

        case .search:
            if focusedIndex == 0 && keyboardActive {
                // Von Search-Bar runter → erstes Keyboard-Key
                focusedIndex = 1
            } else if focusedIndex == 0 && !keyboardActive {
                // Search-Bar, Keyboard nicht aktiv → nix
                break
            } else if keyboardActive {
                // Keyboard-Grid: nach unten
                if let pos = keyboardPosition(for: focusedIndex) {
                    let targetRow = pos.row + 1
                    if targetRow < keyboardRows.count {
                        let targetCol = min(pos.col, keyboardRows[targetRow].count - 1)
                        focusedIndex = flatIndexForKeyboard(row: targetRow, col: targetCol)
                    }
                    // Am Ende der Tastatur → kein weiterer Sprung
                }
            }

        case .topBar: sectionRight()
        case .hero, .recent: sectionRight()
        case .filter: break
        }
    }

    public func moveLeft() {
        switch activeSection {
        case .allGames:
            if isLinearMode {
                if focusedIndex > 0 { focusedIndex -= 1 }
            } else {
                let cols = max(gridColumnCount, 1)
                let rowStart = (focusedIndex / cols) * cols
                if focusedIndex > rowStart { focusedIndex -= 1 }
                rememberedColumn = focusedIndex % cols
            }

        case .search:
            if keyboardActive, focusedIndex > 0 {
                if let pos = keyboardPosition(for: focusedIndex) {
                    let rowStart = flatIndexForKeyboard(row: pos.row, col: 0)
                    let rowEnd = rowStart + max(keyboardRows[pos.row].count - 1, 0)
                    if focusedIndex > rowStart {
                        focusedIndex -= 1
                    } else {
                        // Wrap to end of row
                        focusedIndex = rowEnd
                    }
                }
            } else if focusedIndex > 0 {
                focusedIndex -= 1
            }

        case .filter:
            if focusedIndex > 0 { focusedIndex -= 1 }
        case .topBar:
            if focusedIndex > 0 { focusedIndex -= 1 }
            lastTopBarFocusIndex = focusedIndex
        case .recent:
            if focusedIndex > 0 { focusedIndex -= 1 }
        case .hero: break
        }
    }

    public func moveRight() {
        switch activeSection {
        case .allGames:
            if isLinearMode {
                if focusedIndex < itemCountInSection - 1 { focusedIndex += 1 }
            } else {
                let cols = max(gridColumnCount, 1)
                let rowStart = (focusedIndex / cols) * cols
                let rowEnd = min(rowStart + cols - 1, itemCountInSection - 1)
                if focusedIndex < rowEnd { focusedIndex += 1 }
                rememberedColumn = focusedIndex % cols
            }

        case .search:
            if keyboardActive, focusedIndex > 0 {
                if let pos = keyboardPosition(for: focusedIndex) {
                    let rowStart = flatIndexForKeyboard(row: pos.row, col: 0)
                    let rowEnd = rowStart + max(keyboardRows[pos.row].count - 1, 0)
                    if focusedIndex < rowEnd {
                        focusedIndex += 1
                    } else {
                        focusedIndex = rowStart
                    }
                }
            } else if focusedIndex < itemCountInSection - 1 {
                focusedIndex += 1
            }

        case .filter:
            if focusedIndex < itemCountInSection - 1 { focusedIndex += 1 }
        case .topBar:
            if focusedIndex < itemCountInSection - 1 { focusedIndex += 1 }
            lastTopBarFocusIndex = focusedIndex
        case .recent:
            if focusedIndex < itemCountInSection - 1 { focusedIndex += 1 }
        case .hero: break
        }
    }

    // ── Aktionen ──

    public func confirm() {
        NotificationCenter.default.post(
            name: .consoleConfirm, object: nil,
            userInfo: ["section": activeSection.rawValue, "index": focusedIndex]
        )
    }

    public func back() {
        NotificationCenter.default.post(name: .consoleBack, object: nil)
    }

    /// Menu → Home (Welcome-Screen)
    public func menu() {
        NotificationCenter.default.post(name: .consoleMenu, object: nil)
    }

    // ── Search-Toggle von Select-Button ──
    public func toggleSearch() {
        NotificationCenter.default.post(name: .consoleSearchToggle, object: nil)
    }

    // ── Navbar-Tabs wechseln (Schultertasten) + sofort navigieren ──
    public func navTabLeft() {
        if isKeyboardMode && keyboardActive {
            switchKeyboardPage()
            return
        }
        activeSection = .topBar
        let count = topBarItemCount
        let current = lastTopBarFocusIndex
        let newIndex: Int
        if current > 0 {
            newIndex = current - 1
        } else {
            newIndex = count - 1
        }
        focusedIndex = newIndex
        lastTopBarFocusIndex = newIndex
        updateItemCountForCurrentSection()
        NotificationCenter.default.post(
            name: .consoleConfirm,
            object: nil,
            userInfo: ["section": ConsoleSection.topBar.rawValue, "index": newIndex]
        )
    }

    public func navTabRight() {
        if isKeyboardMode && keyboardActive {
            switchKeyboardPage()
            return
        }
        activeSection = .topBar
        let count = topBarItemCount
        let current = lastTopBarFocusIndex
        let newIndex: Int
        if current < count - 1 {
            newIndex = current + 1
        } else {
            newIndex = 0
        }
        focusedIndex = newIndex
        lastTopBarFocusIndex = newIndex
        updateItemCountForCurrentSection()
        NotificationCenter.default.post(
            name: .consoleConfirm,
            object: nil,
            userInfo: ["section": ConsoleSection.topBar.rawValue, "index": newIndex]
        )
    }

    // ── Content-Sections cyclen (Hoch/Runter) inkl. .filter ──
    public func cycleContentSectionUp() {
        guard !isLinearMode else { return }
        switch activeSection {
        case .filter:   activeSection = .allGames
        case .allGames: activeSection = .recent
        case .recent:   activeSection = .hero
        case .hero:     break
        default:        activeSection = .hero
        }
        focusedIndex = 0
        updateItemCountForCurrentSection()
    }

    public func cycleContentSectionDown() {
        guard !isLinearMode else { return }
        switch activeSection {
        case .hero:     activeSection = .recent
        case .recent:   activeSection = .allGames
        case .allGames: activeSection = .filter
        case .filter:   break
        default:        activeSection = .hero
        }
        focusedIndex = 0
        updateItemCountForCurrentSection()
    }

    // ── Fokus-Check (für Views) ──
    public func isFocused(section: ConsoleSection, index: Int) -> Bool {
        activeSection == section && focusedIndex == index
    }

    // ── ItemCount updaten ──
    public func updateItemCountForCurrentSection() {
        switch activeSection {
        case .search:
            if keyboardActive, !keyboardRows.isEmpty {
                let totalKeys = keyboardRows.reduce(0) { $0 + $1.count }
                itemCountInSection = 1 + totalKeys  // 1 = search bar
            } else {
                itemCountInSection = 1  // nur search bar
            }
        case .hero:
            itemCountInSection = 2  // Play + Details
        case .recent:
            itemCountInSection = min(itemCountInSection, 5)
        case .topBar:
            itemCountInSection = topBarItemCount
        case .allGames, .filter:
            break // wird vom View gesetzt
        }
    }

    // MARK: - Keyboard Grid Helpers

    /// Maximale Spaltenanzahl der aktuellen Keyboard-Seite
    public func currentKeyboardColumnCount() -> Int {
        keyboardRows.map(\.count).max() ?? 10
    }

    /// Flat-Index → (row, col) im Keyboard-Grid
    public func keyboardPosition(for flatIndex: Int) -> (row: Int, col: Int)? {
        KeyboardLayoutService.keyboardPosition(for: flatIndex, rows: keyboardRows)
    }

    /// (row, col) → Flat-Index im search-section
    public func flatIndexForKeyboard(row: Int, col: Int) -> Int {
        KeyboardLayoutService.flatIndexForKeyboard(row: row, col: col, rows: keyboardRows)
    }

    /// Keyboard-Rows laden und itemCount updaten
    public func loadKeyboardPage(page: Int, shifted: Bool = false, layout: KeyboardLayoutType = .qwerty) {
        keyboardRows = KeyboardLayoutService.keyboardRows(page: page, shifted: shifted, layout: layout)
        keyboardPage = page
        updateItemCountForCurrentSection()
    }
}

// MARK: - Notifications

public extension Notification.Name {
    static let consoleConfirm       = Notification.Name("consoleConfirm")
    static let consoleBack          = Notification.Name("consoleBack")
    static let consoleMenu          = Notification.Name("consoleMenu")
    static let consoleSearchToggle  = Notification.Name("consoleSearchToggle")
    static let consoleKeyboardPage  = Notification.Name("consoleKeyboardPage")
    static let consoleScroll        = Notification.Name("consoleScroll")
}
