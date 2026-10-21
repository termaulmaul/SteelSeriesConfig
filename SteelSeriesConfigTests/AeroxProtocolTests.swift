import XCTest
@testable import SteelSeriesConfig

/// Pins every encoder to bytes produced by rivalcfg itself (`pip install rivalcfg`,
/// `handlers.*.process_value` against `devices.aerox3_wireless_wired.profile`), so the
/// app speaks exactly the protocol a known-good open-source driver speaks.
final class AeroxProtocolTests: XCTestCase {

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    func testCPICodeTableCoversTheSensorRange() {
        XCTAssertEqual(AeroxProtocol.cpiCodes.count, 180, "100…18000 in steps of 100.")
        XCTAssertEqual(AeroxProtocol.cpiCode(100), 0x00)
        XCTAssertEqual(AeroxProtocol.cpiCode(18_000), 0xD6)
    }

    func testSensitivityMatchesRivalcfg() {
        XCTAssertEqual(
            hex(AeroxProtocol.sensitivity(levels: [400, 800, 1200, 2400, 3200], activeIndex: 0)),
            "2D 05 00 04 09 0D 1B 26"
        )
        XCTAssertEqual(hex(AeroxProtocol.sensitivity(levels: [18_000, 100], activeIndex: 1)), "2D 02 01 D6 00")
    }

    /// rivalcfg snaps to the nearest table entry with ties going down: 450 → 400.
    func testOffGridCPIRoundsToNearestWithTiesDown() {
        XCTAssertEqual(AeroxProtocol.cpiCode(450), AeroxProtocol.cpiCode(400))
        XCTAssertEqual(AeroxProtocol.cpiCode(451), AeroxProtocol.cpiCode(500))
        XCTAssertEqual(AeroxProtocol.cpiCode(50), AeroxProtocol.cpiCode(100), "Below range clamps.")
        XCTAssertEqual(AeroxProtocol.cpiCode(99_999), 0xD6, "Above range clamps.")
    }

    func testActiveIndexIsClampedToTheLadder() {
        XCTAssertEqual(AeroxProtocol.sensitivity(levels: [800], activeIndex: 4)[2], 0)
    }

    func testPollingRateMatchesRivalcfg() {
        XCTAssertEqual(hex(AeroxProtocol.pollingRate(hz: 500)), "2B 01")
        XCTAssertEqual(hex(AeroxProtocol.pollingRate(hz: 1000)), "2B 00")
        XCTAssertEqual(hex(AeroxProtocol.pollingRate(hz: 125)), "2B 03")
    }

    func testTimersMatchRivalcfg() {
        XCTAssertEqual(hex(AeroxProtocol.sleepTimer(milliseconds: 5 * 60_000)), "29 E0 93 04")
        XCTAssertEqual(hex(AeroxProtocol.sleepTimer(milliseconds: 20 * 60_000)), "29 80 4F 12")
        XCTAssertEqual(hex(AeroxProtocol.dimTimer(milliseconds: 30_000)), "23 0F 01 00 00 30 75 00")
        XCTAssertEqual(hex(AeroxProtocol.dimTimer(milliseconds: 0)), "23 0F 01 00 00 00 00 00")
        XCTAssertEqual(
            AeroxProtocol.sleepTimer(milliseconds: 3_600_000),
            AeroxProtocol.sleepTimer(milliseconds: 20 * 60_000),
            "The firmware maximum is 20 minutes."
        )
    }

    func testLightingMatchesRivalcfg() {
        XCTAssertEqual(hex(AeroxProtocol.reactiveColor((255, 128, 0))), "26 01 00 FF 80 00")
        XCTAssertEqual(hex(AeroxProtocol.reactiveColor(nil)), "26 00 00 00 00 00")
        XCTAssertEqual(hex(AeroxProtocol.defaultLighting(rainbow: true, reactive: true)), "27 01 01")
    }

    func testButtonsMatchRivalcfg() {
        XCTAssertEqual(
            hex(AeroxProtocol.buttons(functions: [1, 2, 3, 4, 5, 48, 49, 50])),
            "2A 01 00 00 00 00 02 00 00 00 00 03 00 00 00 00 04 00 00 00 00 05 00 00 00 00 "
                + "30 00 00 00 00 31 00 00 00 00 32 00 00 00 00"
        )
        // rivalcfg: buttons(button1=button2; button2=button1; button6=disable)
        XCTAssertEqual(
            hex(AeroxProtocol.buttons(functions: [2, 1, 3, 4, 5, 0, 49, 50])),
            "2A 02 00 00 00 00 01 00 00 00 00 03 00 00 00 00 04 00 00 00 00 05 00 00 00 00 "
                + "00 00 00 00 00 31 00 00 00 00 32 00 00 00 00"
        )
    }

    /// A code the firmware does not know must never be sent; the slot keeps its
    /// factory action instead.
    func testUnsupportedButtonFunctionFallsBackToFactoryAction() {
        let packet = AeroxProtocol.buttons(functions: [12, 2])
        XCTAssertEqual(packet[1], 0x01)
        XCTAssertEqual(packet[6], 0x02)
        XCTAssertEqual(packet[26], 0x30, "Missing slots use the factory map too.")
    }

    func testWirelessCommandsCarryTheReceiverFlag() {
        XCTAssertEqual(hex(AeroxProtocol.addressed(AeroxProtocol.saveToFlash, wireless: true)), "51 00")
        XCTAssertEqual(hex(AeroxProtocol.addressed(AeroxProtocol.batteryQuery, wireless: true)), "D2")
        XCTAssertEqual(hex(AeroxProtocol.addressed(AeroxProtocol.saveToFlash, wireless: false)), "11 00")
    }

