import Foundation
import Observation

/// Central state for the app: device discovery, the profile being edited, and the
/// pipeline that gets a change onto the hardware.
///
/// The mouse is driven directly over HID (`HIDMouseDriver`), so SteelSeries GG is
/// not needed. The firmware cannot report its settings back, which shapes the four
/// invariants this type holds:
///
/// 1. **The profile file is the source of truth.** It is what the app shows, what a
///    save writes, and what is re-sent when the mouse reappears.
/// 2. **Never write an unchecked document.** Everything passes `WriteSafetyPolicy`
///    and is preceded by a backup of the profile it replaces.
/// 3. **Live edits are not saves.** A change reaches the mouse as it is made, but only
///    `save()` persists the profile and commits the settings to the mouse's flash.
/// 4. **Only send what changed.** Live apply diffs the command list against what was
///    last sent, so dragging a CPI slider does not rewrite the button map each tick.
@MainActor
@Observable
final class ConfigurationStore {

    static let shared = ConfigurationStore()

    /// The one device this app drives. The id only has to be stable for the session.
    nonisolated static let deviceID = 1

    enum Phase: Equatable {
        case booting
        case ready
        /// Kept for the views; the HID backend has no failure that stops the whole
        /// app — a missing mouse is "no device", not "unavailable".
        case unavailable(String)
    }

    private(set) var phase: Phase = .booting

    var devices: [Device] = []
    var selectedDeviceID: Int?
    var configurations: [DeviceConfiguration] = []
    var selectedConfigurationID: String?

    /// The profile as last saved — the base for writes.
    var draft: DeviceConfiguration?
    var mouseSettings: MouseSettings?

    private(set) var linkPhase: LinkPhase = .unknown
    private(set) var batteryStatus: BatteryStatus?

    var isBusy = false
    /// True when the local edits diverge from the saved profile.
    var isDirty = false
    private(set) var isLiveApplying = false

    var statusMessage: String?
    var statusIsError = false

    var backups: [URL] = []

    /// Set by `StatusBarController`; only affects polling cadence.
    var isPanelVisible = false

    private let driver: HIDMouseDriver
    /// Commands as last accepted by the attached mouse. `nil` forces a full resend —
    /// after (re)attach, because the mouse may have been reprogrammed elsewhere.
    private var sentCommands: [[UInt8]]?
    private var attachedProductID: Int?

    private var liveApplyTask: Task<Void, Never>?
    private var statusLoop: Task<Void, Never>?

    init(driver: HIDMouseDriver = .shared) {
        self.driver = driver
    }

    // MARK: - Derived

    var selectedDevice: Device? {
        devices.first { $0.id == selectedDeviceID }
    }

    var selectedConfiguration: DeviceConfiguration? {
        configurations.first { $0.id == selectedConfigurationID }
    }

    var canEdit: Bool {
        mouseSettings != nil && draft != nil
    }

    var isConnected: Bool {
        selectedDevice?.connected.value == true
    }

    var displayPhase: LinkPhase {
        guard selectedDevice != nil else { return .unknown }
        guard isConnected else { return .offline }
        return linkPhase
    }

    var canReachDevice: Bool {
        isConnected && displayPhase.isUsable
    }

    // MARK: - Lifecycle

    /// Load the profile and look for the mouse. Safe to call more than once.
    func bootstrap() async {
        phase = .booting
        let profile = LocalProfileStore.load()
        configurations = [profile]
        apply(profile)
        refreshBackups()
        sentCommands = nil
        attachedProductID = nil

        phase = .ready
        await pollDeviceStatus()
        startStatusLoop()
    }

    func reloadDraft() {
        guard let draft else { return }
        apply(draft)
        announce("Edits discarded.", error: false)
        scheduleLiveApply()
    }

    private func apply(_ config: DeviceConfiguration) {
        draft = config
        selectedConfigurationID = config.id
        isDirty = false
        mouseSettings = try? MouseSettings(parsing: config.settings)
    }

    // MARK: - Editing

    /// Apply a change to the parsed settings, then push it to the mouse (debounced).
    /// The draft stays dirty until `save()`.
    func mutate(_ changes: (inout MouseSettings) -> Void) {
        guard var settings = mouseSettings else { return }
        changes(&settings)
        mouseSettings = settings
        isDirty = true
        scheduleLiveApply()
    }

