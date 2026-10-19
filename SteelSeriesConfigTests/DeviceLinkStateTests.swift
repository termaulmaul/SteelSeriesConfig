import XCTest
@testable import SteelSeriesConfig

/// Covers the two device-status protocols the status indicator depends on — `rf_status`
/// and `charge_status` — plus the live-deploy document the store produces for every
/// edit. All three are decoded from payloads copied out of the GG client's renderer, so
/// these tests are pinning a protocol contract rather than a preference.
final class DeviceLinkStateTests: XCTestCase {

    // MARK: - Link phase

    /// The one payload that means "the mouse is talking to us": rf_mode 4 + rf_status 1.
    func testReadyLinkFromRfStatus() {
        let phase = LinkPhase(rfPayload: fixture(["rf_mode": 4, "rf_status": 1]))

        XCTAssertEqual(phase, .ready)
        XCTAssertTrue(phase.isUsable)
        XCTAssertFalse(phase.isTransitional)
    }

    /// Both wired encodings are derived from the client's `rfModeToText` table rather
    /// than from the mode number alone — 16 is powered on, 17 is powered off, and only
    /// 16 should still offer edits.
    func testWiredEncodingsDifferByPowerState() {
        XCTAssertEqual(LinkPhase(rfPayload: fixture(["rf_mode": 16, "rf_status": 2])), .wired)
        XCTAssertEqual(LinkPhase(rfPayload: fixture(["rf_mode": 17, "rf_status": 2])), .wiredIdle)

        XCTAssertTrue(LinkPhase(rfPayload: fixture(["rf_mode": 16, "rf_status": 2])).isUsable)
        XCTAssertFalse(LinkPhase(rfPayload: fixture(["rf_mode": 17, "rf_status": 2])).isUsable)
        XCTAssertTrue(LinkPhase(rfPayload: fixture(["rf_mode": 17, "rf_status": 2])).recoveryHint != nil)
    }

    /// Mode 2 is the client's pairing state, which is expected to resolve on its own —
    /// that is what the spinner is for.
    func testPairingIsTransitionalRatherThanBroken() {
        let phase = LinkPhase(rfPayload: fixture(["rf_mode": 2, "rf_status": 4]))

        XCTAssertEqual(phase, .connecting)
        XCTAssertTrue(phase.isTransitional)
        XCTAssertFalse(phase.isUsable)
    }

    func testStatusOutsideTheKnownTableFallsBackToLinkLost() {
        let phase = LinkPhase(rfPayload: fixture(["rf_mode": 4, "rf_status": 2]))

        XCTAssertEqual(phase, .linkLost)
        XCTAssertFalse(phase.isUsable)
        XCTAssertNotNil(phase.recoveryHint)
    }

    /// An empty `command_data` is what the engine returns for a mouse that is switched
    /// off. Reading it as "unknown" would leave the panel saying "Connecting…" forever;
    /// reading it as a failure would surface an error for a perfectly normal state.
    ///
    /// The same answer also comes back from a mouse that is perfectly fine on Bluetooth,
    /// where `rf_status` has nothing to describe — so `.offline` here is deliberately
    /// the *raw* reading, and only `ConfigurationStore.displayPhase` decides whether it
    /// stays disconnected or becomes `ready` on the strength of `/devices`.
    func testAbsentPayloadIsOfflineNotUnknown() {
        XCTAssertEqual(LinkPhase(rfPayload: .null), .offline)
        XCTAssertEqual(LinkPhase(rfPayload: .object([:])), .offline)
        XCTAssertEqual(LinkPhase(rfPayload: .object(["rf_status": .null])), .offline)
        XCTAssertFalse(LinkPhase(rfPayload: .null).isUsable)
    }

    // MARK: - Battery

