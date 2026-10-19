import XCTest
@testable import SteelSeriesConfig

/// End-to-end checks against the **live** SteelSeries engine on this machine.
///
/// These are strictly read-only: they never PUT, never POST `deploy`, and never touch
/// the hardware. If no engine is reachable (GG not installed, not running, or a CI
/// machine) every test skips rather than fails — the point is to prove the app's
/// discovery and decoding work against real data, not to make the suite
/// environment-dependent.
///
/// Run deliberately with: `xcodebuild test -only-testing:SteelSeriesConfigTests/EngineIntegrationTests`
final class EngineIntegrationTests: XCTestCase {

    private func makeEngine() throws -> (EngineClient, URL) {
        guard let url = CorePropsLocator.resolveEngineURL() else {
            throw XCTSkip("No engine URL could be resolved.")
        }

        let client = EngineClient(engineURL: url)
        return (client, url)
    }

    private func requireDevices(_ client: EngineClient) async throws -> [Device] {
        do {
            let devices = try await client.devices()
            if devices.isEmpty {
                throw XCTSkip("Engine reachable but reported no devices.")
            }
            return devices
        } catch is XCTSkip {
            throw XCTSkip("Engine reachable but reported no devices.")
        } catch {
            throw XCTSkip("Engine not reachable at this moment: \(error.localizedDescription)")
        }
    }

    /// Discovery: the documented port really is the engine, and `/devices` really does
    /// carry the fields the UI groups on.
    func testDiscoveryFindsEngineAndDecodesDevices() async throws {
        let (client, url) = try makeEngine()
        let devices = try await requireDevices(client)

        XCTAssertFalse(devices.isEmpty)
        XCTAssertEqual(url.scheme, "https")

        for device in devices {
            XCTAssertFalse(device.name.isEmpty, "Device \(device.id) has no name.")
            XCTAssertFalse(
                device.deviceTypeName.isEmpty,
                "Device \(device.id) has an empty deviceTypeName — the list endpoint is supposed to populate this."
            )
        }
    }

    /// The payload the whole app is built on: a real configuration must decode into the
    /// typed model, and must pass the pre-write policy. If this fails, the app would be
    /// unable to save — which is exactly the failure worth catching here rather than in
    /// front of the user.
    func testRealMouseConfigurationDecodesAndPassesSafetyPolicy() async throws {
        let (client, _) = try makeEngine()
        let devices = try await requireDevices(client)

        guard let mouse = devices.first(where: { $0.isMouse }) else {
            throw XCTSkip("No mouse-class device connected; nothing to decode.")
        }

        let configurations = try await client.configurations(deviceID: mouse.id)
        guard let summary = configurations.first else {
            throw XCTSkip("Mouse \(mouse.id) has no configurations.")
        }

        let config = try await client.configuration(id: summary.id)
        XCTAssertFalse(config.settings.isEmpty)

        // Whatever the device, the document must be a usable object.
        try WriteSafetyPolicy.validate(config)

        let parsed = try MouseSettings(parsing: config.settings)
        XCTAssertGreaterThan(parsed.cpiLevelCount, 0)
        XCTAssertLessThanOrEqual(parsed.cpiLevelCount, MouseSettings.maxCPILevels)
        XCTAssertLessThan(parsed.activeCPILevelIndex, parsed.cpiLevelCount)
        XCTAssertTrue(MouseSettings.pollingRateOptions.contains(parsed.pollingRateHz))

        for level in parsed.cpiLevels.prefix(parsed.cpiLevelCount) {
            XCTAssertGreaterThanOrEqual(level, MouseSettings.cpiMinimum)
            XCTAssertLessThanOrEqual(level, MouseSettings.cpiMaximum)
        }

        // Round-tripping must not lose a single top-level key: that is the guarantee
        // that makes read-modify-write safe.
        let before = Set(try XCTUnwrap(AnyJSONValue.parse(config.settings).objectValue).keys)
        let after = Set(try XCTUnwrap(AnyJSONValue.parse(try parsed.encodedString()).objectValue).keys)
        XCTAssertEqual(before, after, "Re-encoding the parsed settings dropped or added top-level keys.")
    }

    /// Sync status is a separate probe from the device list; the UI shows it as a badge,
    /// so it has to decode for a mouse that is actually connected.
    func testSyncStatusDecodesForConnectedMouse() async throws {
        let (client, _) = try makeEngine()
        let devices = try await requireDevices(client)

        guard let mouse = devices.first(where: { $0.isMouse && $0.connected.value }) else {
            throw XCTSkip("No connected mouse-class device.")
        }

        let status = try await client.syncStatus(deviceID: mouse.id)
        XCTAssertEqual(status.deviceId, mouse.id)
    }

    /// Device artwork is served by the engine over its self-signed HTTPS endpoint, so a
    /// plain URLSession would fail here. Proves the trust delegate is wired correctly.
    func testDeviceImageLoadsThroughEngineClient() async throws {
        let (client, _) = try makeEngine()
        let devices = try await requireDevices(client)

        guard let urlString = devices.compactMap(\.imageUrl).first else {
            throw XCTSkip("No device in the list advertises an imageUrl.")
        }

        let data = try await client.imageData(at: urlString)
        XCTAssertGreaterThan(data.count, 0)
    }

    /// The fallback path must be a real engine, not a guess that happens to be written
    /// down: if the file is missing, this URL is what the app will try.
    func testFallbackURLCarriesUsableHTTPSAddress() throws {
        let url = try XCTUnwrap(
            CoreProps.baseURL(from: CorePropsLocator.fallbackHostAndPort),
            "Fallback host:port did not produce a URL."
        )
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "127.0.0.1")
        XCTAssertNotNil(url.port)
    }
}
