import Foundation
import LutrisForMacCore

public enum FilterKind: String, CaseIterable, Sendable {
    case category
    case platform
    case runner

    public var displayTitle: String {
        switch self {
        case .category: return tr("Kategorie")
        case .platform: return tr("Plattform")
        case .runner:   return tr("Runner")
        }
    }
}
