import Foundation
import IOKit
import SwiftUI

// MARK: - Models

struct MemoryStats {
    let totalGB: Double
    let usedGB: Double
    let freeGB: Double
    let wiredGB: Double
    let compressedGB: Double
    let pressure: MemoryPressure
    enum MemoryPressure { case normal, warning, critical }
}

struct ThermalReading: Identifiable {
    let id = UUID()
    let name: String
    let temperatureCelsius: Double?
    let key: String
}

struct FanReading: Identifiable {
    let id = UUID()
    let name: String
    let rpm: Int
    let minRPM: Int
    let maxRPM: Int
}

struct DiskStats {
    let totalGB: Double
    let freeGB: Double
    let usedGB: Double
}

// MARK: - Frame Time Tracker

final class FrameTimeTracker: ObservableObject {
    @Published var fps: Double = 0
    @Published var frameTimeMs: Double = 0
    @Published var onePercentLowMs: Double = 0
    @Published var zeroOnePercentLowMs: Double = 0

    private var frameTimes: [Double] = []
    private var lastTimestamp: CFTimeInterval?
    private let maxSamples = 3000
    private var link: CVDisplayLink?

    func start() {
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { return }
        CVDisplayLinkSetOutputHandler(link) { [weak self] _, _, _, _, _ in
            self?.onFrame()
            return kCVReturnSuccess
        }
        CVDisplayLinkStart(link)
    }

    func stop() {
        guard let link else { return }
        CVDisplayLinkStop(link)
        self.link = nil
    }

    private func onFrame() {
        let now = CACurrentMediaTime()
        if let last = lastTimestamp {
            let dt = (now - last) * 1000
            frameTimes.append(dt)
            if frameTimes.count > maxSamples {
                frameTimes.removeFirst(frameTimes.count - maxSamples)
            }
            let sum = frameTimes.reduce(0, +)
            let cnt = frameTimes.count
            Task { @MainActor in
                fps = cnt > 0 ? 1000.0 / (sum / Double(cnt)) : 0
                frameTimeMs = cnt > 0 ? sum / Double(cnt) : 0
                if cnt >= 2 {
                    let sorted = frameTimes.sorted()
                    onePercentLowMs = sorted[max(0, Int(Double(cnt) * 0.01))]
                    zeroOnePercentLowMs = sorted[max(0, Int(Double(cnt) * 0.001))]
                }
            }
        }
        lastTimestamp = now
    }
}

// MARK: - Hardware Monitor

@MainActor
final class HardwareMonitor: ObservableObject {
    static let shared = HardwareMonitor()

    @Published var memory: MemoryStats?
    @Published var thermalReadings: [ThermalReading] = []
    @Published var fanReadings: [FanReading] = []
    @Published var disk: DiskStats?
    @Published var thermalState: ProcessInfo.ThermalState = .nominal
    @Published var smcAvailable = false

    let frameTimeTracker = FrameTimeTracker()

    private var timerTask: Task<Void, Never>?
    private var smcConn: io_connect_t = 0
    private var previousThermalState: ProcessInfo.ThermalState = .nominal

    private init() {}

    deinit {
        if smcConn != 0 { IOServiceClose(smcConn) }
    }