    /// Percentage family: `battery_level` is 0…100 and charge_mode is 0/1/2.
    func testPercentageFamilyDecoding() {
        let charging = BatteryStatus(payload: charge(76, mode: 1))
        XCTAssertEqual(charging?.percent, 76)
        XCTAssertEqual(charging?.isCharging, true)
        XCTAssertEqual(charging?.isCharged, false)

        let full = BatteryStatus(payload: charge(100, mode: 2))
        XCTAssertEqual(full?.percent, 100)
        XCTAssertEqual(full?.isCharging, false)
        XCTAssertEqual(full?.isCharged, true)

        let resting = BatteryStatus(payload: charge(42, mode: 0))
        XCTAssertEqual(resting?.isCharging, false)
        XCTAssertEqual(resting?.isCharged, false)
    }

    /// Level-code family: `battery_level` is a coarse 0/1/2/4 code and charge_mode is
    /// 1/2/4/8. This is the encoding the mouse itself uses — taken from the helper
    /// module its device card imports, not from the percentage card's tables.
    func testLevelCodeFamilyDecodesToPercentages() {
        let empty = BatteryStatus(payload: charge(0, mode: 1))
        XCTAssertEqual(empty?.percent, 0)
        XCTAssertEqual(empty?.isCharging, false)

        let half = BatteryStatus(payload: charge(2, mode: 2))
        XCTAssertEqual(half?.percent, 50)
        XCTAssertEqual(half?.isCharging, true)

        let full = BatteryStatus(payload: charge(4, mode: 4))
        XCTAssertEqual(full?.percent, 100)
        XCTAssertEqual(full?.isCharged, true)
        XCTAssertEqual(full?.isCharging, false)
    }

    func testUnknownPayloadIsUnknownRatherThanEmpty() {
        XCTAssertNil(BatteryStatus(payload: .null))
        XCTAssertNil(BatteryStatus(payload: .object([:])))
        XCTAssertNil(BatteryStatus(payload: .object(["charge_status": .object([:])])))
    }

    /// Low is decided at 25 % — the second-lowest level code, which the client labels
    /// `iconBatteryDepleted` — and only while not charging: a mouse at 25 % that is on
    /// its cable is not an emergency. GG has no red state to copy (its indicator is a
    /// sprite whose width changes per level), so the number is ours; what is *not* ours
    /// is which level counts as depleted.
    func testLowBatteryIsTheSecondLowestLevelCodeAndNeverWhileCharging() {
        XCTAssertEqual(BatteryStatus(payload: charge(0, mode: 1))?.isLow, true)
        XCTAssertEqual(BatteryStatus(payload: charge(1, mode: 1))?.isLow, true)
        XCTAssertEqual(BatteryStatus(payload: charge(2, mode: 1))?.isLow, false)
        XCTAssertEqual(BatteryStatus(payload: charge(4, mode: 1))?.isLow, false)

        // Charging at the lowest code is a mouse on its cable, not a dying one.
        XCTAssertEqual(BatteryStatus(payload: charge(0, mode: 2))?.isLow, false)

        XCTAssertTrue(BatteryStatus(percent: 25, isCharging: false, isCharged: false).isLow)
        XCTAssertFalse(BatteryStatus(percent: 26, isCharging: false, isCharged: false).isLow)
        XCTAssertFalse(BatteryStatus(percent: 5, isCharging: true, isCharged: false).isLow)
    }

    /// `3` is absent from the mouse's own `batteryLevelToClass` table but present in the
    /// sibling family's `batteryLevelToText` (`3 → battery_75`), so it is decoded rather
    /// than treated as unknown.
    func testIntermediateLevelCodeStillDecodes() {
        XCTAssertEqual(BatteryStatus.percent(forLevelCode: 3), 75)
    }

    func testPercentagesAreClampedToTheDisplayableRange() {
        XCTAssertEqual(BatteryStatus(percent: -4, isCharging: false, isCharged: false).percent, 0)
        XCTAssertEqual(BatteryStatus(percent: 900, isCharging: false, isCharged: false).percent, 100)
    }

