import Carbon
import Foundation

// ================================================================
// KeyboardLayoutService.swift
// ================================================================
// Erkennt das macOS-Tastaturlayout und liefert Key-Raster für OSDK.
// Unterstützt: QWERTY, QWERTZ, AZERTY, JIS, Dvorak, Colemak
// ================================================================

public enum KeyboardLayoutType: String, CaseIterable, Sendable {
    case qwerty
    case qwertz
    case azerty
    case jis
    case dvorak
    case colemak

    public var displayName: String {
        switch self {
        case .qwerty:  return "QWERTY"
        case .qwertz:  return "QWERTZ"
        case .azerty:  return "AZERTY"
        case .jis:     return "JIS"
        case .dvorak:  return "Dvorak"
        case .colemak: return "Colemak"
        }
    }
}

public enum KeyboardLayoutService {

    private static let cachedLayout: KeyboardLayoutType = {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return .qwerty
        }
        guard let cfProp = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return .qwerty
        }
        let layoutID = Unmanaged<CFString>.fromOpaque(cfProp).takeUnretainedValue() as String
        let lower = layoutID.lowercased()

        if lower.contains("jis") || lower.contains("japanese") {
            return .jis
        }
        if lower.contains("dvorak") {
            return .dvorak
        }
        if lower.contains("colemak") {
            return .colemak
        }
        if lower.contains("german") || lower.contains("swiss") {
            return .qwertz
        }
        if lower.contains("french") || lower.contains("belgian") || lower.contains("azerty") {
            return .azerty
        }
        return .qwerty
    }()

    /// Erkennt das aktuelle macOS-Tastaturlayout (gelazyt und gecached)
    public static func currentLayout() -> KeyboardLayoutType {
        cachedLayout
    }

    /// Liefert das Key-Raster für eine Seite
    public static func keyboardRows(page: Int, shifted: Bool = false, layout: KeyboardLayoutType = currentLayout()) -> [[String]] {
        switch page {
        case 0: return lettersPage(shifted: shifted, for: layout)
        case 1: return symbolsPage(for: layout)
        default: return lettersPage(shifted: shifted, for: layout)
        }
    }

    /// Maximale Spaltenanzahl über alle Keyboard-Rows hinweg
    public static func maxKeyboardColumns(page: Int, shifted: Bool = false, layout: KeyboardLayoutType = currentLayout()) -> Int {
        let rows = keyboardRows(page: page, shifted: shifted, layout: layout)
        return rows.map(\.count).max() ?? 10
    }

    // MARK: - Flat Index Helpers (ausgelagert, um Duplikate zu vermeiden)

    /// Convert keyboard (row, col) to flat section index (0 = search bar, 1+ = keys)
    public static func flatIndexForKeyboard(row: Int, col: Int, rows: [[String]]) -> Int {
        var offset = 1
        for r in 0..<row {
            offset += rows[r].count
        }
        offset += col
        return offset
    }

    /// Flat index → (row, col) position in the keyboard grid
    public static func keyboardPosition(for flatIndex: Int, rows: [[String]]) -> (row: Int, col: Int)? {
        guard flatIndex > 0, !rows.isEmpty else { return nil }
        var offset = flatIndex - 1
        for (rowIdx, row) in rows.enumerated() {
            if offset < row.count {
                return (rowIdx, offset)
            }
            offset -= row.count
        }
        return nil
    }

    /// Flat index → key string
    public static func keyAtFlatIndex(_ flatIndex: Int, rows: [[String]]) -> String {
        guard flatIndex > 0 else { return "" }
        if let pos = keyboardPosition(for: flatIndex, rows: rows) {
            guard pos.row < rows.count, pos.col < rows[pos.row].count else { return "" }
            return rows[pos.row][pos.col]
        }
        return ""
    }

    // MARK: - Layout-Definitionen

    private static func lettersPage(shifted: Bool, for layout: KeyboardLayoutType) -> [[String]] {
        let lowerRows: [[String]]
        switch layout {
        case .qwertz:
            lowerRows = [
                ["q","w","e","r","t","z","u","i","o","p","ü"],
                ["a","s","d","f","g","h","j","k","l","ö","ä"],
                ["_shift","y","x","c","v","b","n","m","_backspace"],
                ["_space", "_done"],
            ]
        case .azerty:
            lowerRows = [
                ["a","z","e","r","t","y","u","i","o","p"],
                ["q","s","d","f","g","h","j","k","l","m"],
                ["_shift","w","x","c","v","b","n","_backspace"],
                ["_space", "_done"],
            ]
        case .jis:
            lowerRows = [
                ["q","w","e","r","t","y","u","i","o","p"],
                ["a","s","d","f","g","h","j","k","l"],
                ["_shift","z","x","c","v","b","n","m","_backspace"],
                ["_space", "_done"],
            ]
        case .dvorak:
            lowerRows = [
                ["'",",",".","p","y","f","g","c","r","l"],
                ["a","o","e","u","i","d","h","t","n","s"],
                ["_shift","-","q","j","k","x","b","m","w","v","z","_backspace"],
                ["_space", "_done"],
            ]
        case .colemak:
            lowerRows = [
                ["q","w","f","p","g","j","l","u","y",";"],
                ["a","r","s","t","d","h","n","e","i","o"],
                ["_shift","z","x","c","v","b","k","m","_backspace"],
                ["_space", "_done"],
            ]
        case .qwerty:
            lowerRows = [
                ["q","w","e","r","t","y","u","i","o","p"],
                ["a","s","d","f","g","h","j","k","l"],
                ["_shift","z","x","c","v","b","n","m","_backspace"],
                ["_space", "_done"],
            ]
        }

        guard shifted else { return lowerRows }

        return lowerRows.map { row in
            row.map { key in
                key.hasPrefix("_") ? key : key.uppercased()
            }
        }
    }

    private static func symbolsPage(for layout: KeyboardLayoutType) -> [[String]] {
        switch layout {
        case .qwertz:
            return [
                ["1","2","3","4","5","6","7","8","9","0"],
                ["ß","!","\"","§","$","%","&","/","(",")","="],
                ["?","`","^","°","*","+","#","-",",",".","_backspace"],
                ["_space", "_done"],
            ]
        case .azerty:
            return [
                ["1","2","3","4","5","6","7","8","9","0"],
                ["&","é","\"","'","(","-","è","_","ç","à"],
                [")","=","+","^","$","*","ù","`",";",":","_backspace"],
                ["_space", "_done"],
            ]
        case .jis:
            return [
                ["1","2","3","4","5","6","7","8","9","0","-","^","\\"],
                ["!","\"","#","$","%","&","'","(",")","~","=","|","_backspace"],
                ["_space", "_done"],
            ]
        case .dvorak:
            return [
                ["1","2","3","4","5","6","7","8","9","0"],
                ["!","@","#","$","%","^","&","*","(",")","_backspace"],
                ["[","]","{","}","<",">","/","?","_space", "_done"],
            ]
        case .colemak:
            return [
                ["1","2","3","4","5","6","7","8","9","0"],
                ["!","@","#","$","%","^","&","*","(",")","_backspace"],
                ["-","_","=","+","[","]","{","}",":",";","_space", "_done"],
            ]
        case .qwerty:
            return [
                ["1","2","3","4","5","6","7","8","9","0"],
                ["!","@","#","$","%","^","&","*","(",")"],
                ["-","_","=","+","[","]","{","}","|","\\","_backspace"],
                ["_space", "_done"],
            ]
        }
    }

    // MARK: - Hilfsfunktionen

    public static func isSpecialKey(_ key: String) -> Bool {
        key.hasPrefix("_")
    }

    public static func displayText(for key: String) -> String {
        switch key {
        case "_space":    return "␣"
        case "_backspace": return "⌫"
        case "_done":     return "↵"
        case "_shift":    return "⇧"
        default:          return key
        }
    }
}
