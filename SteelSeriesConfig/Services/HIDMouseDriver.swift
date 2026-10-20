import Foundation
import IOKit
import IOKit.hid

/// Direct HID transport to a supported mouse — the replacement for the GG engine.
///
/// One `IOHIDManager`, scheduled on the main run loop, matches every model in
/// `AeroxProtocol.models`. Over USB only the vendor interface (interface 3) accepts
/// configuration reports. Over Bluetooth the mouse is a single HID device whose vendor
/// collection uses report id 4; because that device also carries a keyboard
/// collection, macOS only lets the app open it with Input Monitoring permission.
@MainActor
final class HIDMouseDriver {

    struct Attached: Equatable {
        let device: IOHIDDevice
        let model: AeroxProtocol.Model
        let outputReportSize: Int
    }

    enum DriverError: Error, LocalizedError {
        case notConnected
        case needsInputMonitoring
        case writeFailed(IOReturn)

        var errorDescription: String? {
            switch self {
            case .notConnected:
                return "The mouse is not connected."
            case .needsInputMonitoring:
                return "Allow SteelSeries Config under System Settings → Privacy & Security → Input Monitoring to change settings over Bluetooth."
            case .writeFailed(let code):
                return String(format: "The mouse rejected the command (IOReturn 0x%08X).", code)
            }
        }
    }

    static let shared = HIDMouseDriver()

    /// The firmware drops commands that arrive back to back (rivalcfg uses 50 ms).
    static let commandDelay: Duration = .milliseconds(50)
    static let responseTimeout: Duration = .milliseconds(250)

    private let manager: IOHIDManager
    private var inputDevice: IOHIDDevice?
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 128)
    private var inputReports: [(id: UInt32, bytes: [UInt8])] = []
    private var isOpen = false
    private var requestedAccess = false

    private init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching = AeroxProtocol.models.map {
            [kIOHIDVendorIDKey: $0.vendorID, kIOHIDProductIDKey: $0.productID] as CFDictionary
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        openIfPossible()
    }

    /// Opening fails with `kIOReturnNotPermitted` until Input Monitoring is granted when
    /// a Bluetooth mouse is attached; enumeration still works, so presence is known.
    private func openIfPossible() {
        guard !isOpen else { return }
        isOpen = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess
    }

    /// Whether settings can be written right now. Asks for Input Monitoring once, the
    /// first time a Bluetooth mouse needs it.
    func ensureWritable(_ mouse: Attached) throws {
        openIfPossible()
        guard !isOpen, mouse.model.transport == .bluetooth else { return }
        if !requestedAccess, IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
            requestedAccess = true
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        throw DriverError.needsInputMonitoring
    }

    /// The configurable interface of the first supported mouse, or `nil`.
    func attached() -> Attached? {
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return nil }
        let candidates = set.compactMap { device -> (Attached, Int?)? in
            guard let vid = Self.intProperty(device, kIOHIDVendorIDKey),
                  let pid = Self.intProperty(device, kIOHIDProductIDKey),
                  let model = AeroxProtocol.model(vendorID: vid, productID: pid),
                  let size = Self.intProperty(device, kIOHIDMaxOutputReportSizeKey), size > 0
            else { return nil }
            let attached = Attached(device: device, model: model, outputReportSize: size)
            // A Bluetooth mouse is one HID device, so there is no interface to pick.
            if model.transport == .bluetooth { return (attached, AeroxProtocol.interfaceNumber) }
            return (attached, Self.interfaceNumber(of: device))
        }
        // Prefer the documented interface; fall back to any vendor-page interface
        // when the registry does not expose an interface number.
        if let exact = candidates.first(where: { $0.1 == AeroxProtocol.interfaceNumber }) {
            return exact.0
        }
        return candidates.first {
            $0.1 == nil && (Self.intProperty($0.0.device, kIOHIDPrimaryUsagePageKey) ?? 0) >= 0xFF00
        }?.0
    }

    /// Send one command, then wait the inter-command delay.
    func send(_ command: [UInt8], to mouse: Attached) async throws {
        try ensureWritable(mouse)
        let reportID = Self.reportID(for: mouse)
        var report = AeroxProtocol.addressed(command, wireless: mouse.model.isWireless)
        // A numbered report is sent with its id as the first byte.
        if reportID != 0 { report.insert(UInt8(reportID), at: 0) }
        if report.count < mouse.outputReportSize {
            report += [UInt8](repeating: 0, count: mouse.outputReportSize - report.count)
        }
        let result = report.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(mouse.device, kIOHIDReportTypeOutput, reportID, $0.baseAddress!, $0.count)
        }
        guard result == kIOReturnSuccess else { throw DriverError.writeFailed(result) }
        try? await Task.sleep(for: Self.commandDelay)
    }

    /// Send a command and return the first input report that follows it, or `nil`
    /// when the mouse does not answer (asleep, off, or out of range).
    func query(_ command: [UInt8], to mouse: Attached) async throws -> [UInt8]? {
        listen(to: mouse.device)
        inputReports.removeAll()
        try await send(command, to: mouse)

        // Over Bluetooth the same device also streams pointer reports (id 1); only the
        // vendor collection's reports are answers, and their id byte is stripped.
        let reportID = Self.reportID(for: mouse)
        let deadline = ContinuousClock.now + Self.responseTimeout
        while ContinuousClock.now < deadline {
            if let answer = inputReports.first(where: { reportID == 0 || $0.id == UInt32(reportID) }) {
                return reportID != 0 && answer.bytes.first == UInt8(reportID) ? Array(answer.bytes.dropFirst()) : answer.bytes
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }

    private static func reportID(for mouse: Attached) -> CFIndex {
        mouse.model.transport == .bluetooth ? CFIndex(AeroxProtocol.bluetoothReportID) : 0
    }

    private func listen(to device: IOHIDDevice) {
        guard inputDevice != device else { return }
        inputDevice = device
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, 128, { context, _, _, _, id, report, length in
            guard let context else { return }
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            MainActor.assumeIsolated {
                let driver = Unmanaged<HIDMouseDriver>.fromOpaque(context).takeUnretainedValue()
                if driver.inputReports.count < 64 { driver.inputReports.append((id, bytes)) }
            }
        }, context)
    }

    private static func intProperty(_ device: IOHIDDevice, _ key: String) -> Int? {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
    }

    /// `bInterfaceNumber` lives on the USB interface above the HID service.
    private static func interfaceNumber(of device: IOHIDDevice) -> Int? {
        let service = IOHIDDeviceGetService(device)
        guard service != IO_OBJECT_NULL else { return nil }
        let value = IORegistryEntrySearchCFProperty(
            service,
            kIOServicePlane,
            "bInterfaceNumber" as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        )
        return (value as? NSNumber)?.intValue
    }
}
