import XCTest
import AppKit
@testable import SteelSeriesConfig

/// Pins how bundled product artwork is resolved.
///
/// The artwork ships as a loose `.png` in the app bundle, not in an asset catalogue, and
/// the device payload carries a bare name (`"DeviceAerox3"`). This asserts the resolver
/// actually finds the file when running inside the host app — the failure mode being
/// guarded against is `nil`, which silently swaps the mouse icon for a placeholder glyph.
final class DeviceArtworkTests: XCTestCase {

    func testResolvesBundledMouseArtwork() throws {
        let image = DeviceArtwork.image(named: "DeviceAerox3")
        XCTAssertNotNil(image, "Loose bundle PNG must resolve through the host app's bundle.")
    }

    func testResolvesDragonLoreArtwork() throws {
        XCTAssertNotNil(DeviceArtwork.image(named: "DeviceAerox3DragonLore"))
    }

    func testMissingAndEmptyNamesAreNil() {
        XCTAssertNil(DeviceArtwork.image(named: nil))
        XCTAssertNil(DeviceArtwork.image(named: ""))
        XCTAssertNil(DeviceArtwork.image(named: "NoSuchDeviceArtwork"))
    }
}