    func start() {
        smcConn = openSMC()
        smcAvailable = smcConn != 0
        poll()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run { self?.poll() }
            }
        }
        frameTimeTracker.start()
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
        frameTimeTracker.stop()
    }

    private func poll() {
        memory = readMemory()
        disk = readDisk()
        let newState = ProcessInfo.processInfo.thermalState
        thermalState = newState
        if newState != previousThermalState {
            thermalStateChanged(from: previousThermalState, to: newState)
            previousThermalState = newState
        }
        if smcConn != 0 {
            thermalReadings = readSensors()
            fanReadings = readFans()
        }
    }

    private func thermalStateChanged(from old: ProcessInfo.ThermalState, to new: ProcessInfo.ThermalState) {
        switch new {
        case .serious:
            NotificationManager.warning(
                title: "Thermal Throttling",
                message: "System is getting warm – performance may be reduced.",
                duration: 5
            )
        case .critical:
            NotificationManager.error(
                title: "Critical Temperature",
                message: "System is dangerously hot. Close games and let it cool down.",
                duration: 8
            )
        default:
            if old == .critical || old == .serious {
                NotificationManager.success(
                    title: "Temperature Normalized",
                    message: "System has cooled down to normal levels.",
                    duration: 3
                )
            }
        }
    }

    // MARK: - Memory

    private func readMemory() -> MemoryStats {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let total = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        guard result == KERN_SUCCESS else {
            return MemoryStats(totalGB: total, usedGB: 0, freeGB: 0,
                               wiredGB: 0, compressedGB: 0, pressure: .normal)
        }
        let ps = Double(vm_kernel_page_size)
        let free = Double(stats.free_count) * ps / 1_073_741_824
        let wired = Double(stats.wire_count) * ps / 1_073_741_824
        let compressed = Double(stats.compressor_page_count) * ps / 1_073_741_824
        let active = Double(stats.active_count) * ps / 1_073_741_824
        let used = active + wired + compressed
        let pressure: MemoryStats.MemoryPressure = {
            let r = used / total
            if r > 0.9 { return .critical }
            if r > 0.75 { return .warning }
            return .normal
        }()
        return MemoryStats(totalGB: total, usedGB: used, freeGB: free,
                           wiredGB: wired, compressedGB: compressed,
                           pressure: pressure)
    }

    // MARK: - Disk

    private func readDisk() -> DiskStats {
        var s = statfs()
        guard statfs("/", &s) == 0 else {
            return DiskStats(totalGB: 0, freeGB: 0, usedGB: 0)
        }
        let total = Double(s.f_blocks) * Double(s.f_bsize) / 1_073_741_824
        let free = Double(s.f_bfree) * Double(s.f_bsize) / 1_073_741_824
        return DiskStats(totalGB: total, freeGB: free, usedGB: total - free)
    }

    // MARK: - SMC

    private let sensorKeys: [(key: String, name: String)] = [
        ("Tp09", "CPU (M1/M2 P‑Core)"),
        ("Tp01", "CPU (M1/M2 E‑Core)"),
        ("Tp0D", "CPU (M1/M2)"),
        ("Tp0T", "CPU (M1/M2 L2)"),
        ("Tc05", "CPU (M3 E‑Core)"),
        ("Tf09", "CPU (M3)"),
        ("Te05", "CPU (M3 Performance)"),
        ("Tg0G", "GPU (M4)"),
        ("Tg0H", "GPU (M4)"),
        ("Tg1U", "GPU (M4)"),
        ("Tg0j", "GPU (M2)"),
        ("Tg0f", "GPU (M3)"),
        ("Tg0L", "GPU (M1)"),
        ("TC0P", "CPU Proximity (Intel)"),
        ("TC0E", "CPU (Intel)"),
        ("TG0P", "GPU Proximity (Intel)"),
        ("TG0D", "GPU Die (Intel)"),
        ("TM0P", "Memory Proximity"),
    ]

    private func openSMC() -> io_connect_t {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return 0 }
        var conn: io_connect_t = 0
        let ret = IOServiceOpen(service, mach_task_self_, 0, &conn)
        IOObjectRelease(service)
        return ret == kIOReturnSuccess ? conn : 0
    }

    private func readSensors() -> [ThermalReading] {
        sensorKeys.compactMap { kv in
            guard let val = smcRead(kv.key) else { return nil }
            return ThermalReading(name: kv.name, temperatureCelsius: val, key: kv.key)
        }
    }

    private func readFans() -> [FanReading] {
        guard let count = smcReadInt("FNum"), count > 0 else { return [] }
        var fans: [FanReading] = []
        for i in 0..<min(count, 5) {
            let id = "F\(i)"
            guard let rpm = smcReadInt("F\(id)Ac"),
                  let minVal = smcReadInt("F\(id)Mn"),
                  let maxVal = smcReadInt("F\(id)Mx") else { continue }
            let name = "Fan \(i)"
            fans.append(FanReading(name: name, rpm: rpm, minRPM: minVal, maxRPM: maxVal))
        }
        return fans
    }

    private func smcReadInt(_ key: String) -> Int? {
        guard let val = smcRead(key) else { return nil }
        return Int(val)
    }

    private func smcRead(_ key: String) -> Double? {
        var input = SMCParamStruct()
        var output = SMCParamStruct()

        // Step 1: Get key info
        input.key = fourCharCode(from: key)
        input.data8 = SMCKeyGetKeyInfo
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        guard IOConnectCallStructMethod(smcConn, UInt32(SMCSelector), &input,
                                         MemoryLayout<SMCParamStruct>.stride,
                                         &output, &outputSize) == kIOReturnSuccess,
              output.result == 0 else { return nil }

        let dataType = output.keyInfo.dataType
        let dataSize = output.keyInfo.dataSize

        // Step 2: Read value
        input = SMCParamStruct()
        input.key = fourCharCode(from: key)
        input.keyInfo.dataSize = dataSize
        input.data8 = SMCKeyReadValue
        outputSize = MemoryLayout<SMCParamStruct>.stride
        guard IOConnectCallStructMethod(smcConn, UInt32(SMCSelector), &input,
                                         MemoryLayout<SMCParamStruct>.stride,
                                         &output, &outputSize) == kIOReturnSuccess,
              output.result == 0 else { return nil }

        return decodeSMCValue(dataType: dataType, bytes: output.bytes)
    }
}

