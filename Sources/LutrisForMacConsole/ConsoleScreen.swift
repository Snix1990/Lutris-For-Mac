import Foundation

/// Identifiziert den Screen, den ein Tab aufruft
public enum ConsoleScreen: Hashable, Sendable {
    case library
    case favorites
    case settings
}
