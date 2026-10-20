import Foundation

/// Wire protocol of the SteelSeries Aerox 3 Wireless, spoken directly over HID.
///
/// Every byte here is taken from rivalcfg (github.com/flozz/rivalcfg,
/// `devices/aerox3_wireless_{wired,wireless}.py` and its handlers), and
/// `AeroxProtocolTests` pins the encoders to bytes produced by rivalcfg itself.
/// The functions are pure so they can be tested without a mouse attached.
///
/// The protocol is write-only for settings: the mouse cannot report its CPI ladder,
/// polling rate or lighting back, which is why the app keeps its own profile file.
enum AeroxProtocol {

    enum Transport: Equatable, Sendable {
        case usb
        /// The 2.4 GHz receiver.
        case receiver
        /// Bluetooth LE. The mouse then reports SteelSeries' Bluetooth company id as
        /// its vendor and exposes one combined HID device whose vendor collection
        /// (usage page 0xFFC0) uses report id 4.
        case bluetooth
    }

    struct Model: Equatable, Sendable {
        let vendorID: Int
        let productID: Int
        let name: String
        let transport: Transport

        /// Only the receiver needs the `0x40` flag on each command.
        var isWireless: Bool { transport == .receiver }

        /// Bundled product artwork — the same image SteelSeries GG shows for this model
        /// (`loadoutImages/devices/aerox_3*.webp`, converted to PNG).
        var imageName: String {
            name.contains("Dragon Lore") ? "DeviceAerox3DragonLore" : "DeviceAerox3"
        }
    }

    static let vendorID = 0x1038
    static let bluetoothVendorID = 0x0111
    /// The vendor interface on USB; the others are the pointer and keyboard interfaces.
    static let interfaceNumber = 3
    /// Report id of the vendor collection over Bluetooth (from the HID descriptor).
    static let bluetoothReportID = 4

    static let models: [Model] = [
        Model(vendorID: vendorID, productID: 0x183A, name: "Aerox 3 Wireless", transport: .usb),
        Model(vendorID: vendorID, productID: 0x1838, name: "Aerox 3 Wireless", transport: .receiver),
        Model(vendorID: bluetoothVendorID, productID: 0x183A, name: "Aerox 3 Wireless", transport: .bluetooth),
        Model(vendorID: vendorID, productID: 0x187A, name: "Aerox 3 Wireless CS2 Dragon Lore", transport: .usb),
        Model(vendorID: vendorID, productID: 0x1878, name: "Aerox 3 Wireless CS2 Dragon Lore", transport: .receiver),
    ]

    static func model(vendorID: Int, productID: Int) -> Model? {
        models.first { $0.vendorID == vendorID && $0.productID == productID }
    }

    /// Over the receiver every command is flagged with this bit on its first byte.
    static let wirelessFlag: UInt8 = 0x40

    // MARK: - Commands

    static let saveToFlash: [UInt8] = [0x11, 0x00]
    static let batteryQuery: [UInt8] = [0x92]

    /// CPI ladder: count, active index (zero-based), then one sensor code per step.
    static func sensitivity(levels: [Int], activeIndex: Int) -> [UInt8] {
        let steps = Array(levels.prefix(maxCPILevels))
        let active = min(max(activeIndex, 0), max(steps.count - 1, 0))
        return [0x2D, UInt8(steps.count), UInt8(active)] + steps.map(cpiCode)
    }

    static func pollingRate(hz: Int) -> [UInt8] {
        let code: UInt8
        switch hz {
        case 125: code = 0x03
        case 250: code = 0x02
        case 500: code = 0x01
        default: code = 0x00
        }
        return [0x2B, code]
    }

    /// Idle time before the mouse sleeps, in milliseconds (0 disables, max 20 min).
    static func sleepTimer(milliseconds: Int) -> [UInt8] {
        [0x29] + littleEndian24(min(max(milliseconds, 0), maxTimerMilliseconds))
    }

    /// Idle time before the lighting dims, in milliseconds (0 disables, max 20 min).
    static func dimTimer(milliseconds: Int) -> [UInt8] {
        [0x23, 0x0F, 0x01, 0x00, 0x00] + littleEndian24(min(max(milliseconds, 0), maxTimerMilliseconds))
    }

    /// Colour flashed on a click, or `nil` to disable reactive lighting.
    static func reactiveColor(_ color: (red: Int, green: Int, blue: Int)?) -> [UInt8] {
        guard let color else { return [0x26, 0x00, 0x00, 0x00, 0x00, 0x00] }
        return [0x26, 0x01, 0x00, byte(color.red), byte(color.green), byte(color.blue)]
    }

    /// Lighting the mouse falls back to on power-up.
    static func defaultLighting(rainbow: Bool, reactive: Bool) -> [UInt8] {
        [0x27, rainbow ? 0x01 : 0x00, reactive ? 0x01 : 0x00]
    }

