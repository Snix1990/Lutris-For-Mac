import Foundation
import AppKit
import SwiftUI

// MARK: - Helpers (C macros aus <sys/wait.h> in Swift)

private func wifexited(_ status: Int32) -> Bool { (status & 0x7f) == 0 }
private func wexitstatus(_ status: Int32) -> Int32 { (status >> 8) & 0xff }
private func wifsignaled(_ status: Int32) -> Bool { (status & 0x7f) != 0x7f && (status & 0x7f) != 0 }
private func wtermsig(_ status: Int32) -> Int32 { status & 0x7f }

// MARK: - Models

struct MonitoredProcess: Identifiable, Equatable {
    let id = UUID()
    let pid: Int32
    let name: String
    let command: String
    let startTime: Date
    var cpuPercent: Double
    var memoryMB: Double
    var parentPID: Int32

    static func == (lhs: MonitoredProcess, rhs: MonitoredProcess) -> Bool {
        lhs.id == rhs.id
    }
}

enum ProcessExit {
    case running
    case exited(code: Int32)
    case killed(signal: Int32)
    case unknown(status: Int32)

    var description: String {
        switch self {
        case .running: return "running"
        case .exited(let code): return "exited (code \(code))"
        case .killed(let sig): return "killed (signal \(sig)\(Self.signalName(sig)))"
        case .unknown(let s): return "unknown (\(s))"
        }
    }

    var isCrash: Bool {
        switch self {
        case .killed(let sig): return sig != SIGTERM && sig != SIGKILL
        case .exited(let code): return code != 0
        default: return false
        }
    }

    private static func signalName(_ sig: Int32) -> String {
        switch sig {
        case SIGSEGV: return " – segfault"
        case SIGABRT: return " – abort"
        case SIGILL: return " – illegal instruction"
        case SIGBUS: return " – bus error"
        default: return ""
        }
    }
}

// MARK: - Log Entry

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let text: String
    let stream: Stream

    enum Stream { case stdout, stderr, system }
}

// MARK: - Monitor

@MainActor
final class ProcessMonitor: ObservableObject {
    static let shared = ProcessMonitor()

    // MARK: Published State
    @Published var isRunning = false
    @Published var rootPID: Int32?
    @Published var processes: [MonitoredProcess] = []
    @Published var exit: ProcessExit = .running
    @Published var log: [LogEntry] = []
    @Published var totalCPU: Double = 0
    @Published var totalMemoryMB: Double = 0

    // MARK: Configuration
    var maxLogEntries = 5000
    var pollInterval: TimeInterval = 2.0
    var statsInterval: TimeInterval = 3.0

