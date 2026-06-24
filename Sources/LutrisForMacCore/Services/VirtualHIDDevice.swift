import Foundation
import GameController
import Darwin
import OSLog

// ================================================================
// VirtualHIDDevice.swift
// ================================================================
// Erzeugt ein systemweites virtuelles HID-Gamepad via IOHIDUserDevice.
// HID-Report-Deskriptor: 16 Taster, 1 Hat-Switch, 4 Achsen, 2 Trigger
// Report-Format (10 Byte):
//   [0-1]  16 Button-Bits (A,B,X,Y,LB,RB,Back,Start,L3,R3,…)
//   [2]    Hat Switch  (0-7) + 4 Bit Padding
//   [3]    Left Trigger
//   [4]    Right Trigger
//   [5]    Left Stick X
//   [6]    Left Stick Y
//   [7]    Right Stick X
//   [8]    Right Stick Y
//   [9]    (reserved)
// ================================================================

private let log = Logger(subsystem: "net.lutrisformac", category: "VirtualHID")

// MARK: - IOHIDUserDevice C-Funktionen via dlsym

private let IOKitHandle: UnsafeMutableRawPointer = {
    let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL)
    precondition(h != nil, "IOKit.framework konnte nicht geladen werden")
    return h!
}()

private let IOHIDUserDeviceCreateWithProperties_fp: CreateWithPropertiesFunc = {
    let sym = dlsym(IOKitHandle, "IOHIDUserDeviceCreateWithProperties")
    precondition(sym != nil, "IOHIDUserDeviceCreateWithProperties nicht gefunden")
    return unsafeBitCast(sym, to: CreateWithPropertiesFunc.self)
}()

private let IOHIDUserDeviceRegisterGetReportBlock_fp: RegisterGetReportBlockFunc = {
    let sym = dlsym(IOKitHandle, "IOHIDUserDeviceRegisterGetReportBlock")
    precondition(sym != nil, "IOHIDUserDeviceRegisterGetReportBlock nicht gefunden")
    return unsafeBitCast(sym, to: RegisterGetReportBlockFunc.self)
}()

private let IOHIDUserDeviceRegisterSetReportBlock_fp: RegisterSetReportBlockFunc = {
    let sym = dlsym(IOKitHandle, "IOHIDUserDeviceRegisterSetReportBlock")
    precondition(sym != nil, "IOHIDUserDeviceRegisterSetReportBlock nicht gefunden")
    return unsafeBitCast(sym, to: RegisterSetReportBlockFunc.self)
}()

private let IOHIDUserDeviceSetDispatchQueue_fp: SetDispatchQueueFunc = {
    let sym = dlsym(IOKitHandle, "IOHIDUserDeviceSetDispatchQueue")
    precondition(sym != nil, "IOHIDUserDeviceSetDispatchQueue nicht gefunden")
    return unsafeBitCast(sym, to: SetDispatchQueueFunc.self)
}()

private let IOHIDUserDeviceActivate_fp: ActivateFunc = {
    let sym = dlsym(IOKitHandle, "IOHIDUserDeviceActivate")
    precondition(sym != nil, "IOHIDUserDeviceActivate nicht gefunden")
    return unsafeBitCast(sym, to: ActivateFunc.self)
}()

private let IOHIDUserDeviceCancel_fp: CancelFunc = {
    let sym = dlsym(IOKitHandle, "IOHIDUserDeviceCancel")
    precondition(sym != nil, "IOHIDUserDeviceCancel nicht gefunden")
    return unsafeBitCast(sym, to: CancelFunc.self)
}()

private let IOHIDUserDeviceHandleReportWithTimeStamp_fp: HandleReportWithTimeStampFunc = {
    let sym = dlsym(IOKitHandle, "IOHIDUserDeviceHandleReportWithTimeStamp")
    precondition(sym != nil, "IOHIDUserDeviceHandleReportWithTimeStamp nicht gefunden")
    return unsafeBitCast(sym, to: HandleReportWithTimeStampFunc.self)
}()

private let IOHIDUserDeviceSetCancelHandler_fp: SetCancelHandlerFunc = {
    let sym = dlsym(IOKitHandle, "IOHIDUserDeviceSetCancelHandler")
    precondition(sym != nil, "IOHIDUserDeviceSetCancelHandler nicht gefunden")
    return unsafeBitCast(sym, to: SetCancelHandlerFunc.self)
}()

// MARK: - C-Funktionstypen

private typealias IOHIDUserDeviceRef = OpaquePointer

private typealias IOHIDReportType = UInt32
private let kIOHIDReportTypeInput: IOHIDReportType = 0

