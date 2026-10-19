import XCTest
@testable import SteelSeriesConfig

final class HostBatteryReaderTests: XCTestCase {

    /// Trimmed from a real `system_profiler SPBluetoothDataType -json` run on the
    /// development machine, with the connected mouse and a couple of decoys.
    private let document = """
    {
      "SPBluetoothDataType": [
        {
          "controller_properties": {"controller_address": "AC:07:75:20:38:C2"},
          "device_connected": [
            {
              "Aerox 3 WL": {
                "device_address": "03:B7:4B:9A:28:26",
                "device_minorType": "Mouse",
                "device_batteryLevelMain": "82%"
              }
            }
          ],
          "device_not_connected": [
            {"Some Speaker": {"device_minorType": "Speaker"}},
            {"maul AirPods Pro": {"device_batteryLevelLeft": "100%"}}
          ]
        }
      ]
    }
    """.data(using: .utf8)!

    func testParsesConnectedDeviceBattery() {
        let readings = HostBatteryReader.parse(document)

        XCTAssertEqual(readings.count, 1)
        XCTAssertEqual(readings[0].name, "Aerox 3 WL")
        XCTAssertEqual(readings[0].minorType, "Mouse")
        XCTAssertEqual(readings[0].percent, 82)
    }

    /// Only connected devices count — a paired-but-absent mouse is not a reading.
    func testIgnoresNotConnectedDevices() {
        let names = HostBatteryReader.parse(document).map(\.name)
        XCTAssertFalse(names.contains("maul AirPods Pro"))
        XCTAssertFalse(names.contains("Some Speaker"))
    }

    func testPicksTheMouse() {
        let reading = HostBatteryReader.mouse(
            in: HostBatteryReader.parse(document),
            preferringName: nil
        )
        XCTAssertEqual(reading?.percent, 82)
    }

    /// macOS' device name ("Aerox 3 WL") does not match the engine's
    /// ("aerox_3_wireless"); a name that does not match must still fall back to the
    /// only mouse rather than reporting nothing.
    func testFallsBackWhenNameDoesNotMatch() {
        let reading = HostBatteryReader.mouse(
            in: HostBatteryReader.parse(document),
            preferringName: "aerox_3_wireless"
        )
        XCTAssertEqual(reading?.percent, 82)
    }

    func testRejectsMalformedDocuments() {
        XCTAssertTrue(HostBatteryReader.parse(Data("nonsense".utf8)).isEmpty)
        XCTAssertTrue(HostBatteryReader.parse(Data("{}".utf8)).isEmpty)
    }

    // MARK: - NumericField snapping

    func testSnapRoundsToNearestStepWithinRange() {
        XCTAssertEqual(NumericField.snap(1234, to: 50, in: 50...18_000), 1250)
        XCTAssertEqual(NumericField.snap(1220, to: 50, in: 50...18_000), 1200)
        XCTAssertEqual(NumericField.snap(0, to: 30, in: 0...3600), 0)
        XCTAssertEqual(NumericField.snap(44, to: 30, in: 0...3600), 30)
    }

    func testSnapClampsToBounds() {
        XCTAssertEqual(NumericField.snap(-100, to: 1, in: 0...15), 0)
        XCTAssertEqual(NumericField.snap(999_999, to: 50, in: 50...18_000), 18_000)
        XCTAssertEqual(NumericField.snap(20_000, to: 50, in: 50...18_000), 18_000)
    }
}
