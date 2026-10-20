import XCTest
@testable import SteelSeriesConfig

/// Covers ``DeviceNotificationPolicy`` — the rule set deciding which link and battery
/// transitions are worth interrupting the user for.
///
/// The policy is pure precisely so these cases can be pinned without hardware: "the
/// app just launched onto an already-connected mouse" and "the battery has been at
/// 18 % for an hour" both have to *not* notify, and neither is convenient to reproduce
/// by unplugging a real mouse.
final class DeviceNotificationPolicyTests: XCTestCase {

    // MARK: - Link transitions

    /// The first poll has no predecessor, so a link that is already up is not news. A
    /// launch onto a working mouse must be silent.
    func testFirstPollReportsNoLinkEvent() {
        XCTAssertNil(DeviceNotificationPolicy.linkEvent(previous: nil, current: .ready))
        XCTAssertNil(DeviceNotificationPolicy.linkEvent(previous: nil, current: .offline))
    }

    func testLosingTheLinkNotifiesDisconnected() {
        XCTAssertEqual(DeviceNotificationPolicy.linkEvent(previous: .ready, current: .offline), .disconnected)
        XCTAssertEqual(DeviceNotificationPolicy.linkEvent(previous: .ready, current: .linkLost), .disconnected)
        XCTAssertEqual(DeviceNotificationPolicy.linkEvent(previous: .wired, current: .offline), .disconnected)
    }

    func testRegainingTheLinkNotifiesConnected() {
        XCTAssertEqual(DeviceNotificationPolicy.linkEvent(previous: .offline, current: .ready), .connected)
        XCTAssertEqual(DeviceNotificationPolicy.linkEvent(previous: .linkLost, current: .wired), .connected)
    }

    /// A steady state is not a transition — polling must not re-announce it.
    func testSteadyLinkStateIsSilent() {
        XCTAssertNil(DeviceNotificationPolicy.linkEvent(previous: .ready, current: .ready))
        XCTAssertNil(DeviceNotificationPolicy.linkEvent(previous: .offline, current: .offline))
    }

    /// Pairing and start-up are exactly what the header spinner is for; toasting each
    /// one would turn connecting into a slideshow.
    func testTransitionalPhasesAreSilent() {
        XCTAssertNil(DeviceNotificationPolicy.linkEvent(previous: .ready, current: .connecting))
        XCTAssertNil(DeviceNotificationPolicy.linkEvent(previous: .connecting, current: .connecting))
        XCTAssertNil(DeviceNotificationPolicy.linkEvent(previous: .offline, current: .unknown))
    }

    /// Wired-but-powered-off is not usable, so going wired → wiredIdle is a real drop.
    func testWiredIdleCountsAsDisconnected() {
        XCTAssertEqual(DeviceNotificationPolicy.linkEvent(previous: .wired, current: .wiredIdle), .disconnected)
        XCTAssertEqual(DeviceNotificationPolicy.linkEvent(previous: .wiredIdle, current: .wired), .connected)
    }

    // MARK: - Battery transitions

    func testCrossingALowStepNotifies() {
        XCTAssertEqual(
            DeviceNotificationPolicy.batteryEvent(previous: battery(25), current: battery(20)),
            .batteryLow
        )
        XCTAssertEqual(
            DeviceNotificationPolicy.batteryEvent(previous: battery(21), current: battery(19)),
            .batteryLow
        )
        XCTAssertEqual(
            DeviceNotificationPolicy.batteryEvent(previous: battery(12), current: battery(9)),
            .batteryLow
        )
    }

    /// Sitting below a step must not re-fire on every poll — only the crossing does.
    func testStayingBelowAStepIsSilent() {
        XCTAssertNil(DeviceNotificationPolicy.batteryEvent(previous: battery(18), current: battery(17)))
        XCTAssertNil(DeviceNotificationPolicy.batteryEvent(previous: battery(4), current: battery(3)))
    }

    /// Climbing back up (a charge) is not a downward crossing.
    func testClimbingIsSilent() {
        XCTAssertNil(DeviceNotificationPolicy.batteryEvent(previous: battery(9), current: battery(40)))
    }

    /// A mouse on its cable is not dying; a low reading while charging is skipped.
    func testLowWhileChargingIsSilent() {
        let charging = BatteryStatus(percent: 12, isCharging: true, isCharged: false)
        XCTAssertNil(DeviceNotificationPolicy.batteryEvent(previous: battery(30), current: charging))
    }

    func testChargeCompletionNotifiesOnce() {
        let charging = BatteryStatus(percent: 96, isCharging: true, isCharged: false)
        let charged = BatteryStatus(percent: 100, isCharging: false, isCharged: true)

        XCTAssertEqual(DeviceNotificationPolicy.batteryEvent(previous: charging, current: charged), .batteryFull)
        XCTAssertNil(
            DeviceNotificationPolicy.batteryEvent(previous: charged, current: charged),
            "An already-charged reading must not repeat the notification."
        )
    }

    /// A first reading that is already flat is worth saying, because the user got no
    /// warning while the app was closed. A first reading merely below a high step is not.
    func testFirstReadingOnlyNotifiesWhenGenuinelyLow() {
        XCTAssertEqual(DeviceNotificationPolicy.batteryEvent(previous: nil, current: battery(3)), .batteryLow)
        XCTAssertNil(
            DeviceNotificationPolicy.batteryEvent(previous: nil, current: battery(18)),
            "18% on a fresh reading is not an emergency — the badge now shows it."
        )
    }

    /// An unreadable battery is not a low battery.
    func testUnknownBatteryIsSilent() {
        XCTAssertNil(DeviceNotificationPolicy.batteryEvent(previous: battery(30), current: nil))
    }

    // MARK: - Combined

    func testLinkEventWinsOverBattery() {
        XCTAssertEqual(
            DeviceNotificationPolicy.event(
                previousPhase: .ready,
                phase: .offline,
                previousBattery: battery(30),
                battery: battery(10)
            ),
            .disconnected
        )
    }

    // MARK: - Helpers

    private func battery(_ percent: Int) -> BatteryStatus {
        BatteryStatus(percent: percent, isCharging: false, isCharged: false)
    }
}
