import XCTest
@testable import SteelSeriesConfig

final class AnyJSONValueTests: XCTestCase {

    func testParsesScalarsWithCorrectTypes() throws {
        let value = try AnyJSONValue.parse(#"{"i": 4, "d": 1.5, "b": true, "s": "x", "n": null}"#)
        let object = try XCTUnwrap(value.objectValue)

        XCTAssertEqual(object["i"], .int(4))
        XCTAssertEqual(object["d"], .double(1.5))
        XCTAssertEqual(object["b"], .bool(true))
        XCTAssertEqual(object["s"], .string("x"))
        XCTAssertEqual(object["n"], .null)
    }

    func testRoundTripPreservesKeysAndValues() throws {
        let original = try AnyJSONValue.parse(Fixture.aeroxSettings)
        let encoded = try original.compactString()
        let reparsed = try AnyJSONValue.parse(encoded)

        XCTAssertEqual(original, reparsed, "Settings must survive a serialise/parse cycle unchanged.")
    }

    /// The whole point of this type: an unknown key must not disappear on write.
    func testUnknownKeysSurviveMutation() throws {
        var settings = try MouseSettings(parsing: Fixture.aeroxSettings)
        settings.setBrightness(7)

        let encoded = try settings.encodedString()
        let reparsed = try AnyJSONValue.parse(encoded)
        let object = try XCTUnwrap(reparsed.objectValue)

        for key in try XCTUnwrap(AnyJSONValue.parse(Fixture.aeroxSettings).objectValue).keys {
            XCTAssertNotNil(object[key], "Key \(key) was dropped by an unrelated edit.")
        }
    }

    func testParseRejectsGarbage() {
        XCTAssertThrowsError(try AnyJSONValue.parse("not json"))
        XCTAssertThrowsError(try AnyJSONValue.parse(""))
    }

    /// A bare array is valid JSON, so it must parse — rejecting non-object documents
    /// is the job of `WriteSafetyPolicy`, not the JSON layer.
    func testParseAcceptsNonObjectTopLevel() throws {
        XCTAssertEqual(try AnyJSONValue.parse("[]"), .array([]))
        XCTAssertEqual(try AnyJSONValue.parse("123"), .int(123))
    }

    func testCompactStringIsStableAndSorted() throws {
        let value = try AnyJSONValue.parse(#"{"b": 1, "a": 2}"#)
        XCTAssertEqual(try value.compactString(), #"{"a":2,"b":1}"#)
    }
}