    func testBatteryDecodingMatchesRivalcfg() {
        let charging = AeroxProtocol.battery(response: [0x00, 0x95])
        XCTAssertEqual(charging?.percent, 100)
        XCTAssertEqual(charging?.isCharging, true)

        let half = AeroxProtocol.battery(response: [0x00, 0x0B])
        XCTAssertEqual(half?.percent, 50)
        XCTAssertEqual(half?.isCharging, false)

        XCTAssertNil(AeroxProtocol.battery(response: [0x00, 0x00]), "0 decodes to -5%: no reading.")
        XCTAssertNil(AeroxProtocol.battery(response: []), "No answer: mouse off or out of range.")
    }

    /// A Bluetooth mouse answers `0x92` with its firmware-version reply rather than a
    /// battery reading — `04 92 95 "10.6"` with the report id stripped to
    /// `92 95 31 30 2E 36`. Decoded as battery that is "100 %, charging", which is the
    /// phantom charge state the badge used to show on a wireless but idle mouse. The
    /// payload must be rejected so the caller falls back to the level-only host reading.
    func testFirmwareReplyIsNotMistakenForBattery() {
        let firmware: [UInt8] = [0x92, 0x95, 0x31, 0x30, 0x2E, 0x36]
        XCTAssertNil(AeroxProtocol.battery(response: firmware), "Firmware string is not a reading.")

        // Padded out to a full report, exactly as it arrives off the device.
        var padded = firmware
        padded += [UInt8](repeating: 0, count: 58)
        XCTAssertNil(AeroxProtocol.battery(response: padded))
    }

    /// A genuine reading pads the report with zeros and must still decode.
    func testZeroPaddingIsNotMistakenForAFirmwareString() {
        var reading: [UInt8] = [0x92, 0x0B]
        reading += [UInt8](repeating: 0, count: 62)
        let status = AeroxProtocol.battery(response: reading)
        XCTAssertEqual(status?.percent, 50)
        XCTAssertEqual(status?.isCharging, false)
    }

    func testModelsCoverWiredAndReceiver() {
        XCTAssertEqual(AeroxProtocol.model(vendorID: 0x1038, productID: 0x183A)?.transport, .usb)
        XCTAssertEqual(AeroxProtocol.model(vendorID: 0x1038, productID: 0x1838)?.isWireless, true)
        XCTAssertNil(AeroxProtocol.model(vendorID: 0x1038, productID: 0x1234))
    }

    /// What `ioreg` reports for the mouse paired over Bluetooth LE.
    func testBluetoothIdentityIsRecognisedWithoutTheReceiverFlag() {
        let model = AeroxProtocol.model(vendorID: 0x0111, productID: 0x183A)
        XCTAssertEqual(model?.transport, .bluetooth)
        XCTAssertEqual(model?.isWireless, false)
    }

    /// Every model maps to artwork that is actually bundled with the app.
    func testEveryModelHasBundledArtwork() {
        let app = Bundle(for: ConfigurationStore.self)
        for model in AeroxProtocol.models {
            XCTAssertNotNil(app.image(forResource: model.imageName), model.imageName)
        }
    }

    /// The real engine document converts into the full command set, in engine units.
    func testCommandsFromTheEngineDocument() throws {
        let settings = try MouseSettings(parsing: Fixture.aeroxSettings)
        let commands = AeroxProtocol.commands(for: settings)

        XCTAssertEqual(commands.count, 10)
        XCTAssertEqual(commands[0][0], 0x2D)
        XCTAssertEqual(Int(commands[0][1]), settings.cpiLevelCount)
        XCTAssertEqual(commands[0].count, 3 + settings.cpiLevelCount)
        XCTAssertEqual(commands[1], AeroxProtocol.pollingRate(hz: settings.pollingRateHz))
    }

    func testZoneColorsMatchRivalcfg() {
        XCTAssertEqual(
            hex(AeroxProtocol.zoneColor(0, color: (255, 0, 0))),
            "21 01 00 FF 00 00"
        )
        XCTAssertEqual(
            hex(AeroxProtocol.zoneColor(2, color: (0, 0, 255))),
            "21 01 02 00 00 FF"
        )
    }

    /// The three zone commands sit between the timers and the reactive colour, and each
    /// carries its own zone byte.
    func testCommandsCarryThreeIndependentZones() throws {
        let settings = try MouseSettings(parsing: LocalProfileStore.defaultSettings)
        let commands = AeroxProtocol.commands(for: settings)
        let zones = Array(commands[4...6])

        XCTAssertEqual(zones.map { $0[0] }, [0x21, 0x21, 0x21])
        XCTAssertEqual(zones.map { $0[2] }, [0, 1, 2])
        XCTAssertEqual(zones[0], AeroxProtocol.zoneColor(0, color: (255, 0, 0)))
        XCTAssertEqual(zones[2], AeroxProtocol.zoneColor(2, color: (0, 0, 255)))
    }

    func testDefaultProfileIsAValidMouseDocument() throws {
        let settings = try MouseSettings(parsing: LocalProfileStore.defaultSettings)
        XCTAssertEqual(settings.cpiLevels.prefix(5), [400, 800, 1200, 2400, 3200])
        XCTAssertEqual(settings.buttons.map(\.function), AeroxProtocol.defaultButtonFunctions)
        XCTAssertEqual(
            AeroxProtocol.commands(for: settings)[0],
            AeroxProtocol.sensitivity(levels: [400, 800, 1200, 2400, 3200], activeIndex: 0)
        )
        try WriteSafetyPolicy.validate(LocalProfileStore.defaultConfiguration())
    }
}