    private func scheduleLiveApply() {
        liveApplyTask?.cancel()
        liveApplyTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            await self?.liveApply()
        }
    }

    /// Push the current settings to the mouse without persisting them.
    func liveApply() async {
        guard let settings = mouseSettings, !isBusy, canReachDevice else { return }
        isLiveApplying = true
        defer { isLiveApplying = false }

        do {
            if try await send(settings) {
                announce("Applied to the device.", error: false)
            }
        } catch {
            announce(error.localizedDescription, error: true)
        }
    }

    /// Persist the profile, then commit it to the mouse's onboard memory.
    func save() async -> Bool {
        guard let current = draft, let settings = mouseSettings else { return false }

        isBusy = true
        defer { isBusy = false }

        do {
            var candidate = current
            candidate.settings = try settings.encodedString()
            try WriteSafetyPolicy.validate(candidate, previous: current)

            try? BackupStore.save(configuration: current)
            try LocalProfileStore.save(candidate)
            configurations = [candidate]
            apply(candidate)
            refreshBackups()

            guard canReachDevice else {
                announce("Saved. It will be applied when the mouse is back.", error: false)
                return true
            }
            try await send(settings)
            try await commitToFlash()
            announce("Saved to the mouse.", error: false)
            return true
        } catch {
            announce(error.localizedDescription, error: true)
            return false
        }
    }

    /// Re-send the whole saved profile — the recovery path after the mouse was
    /// reprogrammed by another tool.
    func deploy() async -> Bool {
        guard let settings = draft.flatMap({ try? MouseSettings(parsing: $0.settings) }) else { return false }
        guard canReachDevice else {
            announce(HIDMouseDriver.DriverError.notConnected.localizedDescription, error: true)
            return false
        }

        isBusy = true
        defer { isBusy = false }

        do {
            sentCommands = nil
            try await send(settings)
            try await commitToFlash()
            announce("Applied to the mouse.", error: false)
            return true
        } catch {
            announce(error.localizedDescription, error: true)
            return false
        }
    }

    /// Send the commands that differ from what the mouse already has.
    /// Returns whether anything was sent.
    @discardableResult
    private func send(_ settings: MouseSettings) async throws -> Bool {
        guard let mouse = driver.attached() else { throw HIDMouseDriver.DriverError.notConnected }
        let commands = AeroxProtocol.commands(for: settings)
        var accepted = sentCommands ?? []
        var sentAny = false

        for (index, command) in commands.enumerated() {
            if index < accepted.count, accepted[index] == command { continue }
            try await driver.send(command, to: mouse)
            sentAny = true
            if index < accepted.count { accepted[index] = command } else { accepted.append(command) }
            sentCommands = accepted
        }
        sentCommands = accepted
        return sentAny
    }

    private func commitToFlash() async throws {
        guard let mouse = driver.attached() else { throw HIDMouseDriver.DriverError.notConnected }
        try await driver.send(AeroxProtocol.saveToFlash, to: mouse)
    }

    // MARK: - Device status

    func panelVisibilityChanged(_ visible: Bool) {
        isPanelVisible = visible
        guard visible else { return }
        Task { [weak self] in await self?.pollDeviceStatus() }
    }

    private func startStatusLoop() {
        guard statusLoop == nil else { return }
        statusLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.pollDeviceStatus()
                let interval: Duration = self.isPanelVisible ? .seconds(3) : .seconds(8)
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// One poll: presence on the HID bus, then the battery query, which doubles as the
    /// link check over the receiver (no answer = mouse off or out of range).
    private func pollDeviceStatus() async {
        guard phase == .ready, !isBusy, !isLiveApplying else { return }

        guard let mouse = driver.attached() else {
            if !devices.isEmpty { devices = [] }
            selectedDeviceID = nil
            linkPhase = .offline
            batteryStatus = nil
            attachedProductID = nil
            sentCommands = nil
            return
        }

        let response = try? await driver.query(AeroxProtocol.batteryQuery, to: mouse)
        var battery = response.flatMap { $0 }.flatMap(AeroxProtocol.battery(response:))
        // Only the receiver stays enumerated while the mouse is off, so only there does
        // a missing battery answer mean "not talking". A cabled or Bluetooth mouse that
        // is on the bus is, by definition, on.
        let talking = !mouse.model.isWireless || battery != nil
        if battery == nil, mouse.model.transport == .bluetooth {
            battery = await hostBattery()
        }

        let device = Device(id: Self.deviceID, model: mouse.model, connected: true)
        if devices != [device] { devices = [device] }
        selectedDeviceID = device.id
        switch mouse.model.transport {
        case .usb: linkPhase = .wired
        case .receiver, .bluetooth: linkPhase = talking ? .ready : .offline
        }
        batteryStatus = battery

        // A mouse that just appeared (or woke up) gets the profile, so it always runs
        // what the app shows.
        if !talking {
            sentCommands = nil
        } else if attachedProductID != mouse.model.productID || sentCommands == nil {
            attachedProductID = mouse.model.productID
            if let settings = mouseSettings {
                try? await send(settings)
            }
        }
    }

    /// macOS' own reading for a Bluetooth mouse (the number System Settings shows),
    /// cached briefly because it costs a `system_profiler` launch.
    private var hostBatteryCache: (status: BatteryStatus?, at: Date)?

    private func hostBattery() async -> BatteryStatus? {
        if let cache = hostBatteryCache, Date().timeIntervalSince(cache.at) < 20 {
            return cache.status
        }
        let readings = (await HostBatteryReader.rawJSON()).map(HostBatteryReader.parse) ?? []
        let status = HostBatteryReader.mouse(in: readings, preferringName: "Aerox 3").map {
            BatteryStatus(percent: $0.percent, isCharging: false, isCharged: $0.percent >= 100)
        }
        hostBatteryCache = (status, Date())
        return status
    }

    // MARK: - Backups

    func refreshBackups() {
        guard let id = draft?.id else { backups = []; return }
        backups = BackupStore.list(configurationID: id)
    }

    /// Load a backup into the editor. Deliberately does *not* save — restoring is a
    /// local edit until the user saves it.
    func stageBackup(_ url: URL) {
        do {
            let restored = try BackupStore.read(url)
            mouseSettings = try MouseSettings(parsing: restored.settings)
            isDirty = true
            scheduleLiveApply()
            announce("Backup loaded. Save to keep it.", error: false)
        } catch {
            announce(error.localizedDescription, error: true)
        }
    }

    // MARK: - Status

    func announce(_ message: String, error: Bool) {
        statusMessage = message
        statusIsError = error
    }
}
