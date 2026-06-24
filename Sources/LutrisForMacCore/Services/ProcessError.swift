import Foundation

public enum ProcessError: LocalizedError {
    case exitStatus(Int32, String)

    public var output: String {
        switch self {
        case .exitStatus(_, let output): return output
        }
    }

    public var errorDescription: String? {
        switch self {
        case .exitStatus(let code, let output):
            return "Prozess beendet mit Status \(code): \(output)"
        }
    }
}