// MARK: - SMC Protocol

private let SMCSelector = 2
private let SMCKeyGetKeyInfo: UInt8 = 5
private let SMCKeyReadValue: UInt8 = 6

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private typealias SMCBytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                              UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                              UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                              UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

private struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                           0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

private func fourCharCode(from string: String) -> UInt32 {
    var code: UInt32 = 0
    for char in string.utf8 { code = (code << 8) | UInt32(char) }
    return code
}

private func decodeSMCValue(dataType: UInt32, bytes: SMCBytes) -> Double? {
    let b0 = UInt32(bytes.0)
    let b1 = UInt32(bytes.1)
    let b2 = UInt32(bytes.2)
    let b3 = UInt32(bytes.3)
    switch dataType {
    case 0x666c7420: // "flt "
        let bits = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
        return Double(Float(bitPattern: bits))
    case 0x66626532: // "fpe2"
        let val = (UInt16(bytes.0) << 8) | UInt16(bytes.1)
        return Double(val) / 4.0
    case 0x73703738: // "sp78"
        let intPart = Int16(bitPattern: UInt16(bytes.0))
        return Double(intPart) + Double(bytes.1) / 256.0
    case 0x75693332: // "ui32"
        let val = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
        return Double(val)
    case 0x75693820: // "ui8 "
        return Double(bytes.0)
    default:
        return nil
    }
}

// MARK: - View

struct HardwareMonitorView: View {
    @StateObject private var monitor = HardwareMonitor.shared
    @StateObject private var ft = HardwareMonitor.shared.frameTimeTracker