    // MARK: Internal
    private var monitoredTask: Task<Void, Never>?
    private var statsTask: Task<Void, Never>?
    private var launchedProcess: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var logFileHandle: FileHandle?
    private let logDir: URL
    private var logFileURL: URL?

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LutrisForMac", isDirectory: true)
        logDir = support.appendingPathComponent("runtime-logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    }

    // MARK: - Launch

    func launch(exePath: String, arguments: [String] = [], environment: [String: String] = [:]) async throws {
        stop()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: exePath)
        process.arguments = arguments
        process.environment = environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        stdoutPipe = outPipe
        stderrPipe = errPipe

        try process.run()
        launchedProcess = process
        rootPID = process.processIdentifier
        self.isRunning = true
        self.exit = .running

        // Log file
        let dateStr = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let fileName = "\(URL(fileURLWithPath: exePath).lastPathComponent)_\(dateStr).log"
        logFileURL = logDir.appendingPathComponent(fileName)
        if let url = logFileURL {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            logFileHandle = try? FileHandle(forWritingTo: url)
        }

        self.addLog("[Start] \(exePath) \(arguments.joined(separator: " "))", stream: .system)

        // Read pipes
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.addChunk(text, stream: .stdout)
                self?.writeToFile(text)
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.addChunk(text, stream: .stderr)
                self?.writeToFile(text)
            }
        }

        // Wait for exit
        monitoredTask = Task { [weak self] in
            process.waitUntilExit()
            await MainActor.run {
                guard let self else { return }
                let status = process.terminationStatus
                if process.terminationReason == .exit {
                    self.exit = .exited(code: status)
                } else {
                    self.exit = .killed(signal: status)
                }
                self.addLog("[Exit] \(self.exit.description)", stream: .system)
                self.cleanupPipes()
                self.isRunning = false
            }
        }

        // Poll stats
        let statsInterval = self.statsInterval
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(statsInterval * 1_000_000_000))
                await MainActor.run { self?.pollStats() }
            }
        }
    }

    // MARK: - Attach to existing PID

    func attach(pid: Int32) async {
        stop()
        rootPID = pid
        self.isRunning = true
        self.exit = .running

        self.addLog("[Attach] PID \(pid)", stream: .system)

        let dateStr = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let fileName = "pid_\(pid)_\(dateStr).log"
        logFileURL = logDir.appendingPathComponent(fileName)
        if let url = logFileURL {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            logFileHandle = try? FileHandle(forWritingTo: url)
        }

        let pollInterval = self.pollInterval
        let statsInterval = self.statsInterval

        monitoredTask = Task { [weak self] in
            while !Task.isCancelled {
                let rc = kill(pid, 0)
                if rc != 0 {
                    await MainActor.run {
                        guard let self else { return }
                        var status: Int32 = 0
                        let waited = waitpid(pid, &status, WNOHANG)
                        if waited == pid {
                            if wifexited(status) {
                                self.exit = .exited(code: wexitstatus(status))
                            } else if wifsignaled(status) {
                                self.exit = .killed(signal: wtermsig(status))
                            } else {
                                self.exit = .unknown(status: status)
                            }
                        } else {
                            self.exit = .exited(code: -1)
                        }
                        self.addLog("[Exit] \(self.exit.description)", stream: .system)
                        self.isRunning = false
                    }
                    break
                }
                try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            }
        }

        pollStats()
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(statsInterval * 1_000_000_000))
                await MainActor.run { self?.pollStats() }
            }
        }
    }

    // MARK: - Stop / Cancel

    func stop() {
        monitoredTask?.cancel()
        monitoredTask = nil
        statsTask?.cancel()
        statsTask = nil
        launchedProcess = nil
        cleanupPipes()
        logFileHandle?.closeFile()
        logFileHandle = nil
        self.isRunning = false
        processes.removeAll()
        rootPID = nil
    }

    func terminate() {
        guard let pid = rootPID else { return }
        kill(pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            kill(pid, SIGKILL)
        }
    }

    // MARK: - Log

    private func addChunk(_ text: String, stream: LogEntry.Stream) {
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        for line in lines {
            addLog(line, stream: stream)
        }
    }

    private func addLog(_ text: String, stream: LogEntry.Stream) {
        let entry = LogEntry(timestamp: Date(), text: text, stream: stream)
        log.append(entry)
        if log.count > maxLogEntries {
            log.removeFirst(log.count - maxLogEntries)
        }
    }

    private func writeToFile(_ text: String) {
        guard let handle = logFileHandle, let data = text.data(using: .utf8) else { return }
        handle.write(data)
    }

    // MARK: - Stats

    private func pollStats() {
        guard let rootPID else { return }
        let allPIDs = collectProcessTree(rootPID)
        var newProcesses: [MonitoredProcess] = []
        var cpuSum: Double = 0
        var memSum: Double = 0

        for pid in allPIDs {
            if let info = processInfo(pid) {
                newProcesses.append(info)
                cpuSum += info.cpuPercent
                memSum += info.memoryMB
            }
        }

        processes = newProcesses.sorted { $0.pid < $1.pid }
        totalCPU = cpuSum
        totalMemoryMB = memSum
    }

    private func collectProcessTree(_ root: Int32) -> Set<Int32> {
        var result = Set<Int32>()
        result.insert(root)
        var queue = [root]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            let children = childPIDs(current)
            for child in children where !result.contains(child) {
                result.insert(child)
                queue.append(child)
            }
        }
        return result
    }

    private func childPIDs(_ pid: Int32) -> [Int32] {
        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-o", "pid=", "--ppid", "\(pid)"]
        let out = Pipe()
        task.standardOutput = out
        try? task.run()
        task.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return output.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : Int32(trimmed)
        }
    }

    private func processInfo(_ pid: Int32) -> MonitoredProcess? {
        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-o", "pid=,ppid=,pcpu=,rss=,comm=", "-p", "\(pid)"]
        let out = Pipe()
        task.standardOutput = out
        try? task.run()
        task.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        let line = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }

        let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard parts.count >= 5,
              let pidVal = Int32(parts[0]),
              let ppidVal = Int32(parts[1]),
              let cpu = Double(parts[2]),
              let rss = Int64(parts[3]) else { return nil }

        let name = URL(fileURLWithPath: parts[4]).lastPathComponent
        let memMB = Double(rss) / 1024.0 / 1024.0

        return MonitoredProcess(
            pid: pidVal,
            name: name,
            command: parts.dropFirst(4).joined(separator: " "),
            startTime: Date(),
            cpuPercent: cpu,
            memoryMB: memMB,
            parentPID: ppidVal
        )
    }

    // MARK: - Helpers

    private func cleanupPipes() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe = nil
    }

    func openLogFile() {
        guard let url = logFileURL else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Log Viewer View

struct ProcessMonitorView: View {
    @StateObject private var monitor = ProcessMonitor.shared
    @StateObject private var debugManager = WineDebugManager.shared

    private var filteredLog: [LogEntry] {
        guard debugManager.filterDebugLog else { return monitor.log }
        let debugChannels = debugManager.enabledChannelIDs
        guard !debugChannels.isEmpty else { return monitor.log }
        // Show only entries that match enabled channels or aren't debug lines
        return monitor.log.filter { entry in
            let text = entry.text.lowercased()
            // Pass through if it's not a debug channel line
            guard text.contains("winedbg:") || text.contains(":err:") || text.contains(":fixme:")
                    || text.contains(":warn:") || text.contains(":trace:") else { return true }
            // Check if any enabled channel matches
            return debugChannels.contains { text.contains(":\($0):") } ||
                   text.contains("winedbg:")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Status bar
            HStack {
                Circle()
                    .fill(monitor.isRunning ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(monitor.exit.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if monitor.isRunning {
                    Text(String(format: "CPU: %.1f%%", monitor.totalCPU))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "RAM: %.0f MB", monitor.totalMemoryMB))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let pid = monitor.rootPID {
                    Text("PID \(pid)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if !monitor.isRunning, monitor.rootPID != nil {
                    Button("Open log") { monitor.openLogFile() }
                        .buttonStyle(.link)
                }
            }
            .padding(8)

            // Process table
            if !monitor.processes.isEmpty {
                GroupBox {
                    ScrollView(.horizontal) {
                        VStack(spacing: 2) {
                            ForEach(monitor.processes) { proc in
                                HStack(spacing: 12) {
                                    Text("\(proc.pid)")
                                        .font(.system(.caption, design: .monospaced))
                                        .frame(width: 50, alignment: .trailing)
                                    Text(proc.name)
                                        .font(.system(.caption, design: .monospaced))
                                        .frame(width: 120, alignment: .leading)
                                        .lineLimit(1)
                                    Text(String(format: "%.1f%%", proc.cpuPercent))
                                        .font(.caption)
                                        .frame(width: 50, alignment: .trailing)
                                    Text(String(format: "%.0f MB", proc.memoryMB))
                                        .font(.caption)
                                        .frame(width: 60, alignment: .trailing)
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                        .padding(4)
                    }
                }
                .padding(.horizontal)
            }

            // Log view
            GroupBox {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(filteredLog) { entry in
                                HStack(spacing: 6) {
                                    Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(width: 70, alignment: .trailing)
                                    Text(entry.text)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(entry.stream == .stderr ? .red : entry.stream == .system ? .blue : .primary)
                                        .textSelection(.enabled)
                                }
                                .id(entry.id)
                            }
                        }
                        .padding(4)
                    }
                    .frame(minHeight: 200)
                    .onChange(of: filteredLog.count) { _, _ in
                        if let last = filteredLog.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}