    /// Button map: eight five-byte slots (B1…B6, scroll up, scroll down).
    ///
    /// The engine's `function` codes for the actions this mouse supports (1…5, 48 CPI
    /// toggle, 49/50 scroll) are the same bytes the firmware expects. Anything else
    /// falls back to the slot's factory action rather than sending a guessed code.
    static func buttons(functions: [Int]) -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: defaultButtonFunctions.count * 5)
        for (slot, fallback) in defaultButtonFunctions.enumerated() {
            let requested = slot < functions.count ? functions[slot] : fallback
            let code = supportedButtonFunctions.contains(requested) ? requested : fallback
            packet[slot * 5] = UInt8(code)
        }
        return [0x2A] + packet
    }

    static let defaultButtonFunctions = [1, 2, 3, 4, 5, 48, 49, 50]
    static let supportedButtonFunctions: Set<Int> = [0, 1, 2, 3, 4, 5, 48, 49, 50]

    /// Mark a command for the receiver.
    static func addressed(_ command: [UInt8], wireless: Bool) -> [UInt8] {
        guard wireless, let first = command.first else { return command }
        return [first | wirelessFlag] + command.dropFirst()
    }

    /// Every setting this app models, in a fixed order so two lists can be diffed
    /// position by position to send only what changed.
    static func commands(for settings: MouseSettings) -> [[UInt8]] {
        let count = settings.cpiLevelCount
        return [
            sensitivity(
                levels: Array(settings.cpiLevels.prefix(count)),
                activeIndex: settings.activeCPILevelIndex
            ),
            pollingRate(hz: settings.pollingRateHz),
            sleepTimer(milliseconds: settings.powerSaveSeconds * 1000),
            dimTimer(milliseconds: settings.idleTimeoutSeconds * 1000),
            reactiveColor(settings.reactiveLightingEnabled ? settings.reactiveColor : nil),
            defaultLighting(
                rainbow: settings.defaultLightingEnabled,
                reactive: settings.reactiveLightingEnabled
            ),
            buttons(functions: settings.buttons.map(\.function)),
        ]
    }

    // MARK: - Battery

    /// Parse the answer to `batteryQuery`. `nil` means no usable reading — over the
    /// receiver that is a mouse that is off, asleep or out of range.
    static func battery(response: [UInt8]) -> BatteryStatus? {
        guard response.count >= 2 else { return nil }
        let raw = response[1]
        let level = (Int(raw & 0x7F) - 1) * 5
        guard (0...100).contains(level) else { return nil }
        let charging = raw & 0x80 != 0
        return BatteryStatus(percent: level, isCharging: charging, isCharged: charging && level >= 100)
    }

    // MARK: - Encoding helpers

    static let maxCPILevels = 5
    static let cpiMinimum = 100
    static let cpiMaximum = 18_000
    static let maxTimerMilliseconds = 0x124F80

    /// Sensor code for a CPI value, nearest table entry (ties round down, as rivalcfg).
    static func cpiCode(_ cpi: Int) -> UInt8 {
        let index = min(max((cpi + 49) / 100, 1), cpiCodes.count) - 1
        return cpiCodes[index]
    }

    private static func byte(_ value: Int) -> UInt8 { UInt8(min(max(value, 0), 255)) }

    private static func littleEndian24(_ value: Int) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF)]
    }

    /// TrueMove Air sensor codes for 100…18000 CPI in steps of 100
    /// (rivalcfg `devices/dpi/truemove_air.py`).
    static let cpiCodes: [UInt8] = [
        0x00, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x09, 0x0A, 0x0B, 0x0C, 0x0D,
        0x0E, 0x10, 0x11, 0x12, 0x13, 0x14, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B,
        0x1D, 0x1E, 0x1F, 0x20, 0x21, 0x23, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2A,
        0x2C, 0x2D, 0x2E, 0x2F, 0x30, 0x32, 0x33, 0x34, 0x35, 0x36, 0x38, 0x39,
        0x3A, 0x3B, 0x3C, 0x3E, 0x3F, 0x40, 0x41, 0x42, 0x44, 0x45, 0x46, 0x47,
        0x48, 0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x50, 0x51, 0x52, 0x53, 0x54, 0x56,
        0x57, 0x58, 0x59, 0x5A, 0x5C, 0x5D, 0x5E, 0x5F, 0x60, 0x62, 0x63, 0x64,
        0x65, 0x66, 0x68, 0x69, 0x6A, 0x6B, 0x6C, 0x6E, 0x6F, 0x70, 0x71, 0x72,
        0x74, 0x75, 0x76, 0x77, 0x78, 0x7A, 0x7B, 0x7C, 0x7D, 0x7E, 0x80, 0x81,
        0x82, 0x83, 0x84, 0x86, 0x87, 0x88, 0x89, 0x8A, 0x8C, 0x8D, 0x8E, 0x8F,
        0x90, 0x92, 0x93, 0x94, 0x95, 0x96, 0x98, 0x99, 0x9A, 0x9B, 0x9C, 0x9E,
        0x9F, 0xA0, 0xA1, 0xA2, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xAA, 0xAB, 0xAC,
        0xAD, 0xAE, 0xB0, 0xB1, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9,
        0xBA, 0xBB, 0xBC, 0xBD, 0xBF, 0xC0, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7,
        0xC9, 0xCA, 0xCB, 0xCC, 0xCD, 0xCF, 0xD0, 0xD1, 0xD2, 0xD3, 0xD5, 0xD6
    ]
}