    var body: some View {
        VStack(spacing: 8) {
            // Thermal State
            HStack {
                Image(systemName: thermalIcon).foregroundColor(thermalColor)
                Text(thermalLabel).font(.caption)
                Spacer()
            }
            .padding(.horizontal)

            Divider()

            // Memory
            if let mem = monitor.memory {
                GroupBox {
                    bar(ratio: mem.usedGB / mem.totalGB, color: memColor)
                    HStack {
                        Text(verbatim: "\(String(format: "%.1f", mem.usedGB))/\(String(format: "%.1f", mem.totalGB)) GB")
                            .font(.caption2)
                        Spacer()
                        Text(verbatim: "\(Int(mem.usedGB / mem.totalGB * 100))%")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    HStack(spacing: 12) {
                        chip("Free", "\(String(format: "%.1f", mem.freeGB))")
                        chip("Wired", "\(String(format: "%.1f", mem.wiredGB))")
                        chip("Compressed", "\(String(format: "%.1f", mem.compressedGB))")
                    }
                    .font(.caption2).foregroundColor(.secondary)
                } label: { Label("Memory", systemImage: "memorychip") }
                .padding(.horizontal)
            }

            // Disk
            if let d = monitor.disk {
                GroupBox {
                    bar(ratio: d.usedGB / d.totalGB, color: .blue)
                    HStack {
                        Text(verbatim: "\(String(format: "%.1f", d.usedGB))/\(String(format: "%.1f", d.totalGB)) GB")
                            .font(.caption2)
                        Spacer()
                        Text(verbatim: "\(Int(d.usedGB / d.totalGB * 100))%")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                } label: { Label("Disk", systemImage: "internaldrive") }
                .padding(.horizontal)
            }

            // Temperatures
            if !monitor.thermalReadings.isEmpty {
                GroupBox {
                    VStack(spacing: 4) {
                        ForEach(monitor.thermalReadings) { r in
                            HStack(spacing: 8) {
                                Image(systemName: "thermometer").frame(width: 16)
                                Text(r.name).font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(String(format: "%.1f°C", r.temperatureCelsius ?? 0))
                                    .font(.caption).bold()
                                    .frame(width: 60, alignment: .trailing)
                                let rt = (r.temperatureCelsius ?? 0) / 100.0
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.gray.opacity(0.15)).frame(height: 8)
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(tempColor(rt))
                                            .frame(width: geo.size.width * min(rt, 1), height: 8)
                                    }
                                }
                                .frame(width: 50)
                            }
                        }
                    }
                } label: { Label("Temperatures", systemImage: "cpu") }
                .padding(.horizontal)
            }

            // Fans
            if !monitor.fanReadings.isEmpty {
                GroupBox {
                    VStack(spacing: 4) {
                        ForEach(monitor.fanReadings) { fan in
                            HStack(spacing: 8) {
                                Image(systemName: "fanblades").frame(width: 16)
                                Text(fan.name).frame(width: 50, alignment: .leading)
                                Text("\(fan.rpm) RPM")
                                    .font(.caption).bold()
                                    .frame(width: 70, alignment: .trailing)
                                let ratio = Double(fan.rpm - fan.minRPM) / Double(max(fan.maxRPM - fan.minRPM, 1))
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.gray.opacity(0.15)).frame(height: 8)
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.blue.opacity(0.7))
                                            .frame(width: geo.size.width * min(ratio, 1), height: 8)
                                    }
                                }
                                .frame(width: 50)
                            }
                            .font(.caption)
                        }
                    }
                } label: { Label("Fans", systemImage: "fanblades") }
                .padding(.horizontal)
            }

            // Frame Time
            GroupBox {
                HStack(spacing: 16) {
                    VStack(alignment: .trailing) {
                        Text(String(format: "%.0f", ft.fps)).font(.title2).bold()
                        Text("FPS").font(.caption2).foregroundColor(.secondary)
                    }
                    Divider().frame(height: 30)
                    VStack(alignment: .trailing) {
                        Text(String(format: "%.1f", ft.frameTimeMs)).font(.caption).bold()
                        Text("Avg ms").font(.caption2).foregroundColor(.secondary)
                    }
                    VStack(alignment: .trailing) {
                        Text(String(format: "%.1f", ft.onePercentLowMs)).font(.caption).bold()
                        Text("1% Low").font(.caption2).foregroundColor(.secondary)
                    }
                    VStack(alignment: .trailing) {
                        Text(String(format: "%.1f", ft.zeroOnePercentLowMs)).font(.caption).bold()
                        Text("0.1% Low").font(.caption2).foregroundColor(.secondary)
                    }
                }
            } label: { Label("Frame Time", systemImage: "play.rectangle") }
            .padding(.horizontal)
        }
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    // MARK: - Helpers

    private var thermalIcon: String {
        switch monitor.thermalState {
        case .nominal: return "thermometer"
        case .fair: return "thermometer.low"
        case .serious: return "thermometer.medium"
        case .critical: return "thermometer.high"
        @unknown default: return "thermometer"
        }
    }

    private var thermalColor: Color {
        switch monitor.thermalState {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .secondary
        }
    }

    private var thermalLabel: String {
        switch monitor.thermalState {
        case .nominal: return "Normal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "?"
        }
    }

    private var memColor: Color {
        guard let m = monitor.memory else { return .blue }
        switch m.pressure {
        case .normal: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private func tempColor(_ ratio: Double) -> Color {
        if ratio < 0.5 { return .green }
        if ratio < 0.75 { return .yellow }
        return .red
    }

    private func chip(_ name: String, _ value: String) -> some View {
        HStack(spacing: 2) {
            Text(verbatim: "\(name):").foregroundColor(.secondary)
            Text(verbatim: value)
        }
    }

    private func bar(ratio: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.15)).frame(height: 10)
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: geo.size.width * min(ratio, 1), height: 10)
            }
        }
        .frame(height: 10)
    }
}
