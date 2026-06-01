import Foundation

enum ProcessError: LocalizedError {
    case exitStatus(Int32, String)

    var output: String {
        switch self {
        case .exitStatus(_, let output): return output
        }
    }

    var errorDescription: String? {
        switch self {
        case .exitStatus(let code, let output):
            return "Prozess beendet mit Status \(code): \(output)"
        }
    }
}