private typealias GetReportBlock = @convention(block) (IOHIDReportType, CFIndex, UnsafeMutablePointer<UInt8>?, UnsafeMutablePointer<CFIndex>) -> IOReturn
private typealias SetReportBlock = @convention(block) (IOHIDReportType, CFIndex, UnsafePointer<UInt8>, CFIndex) -> IOReturn

private typealias CreateWithPropertiesFunc = @convention(c) (CFAllocator?, CFDictionary) -> IOHIDUserDeviceRef?
private typealias RegisterGetReportBlockFunc = @convention(c) (IOHIDUserDeviceRef, GetReportBlock) -> Void
private typealias RegisterSetReportBlockFunc = @convention(c) (IOHIDUserDeviceRef, SetReportBlock) -> Void
private typealias SetDispatchQueueFunc = @convention(c) (IOHIDUserDeviceRef, DispatchQueue) -> Void
private typealias ActivateFunc = @convention(c) (IOHIDUserDeviceRef) -> Void
private typealias CancelFunc = @convention(c) (IOHIDUserDeviceRef) -> Void
private typealias HandleReportWithTimeStampFunc = @convention(c) (IOHIDUserDeviceRef, IOHIDReportType, UInt64, UnsafePointer<UInt8>, CFIndex) -> IOReturn
private typealias SetCancelHandlerFunc = @convention(c) (IOHIDUserDeviceRef, @convention(block) () -> Void) -> Void

// MARK: - HID Report Descriptor

/// Standard-Gamepad HID Report Descriptor (10-Byte Report)
private let gamepadReportDescriptor: [UInt8] = [
    // Usage Page (Generic Desktop)
    0x05, 0x01,
    // Usage (Game Pad)
    0x09, 0x05,
    // Collection (Application)
    0xA1, 0x01,

    // ── 16 Taster ──
    0x05, 0x09,        // Usage Page (Button)
    0x19, 0x01,        // Usage Minimum (1)
    0x29, 0x10,        // Usage Maximum (16)
    0x15, 0x00,        // Logical Minimum (0)
    0x25, 0x01,        // Logical Maximum (1)
    0x75, 0x01,        // Report Size (1)
    0x95, 0x10,        // Report Count (16)
    0x81, 0x02,        // Input (Data,Var,Abs)

    // ── Hat Switch (4 Bit + 4 Bit Padding) ──
    0x05, 0x01,        // Usage Page (Generic Desktop)
    0x09, 0x39,        // Usage (Hat Switch)
    0x15, 0x00,        // Logical Minimum (0)
    0x25, 0x07,        // Logical Maximum (7)
    0x35, 0x00,        // Physical Minimum (0)
    0x46, 0x3B, 0x01,  // Physical Maximum (315)
    0x65, 0x14,        // Unit (Degrees)
    0x75, 0x04,        // Report Size (4)
    0x95, 0x01,        // Report Count (1)
    0x81, 0x42,        // Input (Data,Var,Abs,Null)
    // Padding
    0x75, 0x04,        // Report Size (4)
    0x95, 0x01,        // Report Count (1)
    0x81, 0x03,        // Input (Const,Var,Abs)

    // ── Left Trigger (8 Bit) ──
    0x05, 0x01,        // Usage Page (Generic Desktop)
    0x09, 0x32,        // Usage (Z)
    0x15, 0x00,        // Logical Minimum (0)
    0x26, 0xFF, 0x00,  // Logical Maximum (255)
    0x75, 0x08,        // Report Size (8)
    0x95, 0x01,        // Report Count (1)
    0x81, 0x02,        // Input (Data,Var,Abs)

    // ── Right Trigger (8 Bit) ──
    0x09, 0x35,        // Usage (Rz)
    0x15, 0x00,        // Logical Minimum (0)
    0x26, 0xFF, 0x00,  // Logical Maximum (255)
    0x75, 0x08,        // Report Size (8)
    0x95, 0x01,        // Report Count (1)
    0x81, 0x02,        // Input (Data,Var,Abs)

    // ── Left Stick X (8 Bit) ──
    0x09, 0x30,        // Usage (X)
    0x15, 0x00,        // Logical Minimum (0)
    0x26, 0xFF, 0x00,  // Logical Maximum (255)
    0x75, 0x08,        // Report Size (8)
    0x95, 0x01,        // Report Count (1)
    0x81, 0x02,        // Input (Data,Var,Abs)

    // ── Left Stick Y (8 Bit) ──
    0x09, 0x31,        // Usage (Y)
    0x15, 0x00,        // Logical Minimum (0)
    0x26, 0xFF, 0x00,  // Logical Maximum (255)
    0x75, 0x08,        // Report Size (8)
    0x95, 0x01,        // Report Count (1)
    0x81, 0x02,        // Input (Data,Var,Abs)

    // ── Right Stick X (8 Bit) ──
    0x09, 0x33,        // Usage (Rx)
    0x15, 0x00,        // Logical Minimum (0)
    0x26, 0xFF, 0x00,  // Logical Maximum (255)
    0x75, 0x08,        // Report Size (8)
    0x95, 0x01,        // Report Count (1)
    0x81, 0x02,        // Input (Data,Var,Abs)

    // ── Right Stick Y (8 Bit) ──
    0x09, 0x34,        // Usage (Ry)
    0x15, 0x00,        // Logical Minimum (0)
    0x26, 0xFF, 0x00,  // Logical Maximum (255)
    0x75, 0x08,        // Report Size (8)
    0x95, 0x01,        // Report Count (1)
    0x81, 0x02,        // Input (Data,Var,Abs)

    // ── Reserved (8 Bit) ──
    0x75, 0x08,        // Report Size (8)
    0x95, 0x01,        // Report Count (1)
    0x81, 0x03,        // Input (Const,Var,Abs)

    0xC0               // End Collection
]