    // MARK: - Live deploy document

    /// The whole reason `no_live_deploy` exists: `button_mappings` carries it on this
    /// mouse, and live-applying it would rebind buttons with no confirmation.
    /// Reproduced from the GG client's own pre-liveDeploy filter.
    func testLiveDeployDropsNoLiveDeployKeys() throws {
        let settings = try MouseSettings(parsing: Fixture.aeroxSettings)

        let live = try settings.encodedStringForLiveDeploy()
        let parsed = try XCTUnwrap(AnyJSONValue.parse(live).objectValue)

        XCTAssertNil(parsed["button_mappings"], "button_mappings is marked no_live_deploy and must be dropped.")
        XCTAssertNotNil(parsed["polling_rate"], "Everything else must still be applied live.")
        XCTAssertNotNil(parsed["batch_resolution"])
        XCTAssertNotNil(
            settings.json["button_mappings"],
            "Stripping happens on the serialised copy only; the editable document must keep the key."
        )
    }

    /// The store compares the engine's stored copy against this list after a live
    /// deploy, so a mismatch would either never fire or fire on every edit.
    func testExcludedKeysAgreeWithTheEncoder() throws {
        let settings = try MouseSettings(parsing: Fixture.aeroxSettings)
        let live = try settings.encodedStringForLiveDeploy()

        XCTAssertEqual(MouseSettings.livePreviewExcludedKeys(in: Fixture.aeroxSettings), ["button_mappings"])
        XCTAssertEqual(MouseSettings.livePreviewExcludedKeys(in: live), [], "Already stripped.")

        let full = try AnyJSONValue.parse(Fixture.aeroxSettings)
        let liveCount = try XCTUnwrap(AnyJSONValue.parse(live).objectValue).count
        let fullCount = try XCTUnwrap(full.objectValue).count
        XCTAssertEqual(liveCount, fullCount - 1, "Exactly one key should be dropped.")
    }

    // MARK: - Presets

    /// Presets are written straight into an engine-units slot. A preset that was not on
    /// the grid would round down and silently set a different CPI than the one labelled.
    func testCPIPresetsSitExactlyOnTheGrid() {
        XCTAssertEqual(MouseSettings.cpiPresets, [1000, 2000, 5000, 6000])
        XCTAssertEqual(Set(MouseSettings.cpiPresets).count, MouseSettings.cpiPresets.count)

        for cpi in MouseSettings.cpiPresets {
            XCTAssertEqual(cpi % MouseSettings.cpiScale, 0)
            XCTAssertGreaterThanOrEqual(cpi, MouseSettings.cpiMinimum)
            XCTAssertLessThanOrEqual(cpi, MouseSettings.cpiMaximum)
            XCTAssertEqual(MouseSettings.quantise(cpi), cpi)
        }
    }

    /// A preset rewrites only the step the user is currently on; the rest of the ladder
    /// is their tuning and must survive untouched.
    func testPresetRewritesOnlyTheActiveStep() throws {
        var settings = try MouseSettings(parsing: Fixture.aeroxSettings)

        settings.setActiveCPIValue(6000)

        XCTAssertEqual(settings.activeCPI, 6000)
        XCTAssertEqual(settings.rawCPI(step: 1), 120)
        XCTAssertEqual(settings.rawCPI(step: 2), 9, "Untouched steps keep their value.")
        XCTAssertEqual(settings.cpiLevelCount, 5, "The ladder shape must not change.")
    }

    // MARK: - Helpers

    private func fixture(_ status: [String: Int]) -> AnyJSONValue {
        .object(["rf_status": .object(status.mapValues { .int($0) })])
    }

    private func charge(_ level: Int, mode: Int) -> AnyJSONValue {
        .object(["charge_status": .object([
            "battery_level": .int(level),
            "charge_mode": .int(mode),
        ])])
    }
}
