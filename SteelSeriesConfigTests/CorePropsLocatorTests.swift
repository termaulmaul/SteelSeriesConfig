import XCTest
@testable import SteelSeriesConfig

final class CorePropsLocatorTests: XCTestCase {

    private let sample = #"{"encryptedAddress":"127.0.0.1:50530","ggEncryptedAddress":"127.0.0.1:6327","address":"127.0.0.1:50526"}"#

    func testParseEngineURL() throws {
        let coreProps = try XCTUnwrap(CorePropsLocator.parse(sample))
        let url = try XCTUnwrap(coreProps.engineURL)

        XCTAssertEqual(url.host, "127.0.0.1")
        XCTAssertEqual(url.port, 50530)
        XCTAssertEqual(url.scheme, "https")
    }

    func testEngineURLPrefersEncryptedAddress() throws {
        // The GG client reads the *encrypted* port for the core engine API; the plain
        // `address` field is a different service and must not win.
        let coreProps = try XCTUnwrap(
            CorePropsLocator.parse(#"{"encryptedAddress":"127.0.0.1:50530","address":"127.0.0.1:50526"}"#)
        )
        XCTAssertEqual(coreProps.engineURL?.port, 50530)
    }

    func testParsesRealisticFileWithTrailingNewlineAndSpaces() throws {
        let coreProps = try XCTUnwrap(
            CorePropsLocator.parse(
                """
                {"encryptedAddress": "127.0.0.1:50530", "ggEncryptedAddress": "127.0.0.1:6327", "address": "127.0.0.1:50526"}
                """
            )
        )
        XCTAssertNotNil(coreProps.engineURL)
    }

    func testRejectsGarbageAndEmptyInput() {
        XCTAssertNil(CorePropsLocator.parse("not json"))
        XCTAssertNil(CorePropsLocator.parse(""))
        XCTAssertNil(CorePropsLocator.parse("[]"))
    }

    /// Missing `encryptedAddress` must not silently produce the fallback URL from the
    /// parse step — that is what `resolveEngineURL` is for.
    func testMissingEncryptedAddressGivesNoEngineURLFromParse() throws {
        let coreProps = try XCTUnwrap(
            CorePropsLocator.parse(#"{"address":"127.0.0.1:50526"}"#)
        )
        XCTAssertNil(coreProps.engineURL)
    }

    /// Fallback must stay a valid `host:port` — a typo here would silently disable the
    /// app's only recovery path from a missing or malformed file.
    func testFallbackAddressIsValid() throws {
        let parts = CorePropsLocator.fallbackHostAndPort.split(separator: ":")
        XCTAssertEqual(parts.count, 2)
        XCTAssertNotNil(Int(parts[1]), "Fallback port must be numeric, got '\(parts[1])'.")
        XCTAssertNotNil(CoreProps.baseURL(from: CorePropsLocator.fallbackHostAndPort))
    }

    /// resolveEngineURL falls back rather than returning nil, so an engine that moved
    /// to an unexpected port still gets *one* attempt before failing loudly.
    func testResolveEngineURLFallsBackWhenFileUnreadable() {
        let url = CorePropsLocator.resolveEngineURL(path: "/nonexistent/coreProps.json")
        XCTAssertEqual(url?.port, 50530)
        XCTAssertEqual(url?.host, "127.0.0.1")
    }

    func testResolveEngineURLUsesFileWhenPresent() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("coreProps-\(UUID().uuidString).json")
        try Data(sample.utf8).write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }

        let url = CorePropsLocator.resolveEngineURL(path: temp.path)
        XCTAssertEqual(url?.port, 50530)
    }
}