// MARK: - HID-Report-Puffer (10 Byte)

private struct HIDReport {
    var buttons: UInt16 = 0   // [0-1]
    var hatAndPad: UInt8 = 0x0F // [2] hat = 0x0F = centered
    var leftTrigger: UInt8 = 0  // [3]
    var rightTrigger: UInt8 = 0 // [4]
    var leftX: UInt8 = 128      // [5]
    var leftY: UInt8 = 128      // [6]
    var rightX: UInt8 = 128     // [7]
    var rightY: UInt8 = 128     // [8]
    var reserved: UInt8 = 0     // [9]
}

// MARK: - VirtualHIDDevice

@MainActor
public final class VirtualHIDDevice {
    public let id: String
    public let name: String

    private let device: IOHIDUserDeviceRef
    private let queue: DispatchQueue
    private var isActive = false

    /// Mapping from GCController axis values (0.0…1.0) → UInt8
    private static func floatToUInt8(_ val: Float) -> UInt8 {
        UInt8(max(0, min(255, val * 255)))
    }

    /// Mapping from GCController axis values (-1.0…1.0) → UInt8 (0…255)
    private static func normalizedFloatToUInt8(_ val: Float) -> UInt8 {
        UInt8(max(0, min(255, (val + 1) * 127.5)))
    }

    /// Hat-Switch aus D-Pad-Werten (0 = centered, 1-8 = Richtungen)
    private static func hatFromDPad(up: Float, down: Float, left: Float, right: Float) -> UInt8 {
        let u = up > 0.5, d = down > 0.5, l = left > 0.5, r = right > 0.5
        if u && !d && !l && !r { return 0 }  // up
        if u && !d && !l && r { return 1 }   // up-right
        if !u && !d && !l && r { return 2 }  // right
        if d && !u && !l && r { return 3 }   // down-right
        if d && !u && !l && !r { return 4 }  // down
        if d && !u && l && !r { return 5 }   // down-left
        if !u && !d && l && !r { return 6 }  // left
        if u && !d && l && !r { return 7 }   // up-left
        return 0x0F // centered
    }

    // MARK: - Init

    public init?(id: String, name: String, vendorID: Int = 0x1234, productID: Int = 0x5678) {
        self.id = id
        self.name = name

        let reportData = Data(gamepadReportDescriptor)
        let props: CFDictionary = [
            kIOHIDVendorIDKey as String: vendorID,
            kIOHIDProductIDKey as String: productID,
            kIOHIDProductKey as String: "Lutris Virtual Gamepad – \(name)",
            kIOHIDTransportKey as String: "Virtual",
            kIOHIDPrimaryUsagePageKey as String: 0x01,
            kIOHIDPrimaryUsageKey as String: 0x05,
            kIOHIDReportDescriptorKey as String: reportData,
            kIOHIDLocationIDKey as String: id.hash,
        ] as CFDictionary

        guard let dev = IOHIDUserDeviceCreateWithProperties_fp(kCFAllocatorDefault, props) else {
            log.error("IOHIDUserDeviceCreateWithProperties fehlgeschlagen")
            return nil
        }
        device = dev
        queue = DispatchQueue(label: "virtual-hid-\(id)", qos: .userInteractive)

        // GetReport-Block (wird vom System gefragt, wenn ein Programm den initialen Report lesen will)
        IOHIDUserDeviceRegisterGetReportBlock_fp(device) { _, _, _, _ in
            kIOReturnUnsupported
        }

        // SetReport-Block (wird bei Output/Feature-Reports aufgerufen)
        IOHIDUserDeviceRegisterSetReportBlock_fp(device) { _, _, _, _ in
            kIOReturnUnsupported
        }

        IOHIDUserDeviceSetDispatchQueue_fp(device, queue)
        IOHIDUserDeviceSetCancelHandler_fp(device) { [weak self] in
            Task { @MainActor in
                log.info("Virtual HID device cancelled: \(self?.name ?? "?")")
            }
        }

        IOHIDUserDeviceActivate_fp(device)
        isActive = true

        log.info("Virtual HID device created: \(name) (\(id))")
    }

