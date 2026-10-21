import XCTest
@testable import SteelSeriesConfig

final class MouseSettingsTests: XCTestCase {

    func testParsesRealAeroxDocument() throws {
        let settings = try MouseSettings(parsing: Fixture.aeroxSettings)

        XCTAssertEqual(settings.cpiLevelCount, 5)
        XCTAssertEqual(settings.activeCPILevelIndex, 0)
        XCTAssertEqual(settings.pollingRateHz, 1000)
        XCTAssertEqual(settings.brightness, 15)
        XCTAssertEqual(settings.powerSaveSeconds, 300)
        XCTAssertEqual(settings.buttons.count, 2)
        XCTAssertTrue(settings.hasButtonMappings)
    }

    /// CPI is stored in engine units; the GG client multiplies by 50.
    /// Values below come from the live device: [4, 9, 13, 27, 38].
    func testCPIScaleMatchesClientConversion() throws {
        let settings = try MouseSettings(parsing: Fixture.aeroxSettings)

        XCTAssertEqual(settings.cpiLevels, [200, 450, 650, 1350, 1900])
        XCTAssertEqual(settings.activeCPI, 200)
        XCTAssertEqual(settings.rawCPI(step: 5), 38)
    }

    func testSettingActiveCPIQuantisesToGridAndWritesCorrectStep() throws {
        var settings = try MouseSettings(parsing: Fixture.aeroxSettings)

        settings.setActiveCPIValue(1234)

        XCTAssertEqual(settings.activeCPI, 1250, "Should snap to the 50-CPI grid.")
        XCTAssertEqual(settings.rawCPI(step: 1), 25, "1234 → 1250 → 1250/50.")
        XCTAssertEqual(settings.rawCPI(step: 2), 9, "Other steps must be untouched.")
    }

    func testCPILevelCountClampsActiveIndex() throws {
        var settings = try MouseSettings(parsing: Fixture.aeroxSettings)
        settings.setActiveCPILevelIndex(4)
        XCTAssertEqual(settings.activeCPILevelIndex, 4)

        settings.setCPILevelCount(2)
        XCTAssertEqual(settings.cpiLevelCount, 2)
        XCTAssertLessThan(settings.activeCPILevelIndex, 2)
    }

    func testPollingCodeMapMatchesClientSwitch() {
        XCTAssertEqual(MouseSettings.hz(forPollingCode: 0), 1000)
        XCTAssertEqual(MouseSettings.hz(forPollingCode: 1), 500)
        XCTAssertEqual(MouseSettings.hz(forPollingCode: 2), 250)
        XCTAssertEqual(MouseSettings.hz(forPollingCode: 3), 125)

        for hz in MouseSettings.pollingRateOptions {
            XCTAssertEqual(MouseSettings.pollingCode(forHz: hz), MouseSettings.pollingCode(forHz: hz))
            XCTAssertEqual(MouseSettings.hz(forPollingCode: MouseSettings.pollingCode(forHz: hz)), hz)
        }
    }

    func testSettingPollingRateKeepsStorageAsSmallCode() throws {
        var settings = try MouseSettings(parsing: Fixture.aeroxSettings)
        settings.setPollingRateHz(125)

        XCTAssertEqual(settings.int("polling_rate", "val"), 3, "125 Hz is stored as code 3, not 125.")
        XCTAssertEqual(settings.pollingRateHz, 125)
    }

    func testZoneColoursDefaultAndWriteIndependently() throws {
        var settings = try MouseSettings(parsing: LocalProfileStore.defaultSettings)
        let zones = MouseSettings.LightingZone.all

        XCTAssertEqual(settings.zoneColor(zones[0]), MouseSettings.LightingColor(red: 255, green: 0, blue: 0))
        XCTAssertEqual(settings.zoneColor(zones[2]), MouseSettings.LightingColor(red: 0, green: 0, blue: 255))

        settings.setZoneColor(zones[1], MouseSettings.LightingColor(red: 1, green: 2, blue: 3))

        XCTAssertEqual(settings.zoneColor(zones[1]), MouseSettings.LightingColor(red: 1, green: 2, blue: 3))
        XCTAssertEqual(
            settings.zoneColor(zones[0]),
            MouseSettings.LightingColor(red: 255, green: 0, blue: 0),
            "Sibling zone changed."
        )
    }

    /// A document written by GG stores colours as a sequence; the first frame is the
    /// colour the user picked, so it is a sensible fallback before this app writes one.
    func testZoneColourFallsBackToGGSequence() throws {
        let document = """
        {"aerox_3_wireless_z2_color_sequence": {"data": [[12, 34, 56], [0, 0, 0]], "repeat": 255}}
        """
        let settings = try MouseSettings(parsing: document)

        XCTAssertEqual(
            settings.zoneColor(MouseSettings.LightingZone.all[1]),
            MouseSettings.LightingColor(red: 12, green: 34, blue: 56)
        )
    }

