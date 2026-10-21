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

    /// The status as of the previous poll, so a transition can be told from a steady
    /// state. `nil` until the first poll completes — that gap is what stops launch from
    /// announcing a connection the user did not make.
    private var lastAnnouncedPhase: LinkPhase?
    private var lastAnnouncedBattery: BatteryStatus?

    var isBusy = false
    /// True when the local edits diverge from the saved profile.
    var isDirty = false

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

    private var autoSaveTask: Task<Void, Never>?
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
        scheduleAutoSave()
    }

    private func apply(_ config: DeviceConfiguration) {
        draft = config
        selectedConfigurationID = config.id
        isDirty = false
        mouseSettings = try? MouseSettings(parsing: config.settings)
    }

    // MARK: - Editing

    /// Apply a change to the parsed settings, then persist it and push it to the mouse.
    /// Saves are debounced so dragging a slider writes once, not once per pixel.
    func mutate(_ changes: (inout MouseSettings) -> Void) {
        guard var settings = mouseSettings else { return }
        changes(&settings)
        mouseSettings = settings
        isDirty = true
        scheduleAutoSave()
    }

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self?.autoSave()
        }
    }

    /// Persist the current edit and commit it to the mouse's memory.
    ///
    /// If a previous save is still in flight the last edit would otherwise be dropped,
    /// so this waits for the writer to become free before running.
    private func autoSave() async {
        while isBusy {
            try? await Task.sleep(for: .milliseconds(120))
            if Task.isCancelled { return }
        }
        _ = await save()
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
        guard phase == .ready, !isBusy else { return }

        guard let mouse = driver.attached() else {
            if !devices.isEmpty { devices = [] }
            selectedDeviceID = nil
            linkPhase = .offline
            batteryStatus = nil
            attachedProductID = nil
            sentCommands = nil
            announceTransition(phase: .unknown)
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

        announceTransition(phase: displayPhase)

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
        // macOS reports a Bluetooth peripheral's level and nothing else — no charging
        // flag, no "on the cable" signal. So neither charge state can be inferred here:
        // a full reading is just a full reading, not a completed charge. Guessing
        // "charged" from `percent >= 100` is what made a mouse sitting idle at 100 %
        // show a charging bolt.
        let status = HostBatteryReader.mouse(in: readings, preferringName: "Aerox 3").map {
            BatteryStatus(percent: $0.percent, isCharging: false, isCharged: false)
        }
        hostBatteryCache = (status, Date())
        return status
    }

    // MARK: - Notifications

    /// Compare this poll against the previous one and raise a notification if the
    /// transition warrants it. Decisions live in ``DeviceNotificationPolicy``; this only
    /// turns the verdict into a message and hands it to the notification centre.
    ///
    /// Runs on every poll, including the very first (`lastAnnounced*` are `nil`), where
    /// the policy suppresses a "connected" it did not see happen but still allows an
    /// already-low battery to be reported.
    private func announceTransition(phase: LinkPhase) {
        let previousPhase = lastAnnouncedPhase
        let previousBattery = lastAnnouncedBattery
        lastAnnouncedPhase = phase
        lastAnnouncedBattery = batteryStatus

        // Nothing to say while the device list is empty: that is the app's own start-up
        // state, not a disconnection the user caused.
        guard let device = selectedDevice else { return }
        guard let kind = DeviceNotificationPolicy.event(
            previousPhase: previousPhase,
            phase: phase,
            previousBattery: previousBattery,
            battery: batteryStatus
        ) else { return }

        let preferences = AppPreferences.shared
        if kind == .connected || kind == .disconnected {
            guard preferences.notifyOnConnect else { return }
        } else {
            guard preferences.notifyOnBattery else { return }
        }

        DeviceNotificationCenter.shared.show(
            DeviceNotification(
                kind: kind,
                deviceName: device.localizedName,
                imageName: device.imageUrl,
                detail: detail(for: kind, phase: phase),
                batteryProgress: batteryStatus.map { Double($0.percent) / 100 }
            ),
            style: preferences.notificationStyle
        )
    }

    private func detail(for kind: DeviceNotification.Kind, phase: LinkPhase) -> String {
        switch kind {
        case .connected:
            return phase.label
        case .disconnected:
            return phase.recoveryHint ?? phase.label
        case .batteryLow:
            return "Battery low · \(batteryStatus?.label ?? "—")"
        case .batteryFull:
            return "Fully charged"
        }
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
            scheduleAutoSave()
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