    deinit {
        if isActive {
            isActive = false
            IOHIDUserDeviceCancel_fp(device)
        }
    }

    // MARK: - Send Report

    /// Sendet einen vollständigen HID-Report aus dem aktuellen GCController-Zustand.
    /// Wendet vorher das aktive Button-Remapping an.
    public func sendReport(from gamepad: GCExtendedGamepad, remap sourceToTarget: [String: String]) {
        guard isActive else { return }

        // 1) Button-Zustände auslesen (nach IDs)
        var buttonStates: [String: Bool] = [:]
        buttonStates["buttonA"] = gamepad.buttonA.isPressed
        buttonStates["buttonB"] = gamepad.buttonB.isPressed
        buttonStates["buttonX"] = gamepad.buttonX.isPressed
        buttonStates["buttonY"] = gamepad.buttonY.isPressed
        buttonStates["leftShoulder"] = gamepad.leftShoulder.isPressed
        buttonStates["rightShoulder"] = gamepad.rightShoulder.isPressed
        buttonStates["leftTrigger"] = gamepad.leftTrigger.isPressed
        buttonStates["rightTrigger"] = gamepad.rightTrigger.isPressed
        buttonStates["leftThumbstickButton"] = gamepad.leftThumbstickButton?.isPressed ?? false
        buttonStates["rightThumbstickButton"] = gamepad.rightThumbstickButton?.isPressed ?? false
        buttonStates["buttonMenu"] = gamepad.buttonMenu.isPressed
        buttonStates["buttonOptions"] = gamepad.buttonOptions?.isPressed ?? false

        // 2) Remapping anwenden
        var remapped: [String: Bool] = [:]
        for (id, pressed) in buttonStates {
            let targetID = sourceToTarget[id] ?? id
            remapped[targetID] = (remapped[targetID] ?? false) || pressed
        }

        // 3) Report bauen
        var report = HIDReport()
        report.buttons = buttonBits(remapped)
        report.hatAndPad = Self.hatFromDPad(
            up: gamepad.dpad.up.value,
            down: gamepad.dpad.down.value,
            left: gamepad.dpad.left.value,
            right: gamepad.dpad.right.value
        ) << 4  // Hat im oberen Nibble, Padding unten
        report.leftTrigger = Self.floatToUInt8(gamepad.leftTrigger.value)
        report.rightTrigger = Self.floatToUInt8(gamepad.rightTrigger.value)
        report.leftX = Self.normalizedFloatToUInt8(gamepad.leftThumbstick.xAxis.value)
        report.leftY = Self.normalizedFloatToUInt8(gamepad.leftThumbstick.yAxis.value)
        report.rightX = Self.normalizedFloatToUInt8(gamepad.rightThumbstick.xAxis.value)
        report.rightY = Self.normalizedFloatToUInt8(gamepad.rightThumbstick.yAxis.value)

        // 4) Report senden
        let now = mach_continuous_time()
        withUnsafePointer(to: report) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<HIDReport>.size) { buf in
                let ret = IOHIDUserDeviceHandleReportWithTimeStamp_fp(device, kIOHIDReportTypeInput, now, buf, CFIndex(MemoryLayout<HIDReport>.size))
                if ret != kIOReturnSuccess {
                    log.error("HandleReport fehlgeschlagen: \(ret)")
                }
            }
        }
    }

    // MARK: - Cancel

    public func cancel() {
        guard isActive else { return }
        isActive = false
        IOHIDUserDeviceCancel_fp(device)
        log.info("Virtual HID device destroyed: \(self.name)")
    }

    // MARK: - Helpers

    private func buttonBits(_ states: [String: Bool]) -> UInt16 {
        var bits: UInt16 = 0
        if states["buttonA"] ?? false { bits |= 1 << 0 }
        if states["buttonB"] ?? false { bits |= 1 << 1 }
        if states["buttonX"] ?? false { bits |= 1 << 2 }
        if states["buttonY"] ?? false { bits |= 1 << 3 }
        if states["leftShoulder"] ?? false { bits |= 1 << 4 }
        if states["rightShoulder"] ?? false { bits |= 1 << 5 }
        if states["leftThumbstickButton"] ?? false { bits |= 1 << 6 }
        if states["rightThumbstickButton"] ?? false { bits |= 1 << 7 }
        if states["buttonMenu"] ?? false { bits |= 1 << 8 }
        if states["buttonOptions"] ?? false { bits |= 1 << 9 }
        return bits
    }
}