    /// Editing one leaf must not flatten its parent or lose siblings.
    func testNestedEditsPreserveSiblings() throws {
        var settings = try MouseSettings(parsing: Fixture.aeroxSettings)

        settings.setBrightness(7)
        settings.setSmartLighting(false)
        settings.setReactiveColor(red: 1, green: 2, blue: 3)

        let lighting = try XCTUnwrap(settings.json["lighting_settings"]?.objectValue)
        XCTAssertEqual(lighting["brightness"]?.intValue, 7)
        XCTAssertEqual(lighting["idle_brightness"]?.intValue, 1, "Sibling lost.")
        XCTAssertEqual(lighting["idle_timeout"]?.intValue, 30000, "Sibling lost.")
        XCTAssertEqual(lighting["smart_lighting"]?.intValue, 0)

        let reactive = try XCTUnwrap(settings.json["reactive_lighting"]?.objectValue)
        let color = try XCTUnwrap(reactive["color"]?.objectValue)
        XCTAssertEqual(color["r"]?.intValue, 1)
        XCTAssertEqual(color["g"]?.intValue, 2)
        XCTAssertEqual(color["b"]?.intValue, 3)

        let mappings = try XCTUnwrap(settings.json["button_mappings"]?.objectValue)
        XCTAssertEqual(mappings["no_live_deploy"]?.intValue, 1, "Unrelated branch lost.")
    }

    /// Bool vs 0/1 matters: the engine stores these as integers, and changing the
    /// type on write is exactly the sort of drift that later breaks a reader.
    func testIntegerTogglesStayIntegers() throws {
        var settings = try MouseSettings(parsing: Fixture.aeroxSettings)
        settings.setSmartLighting(false)
        settings.setDefaultLightingEnabled(false)
        settings.setAngleSnapping(true)

        XCTAssertEqual(settings.json["lighting_settings"]?.objectValue?["smart_lighting"], .int(0))
        XCTAssertEqual(settings.json["default_lighting_enabled"]?.objectValue?["default_lighting_enabled"], .int(0))
        XCTAssertEqual(settings.json["angle_snapping"]?.objectValue?["level"], .int(1))
    }

    func testClamping() throws {
        var settings = try MouseSettings(parsing: Fixture.aeroxSettings)

        settings.setBrightness(99)
        XCTAssertEqual(settings.brightness, 15)

        settings.setIdleBrightness(-4)
        XCTAssertEqual(settings.idleBrightness, 0)

        settings.setActiveCPIValue(999_999)
        XCTAssertEqual(settings.activeCPI, MouseSettings.cpiMaximum)

        settings.setPowerSaveSeconds(-10)
        XCTAssertEqual(settings.powerSaveSeconds, 0)
    }

    func testRejectsNonObjectDocuments() {
        XCTAssertThrowsError(try MouseSettings(parsing: "[]"))
        XCTAssertThrowsError(try MouseSettings(parsing: "{}")) { error in
            XCTAssertEqual(error as? MouseSettings.MouseSettingsError, .notAnObject)
        }
        XCTAssertThrowsError(try MouseSettings(parsing: "nonsense"))
    }

    func testButtonLabelsCoverKnownHIDCodes() throws {
        let settings = try MouseSettings(parsing: Fixture.aeroxSettings)
        XCTAssertEqual(settings.buttons.map { $0.function }, [1, 49])
        XCTAssertEqual(settings.buttons[0].label, "Left click")
        XCTAssertEqual(settings.buttons[1].label, "Scroll up")
        XCTAssertTrue(settings.buttons[0].isFactoryDefault)
    }

    func testButtonsCarryStablePositionalIdentity() throws {
        var settings = try MouseSettings(parsing: Fixture.aeroxSettings)

        settings.setButtonFunction(at: 1, function: 1)

        XCTAssertEqual(settings.buttons.map(\.function), [1, 1])
        XCTAssertEqual(settings.buttons.map(\.index), [0, 1], "Identity must follow position, not the code.")
        XCTAssertEqual(settings.buttons.map(\.id), [0, 1])
    }

    func testRemappingOneButtonPreservesTheRest() throws {
        var settings = try MouseSettings(parsing: Fixture.aeroxSettings)

        settings.setButtonFunction(at: 0, function: 2)

        XCTAssertEqual(settings.buttons[0].function, 2)
        XCTAssertEqual(settings.buttons[1].function, 49, "Sibling button lost.")
        XCTAssertEqual(settings.buttons[0].keyCodes, [0, 0, 0, 0], "key_codes must be preserved.")

        let mappings = try XCTUnwrap(settings.json["button_mappings"]?.objectValue)
        XCTAssertEqual(mappings["no_live_deploy"]?.intValue, 1, "no_live_deploy must survive the edit.")
    }

    func testRemappingOutOfRangeIndexIsIgnored() throws {
        var settings = try MouseSettings(parsing: Fixture.aeroxSettings)
        let before = try settings.encodedString()

        settings.setButtonFunction(at: 9, function: 3)

        XCTAssertEqual(try settings.encodedString(), before)
    }

    /// Angle snapping is a 0…10 strength, not a switch — the GG client's own template
    /// binds `angle_snapping.level` to `snapLevelRange: [0…10]`.
    func testAngleSnapLevelClampsToTen() throws {
        var settings = try MouseSettings(parsing: Fixture.aeroxSettings)

        XCTAssertEqual(settings.angleSnapLevel, 0)
        settings.setAngleSnapLevel(7)
        XCTAssertEqual(settings.angleSnapLevel, 7)
        XCTAssertTrue(settings.angleSnapping)

        settings.setAngleSnapLevel(99)
        XCTAssertEqual(settings.angleSnapLevel, 10)

        settings.setAngleSnapLevel(0)
        XCTAssertFalse(settings.angleSnapping)
    }

    func testButtonFunctionCatalogCoversTheDefaults() {
        let codes = Set(MouseSettings.buttonFunctions.map(\.code))
        XCTAssertTrue(codes.isSuperset(of: [1, 2, 3, 4, 5, 48, 49, 50]))
    }
}
