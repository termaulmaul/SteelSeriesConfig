import XCTest
@testable import SteelSeriesConfig

final class WriteSafetyPolicyTests: XCTestCase {

    func testAcceptsRealDocument() throws {
        try WriteSafetyPolicy.validate(Fixture.makeConfiguration())
    }

    /// The incident this app exists to make impossible: an empty settings body sent
    /// to PUT wipes the stored configuration, and the engine still answers 200.
    func testRejectsEmptySettings() {
        var config = Fixture.makeConfiguration()
        config.settings = ""

        XCTAssertThrowsError(try WriteSafetyPolicy.validate(config)) { error in
            XCTAssertEqual(error as? WriteSafetyPolicy.Violation, .emptySettings)
        }
    }

    func testRejectsWhitespaceOnlySettings() {
        var config = Fixture.makeConfiguration()
        config.settings = "   \n\t "

        XCTAssertThrowsError(try WriteSafetyPolicy.validate(config)) { error in
            XCTAssertEqual(error as? WriteSafetyPolicy.Violation, .emptySettings)
        }
    }

    func testRejectsSettingsThatIsNotAnObject() {
        for bad in ["[]", "\"text\"", "123", "null", "{\"a\":1,\"b\":2}[]"] {
            var config = Fixture.makeConfiguration()
            config.settings = bad
            XCTAssertThrowsError(
                try WriteSafetyPolicy.validate(config),
                "Expected '\(bad)' to be rejected"
            )
        }
    }

    func testRejectsEmptyObject() {
        var config = Fixture.makeConfiguration()
        config.settings = "{}"

        XCTAssertThrowsError(try WriteSafetyPolicy.validate(config)) { error in
            XCTAssertEqual(error as? WriteSafetyPolicy.Violation, .settingsNotAnObject)
        }
    }

    func testRejectsEmptyName() {
        var config = Fixture.makeConfiguration()
        config.name = "   "

        XCTAssertThrowsError(try WriteSafetyPolicy.validate(config)) { error in
            XCTAssertEqual(error as? WriteSafetyPolicy.Violation, .emptyName)
        }
    }

    func testRejectsMissingID() {
        var config = Fixture.makeConfiguration()
        config.id = ""

        XCTAssertThrowsError(try WriteSafetyPolicy.validate(config)) { error in
            XCTAssertEqual(error as? WriteSafetyPolicy.Violation, .missingID)
        }
    }

    func testAllowsEmptyUndeployedButRejectsMalformed() throws {
        var config = Fixture.makeConfiguration()
        config.undeployedSettings = ""
        try WriteSafetyPolicy.validate(config)

        config.undeployedSettings = "{oops"
        XCTAssertThrowsError(try WriteSafetyPolicy.validate(config)) { error in
            XCTAssertEqual(error as? WriteSafetyPolicy.Violation, .invalidUndeployedSettings)
        }
    }

    /// A save that would shrink the document by more than 90% is the fingerprint of a
    /// wipe rather than an edit, so it is blocked even though each field is valid.
    ///
    /// The fixture is padded above `shrinkageFloorBytes` because the heuristic
    /// deliberately stays out of the way for small documents — see
    /// `testSmallDocumentsSkipShrinkageHeuristic`.
    func testRejectsSuspiciousShrinkage() throws {
        let padding = String(repeating: "a", count: 1_200)
        let previous = Fixture.makeConfiguration(
            settings: #"{"padding":{"blob":"\#(padding)"},"polling_rate":{"val":0}}"#
        )
        var next = Fixture.makeConfiguration()
        next.settings = #"{"polling_rate":{"val":0}}"#

        XCTAssertThrowsError(try WriteSafetyPolicy.validate(next, previous: previous)) { error in
            guard case .suspiciousShrinkage = error as? WriteSafetyPolicy.Violation else {
                return XCTFail("Expected suspiciousShrinkage, got \(error)")
            }
        }
    }

    func testAllowsOrdinaryEditsAgainstRealDocument() throws {
        let previous = Fixture.makeConfiguration()
        var next = Fixture.makeConfiguration()
        var settings = try MouseSettings(parsing: Fixture.aeroxSettings)
        settings.setBrightness(3)
        next.settings = try settings.encodedString()

        try WriteSafetyPolicy.validate(next, previous: previous)
    }

    func testSmallDocumentsSkipShrinkageHeuristic() throws {
        let previous = Fixture.makeConfiguration(settings: #"{"a":{"b":1}}"#)
        var next = Fixture.makeConfiguration(settings: #"{"a":{"b":2}}"#)

        // Too small to draw a conclusion from — a legitimately tiny document must not
        // be permanently uneditable.
        try WriteSafetyPolicy.validate(next, previous: previous)

        next.settings = #"{"c":{"d":3}}"#
        try WriteSafetyPolicy.validate(next, previous: previous)
    }
}
