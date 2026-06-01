import Foundation

enum ProcessRunner {
    static func run(command: String, currentDirectory: URL?, environment: [String: String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let task = Process()
            task.launchPath = "/bin/bash"
            task.arguments = ["-lc", command]
            task.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
            task.currentDirectoryURL = currentDirectory

            let outputPipe = Pipe()
            task.standardOutput = outputPipe
            task.standardError = outputPipe

            task.terminationHandler = { process in
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: ProcessError.exitStatus(process.terminationStatus, output))
                }
            }

            do {
                try task.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    static func parseEnvironmentVariables(from text: String) -> [String: String] {
        var env: [String: String] = [:]
        let lines = text.split(whereSeparator: { $0.isNewline })
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let equalIndex = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<equalIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: equalIndex)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty {
                env[key] = value
            }
        }
        return env
    }
}
