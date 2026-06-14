import Foundation

enum ProcessRunner {
    private static let logDir: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LutrisForMac", isDirectory: true)
            .appendingPathComponent("runtime-logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support
    }()

    static func writeOutputToLogFile(gameID: UUID, gameName: String, output: String) {
        let dateStr = ISO8601DateFormatter().string(from: Date())
        let sanitized = gameName.replacingOccurrences(of: "/", with: "_")
        let fileName = "\(gameID.uuidString.prefix(8))_\(sanitized)_\(dateStr).log"
        let url = logDir.appendingPathComponent(fileName)
        try? output.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Run a command and wait for completion (blocking).
    /// - Parameter captureOutput: If false, stdout/stderr pipes are not set up (saves memory).
    static func run(command: String, currentDirectory: URL?, environment: [String: String], captureOutput: Bool = true) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let task = Process()
            task.launchPath = "/bin/bash"
            task.arguments = ["-lc", command]
            task.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
            task.currentDirectoryURL = currentDirectory

            if captureOutput {
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
            } else {
                task.terminationHandler = { process in
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: "")
                    } else {
                        continuation.resume(throwing: ProcessError.exitStatus(process.terminationStatus, ""))
                    }
                }
            }

            do {
                try task.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Launch a command in the background. Returns the PID and an async stream of stdout/stderr lines.
    /// The caller is responsible for monitoring the PID via GameSessionManager or manual wait.
    static func launch(
        command: String,
        currentDirectory: URL? = nil,
        environment: [String: String] = [:]
    ) async throws -> (pid: Int32, output: AsyncStream<String>) {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-lc", command]
        task.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        task.currentDirectoryURL = currentDirectory

        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = outputPipe

        let stream = AsyncStream<String> { continuation in
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let line = String(data: data, encoding: .utf8) {
                    continuation.yield(line)
                }
            }
            task.terminationHandler = { _ in
                outputPipe.fileHandleForReading.readabilityHandler = nil
                continuation.finish()
            }
        }

        try task.run()
        return (task.processIdentifier, stream)
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
