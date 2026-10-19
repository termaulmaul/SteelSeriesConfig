import Foundation
import Observation

/// Central state for the app: engine discovery, device list, the configuration being
/// edited, and the pipeline that gets a change onto the hardware.
///
/// Four invariants this type exists to hold:
///
/// 1. **Never edit from a stale document.** `save()` re-reads the configuration from
///    the engine first and writes against *that*, so a change made elsewhere (the GG
///    client, another tool) is merged rather than clobbered.
/// 2. **Never write an unchecked body.** Everything passes `WriteSafetyPolicy` and is
///    preceded by a backup of the pre-write state.
/// 3. **Never claim success the engine did not confirm.** After a write the
///    configuration is re-read and the UI is refreshed from the response, not from
///    what we hoped we sent.
/// 4. **Never leave a change sitting on the server.** A write that is not followed by a
///    deploy is invisible on the mouse, which is indistinguishable from the app being
///    broken. `save()` persists *and* deploys; live edits deploy as they happen.
@MainActor
@Observable
final class ConfigurationStore {

    static let shared = ConfigurationStore()

    enum Phase: Equatable {
        case booting
        case ready
        /// The engine could not be reached or answered unexpectedly. Carries the
        /// human-readable reason, shown in the bar instead of a fake empty state.
        case unavailable(String)
    }

    private(set) var engine: EngineClient?
    private(set) var engineURL: URL?

    private(set) var phase: Phase = .booting

    var devices: [Device] = []
    var selectedDeviceID: Int?
    var configurations: [DeviceConfiguration] = []
    var selectedConfigurationID: String?

    /// The configuration as last read from the engine — the base for writes.
    var draft: DeviceConfiguration?
    /// Typed view over `draft.settings`, present only for devices whose schema this
    /// app models (currently mice). Absent means read-only, by design.
    var mouseSettings: MouseSettings?
    var syncStatus: SyncStatus?

    /// Wireless link state of the selected device. Refines the engine's `connected`
    /// flag for the status indicator; it never overrides it (see `displayPhase`).
    private(set) var linkPhase: LinkPhase = .unknown
    /// Battery of the selected device, when it reports one.
    ///
    /// `nil` is the normal state for a mouse on Bluetooth: the client only queries
    /// `charge_status` after `rf_status` answers, so a Bluetooth mouse has no battery
    /// reading anywhere in the GG stack either. Absent must never be drawn as empty.
    private(set) var batteryStatus: BatteryStatus?

    var isBusy = false
    /// True when the local edits diverge from what the engine last returned.
    var isDirty = false
    /// True while a live apply is in flight. Distinct from `isDirty`: a live apply puts
    /// the change on the mouse but does not persist a revision.
    private(set) var isLiveApplying = false

    var statusMessage: String?
    var statusIsError = false

    /// Backups for the currently open configuration, newest first.
    var backups: [URL] = []

    /// Set by `StatusBarController`; only affects polling cadence.
    var isPanelVisible = false

    /// The settings document already backed up for the current draft. Guards against
    /// writing one backup per slider tick — the state worth backing up only changes
    /// when the engine's copy changes.
    private var backedUpSettings: String?

    private var liveApplyTask: Task<Void, Never>?
    private var statusLoop: Task<Void, Never>?

    init() {}

    // MARK: - Derived

    var selectedDevice: Device? {
        devices.first { $0.id == selectedDeviceID }
    }

    var selectedConfiguration: DeviceConfiguration? {
        configurations.first { $0.id == selectedConfigurationID }
    }

    /// True when the bar's controls may mutate anything.
    var canEdit: Bool {
        mouseSettings != nil && draft != nil && engine != nil
    }

    var isHardwareInSync: Bool {
        syncStatus?.isSynced.value == true
    }

    /// Whether the engine currently reports the selected device as attached.
    ///
    /// `/devices` is the authority rather than the wireless link query, because the
    /// engine maintains it for every device class — a keyboard has no `rf_status` to
    /// ask about.
    var isConnected: Bool {
        selectedDevice?.connected.value == true
    }

    /// The phase the status indicator renders.
    ///
    /// `linkPhase` is a refinement and never an override. Two real cases need it:
    ///
    /// - a device that does not implement `rf_status` at all — a keyboard — would read
    ///   as perpetually "connecting" if the two signals were folded naively;
    /// - a mouse on **Bluetooth** answers `rf_status` with an empty `command_data`
    ///   even though it is attached and working, because `rf_status` describes the
    ///   dongle link. GG paints nothing in that case; this app says `ready`, because
    ///   `/devices` — which the engine maintains for every device class — says the
    ///   device is there.
    ///
    /// The other direction still holds: an unplugged device is `offline` no matter what
    /// the last `rf_status` said.
    var displayPhase: LinkPhase {
        guard selectedDevice != nil else { return .unknown }
        guard isConnected else { return .offline }

        switch linkPhase {
        case .connecting, .wired, .wiredIdle, .linkLost:
            return linkPhase
        case .unknown, .offline, .ready:
            return .ready
        }
    }

    /// Whether the device can be asked to change right now — attached *and* talking.
    var canReachDevice: Bool {
        isConnected && displayPhase.isUsable
    }

    // MARK: - Lifecycle

    /// Discover the engine and load the first mouse. Safe to call more than once;
    /// a second call is a full refresh.
    func bootstrap() async {
        phase = .booting
        isBusy = true
        defer { isBusy = false }

        guard let url = CorePropsLocator.resolveEngineURL() else {
            phase = .unavailable("SteelSeries GG configuration not found.")
            return
        }

        let client: EngineClient
        if let existing = engine, url == engineURL {
            client = existing
        } else {
            client = EngineClient(engineURL: url)
            engine = client
            engineURL = url
        }

        do {
            let list = try await client.devices()
            devices = list
            phase = .ready

            let preferred = list.first { $0.isMouse && $0.connected.value }
                ?? list.first { $0.connected.value }
                ?? list.first
            if let preferred {
                await selectDevice(id: preferred.id)
                await pollDeviceStatus()
            } else {
                selectedDeviceID = nil
                draft = nil
                mouseSettings = nil
                linkPhase = .unknown
                batteryStatus = nil
                announce("No SteelSeries devices detected.", error: false)
            }

            startStatusLoop()
        } catch {
            phase = .unavailable(error.localizedDescription)
        }
    }

    func selectDevice(id: Int) async {
        guard let engine else { return }
        selectedDeviceID = id
        selectedConfigurationID = nil
        draft = nil
        mouseSettings = nil
        syncStatus = nil
        linkPhase = .unknown
        batteryStatus = nil
        backups = []

        do {
            let configs = try await engine.configurations(deviceID: id)
            configurations = configs

            // Prefer whatever the engine marked as live on the device.
            let preferred = configs.first { $0.lastDeployed?.value == true }
                ?? configs.first { $0.active.value }
                ?? configs.first
            if let preferred {
                await openConfiguration(id: preferred.id)
            }
        } catch {
            announce(error.localizedDescription, error: true)
        }
    }

    func openConfiguration(id: String) async {
        guard let engine else { return }
        selectedConfigurationID = id

        do {
            let config = try await engine.configuration(id: id)
            apply(config)
            await refreshSyncStatus(deviceID: config.deviceId ?? selectedDeviceID ?? 0)
            refreshBackups()
        } catch {
            announce(error.localizedDescription, error: true)
        }
    }

    private func apply(_ config: DeviceConfiguration) {
        draft = config
        selectedConfigurationID = config.id
        isDirty = false
        // A new engine state has not been backed up yet.
        backedUpSettings = nil

        // A document this app cannot parse must stay visible but read-only, rather
        // than being replaced with an empty one on the next save.
        if let parsed = try? MouseSettings(parsing: config.settings), isMouseDevice {
            mouseSettings = parsed
        } else {
            mouseSettings = nil
        }
    }

    private var isMouseDevice: Bool {
        guard let deviceID = draft?.deviceId ?? selectedDeviceID else { return false }
        return devices.first { $0.id == deviceID }?.isMouse == true
    }

    // MARK: - Editing

    /// Apply a change to the parsed settings, then push it to the device.
    ///
    /// The change is reflected in the UI immediately, and a debounced live apply
    /// follows it onto the hardware — mirroring the GG client, where a slider moves the
    /// mouse before anything is saved. Live application is not persistence: the draft
    /// stays dirty and `save()` still has to run for the change to survive a reconnect.
    func mutate(_ changes: (inout MouseSettings) -> Void) {
        guard var settings = mouseSettings else { return }
        changes(&settings)
        mouseSettings = settings
        isDirty = true
        scheduleLiveApply()
    }

    func reloadDraft() {
        guard let draft else { return }
        apply(draft)
        announce("Edits discarded.", error: false)
    }

    /// Coalesce a burst of edits into one live apply.
    ///
    /// A slider drag emits dozens of `mutate` calls; without this each one would be a
    /// separate request to the engine and a separate device write.
    private func scheduleLiveApply() {
        liveApplyTask?.cancel()
        liveApplyTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            await self?.liveApply()
        }
    }

    /// Push the current settings to the device without persisting a revision.
    ///
    /// Deliberately quiet on the happy path beyond a one-line status: this runs while
    /// the user is dragging a slider, and a modal-ish banner per tick would be noise.
    func liveApply() async {
        guard let engine, let current = draft, let settings = mouseSettings else { return }
        guard !isBusy else { return }

        // The device can be asleep while edits are still pending in the draft — that is
        // a legitimate way to work, so the edit itself is never blocked. Only the push
        // is skipped, quietly: the panel already says "Disconnected", and an error
        // banner per slider tick would be noise. `save()` persists and deploys the
        // queued edits when the mouse comes back.
        guard canReachDevice else { return }

        let encoded: String
        do {
            encoded = try settings.encodedString()
            var candidate = current
            candidate.settings = encoded
            // Structural checks only. The live document is *meant* to be partial — the
            // engine drops the keys it refuses to change live — so the shrinkage guard
            // would reject a perfectly good payload.
            try WriteSafetyPolicy.validate(candidate)
        } catch {
            announce(error.localizedDescription, error: true)
            return
        }

        isLiveApplying = true
        defer { isLiveApplying = false }

        // One backup per engine state rather than one per tick.
        if backedUpSettings != current.settings {
            try? BackupStore.save(configuration: current)
            backedUpSettings = current.settings
            refreshBackups()
        }

        do {
            let liveDocument = try settings.encodedStringForLiveDeploy()
            try await engine.liveDeploy(current, settings: liveDocument)
        } catch {
            announce(error.localizedDescription, error: true)
            return
        }

        // The live document omitted the keys marked `no_live_deploy`. If the engine
        // took that omission as a replacement rather than a merge, the stored revision
        // just lost them — so check, and put the full document back if it did.
        let excluded = MouseSettings.livePreviewExcludedKeys(in: encoded)
        if !excluded.isEmpty,
           let stored = try? await engine.configuration(id: current.id),
           let parsed = try? AnyJSONValue.parse(stored.settings),
           excluded.contains(where: { parsed.objectValue?[$0] == nil }) {
            try? await engine.putConfiguration(candidateFor(current, settings: encoded))
        }

        await refreshSyncStatus(deviceID: current.deviceId ?? selectedDeviceID ?? 0)
        announce("Applied to the device.", error: false)
    }

    /// Read-modify-write, then deploy. See the type-level documentation for why every
    /// step exists.
    func save() async -> Bool {
        guard let engine, let current = draft, let settings = mouseSettings else { return false }

        isBusy = true
        defer { isBusy = false }

        do {
            var body = try await engine.configuration(id: current.id)

            let encoded = try settings.encodedString()
            var candidate = body
            candidate.settings = encoded
            candidate.name = current.name
            candidate.undeployedSettings = current.undeployedSettings
            try WriteSafetyPolicy.validate(candidate, previous: current)

            // Backup what the engine holds right now, not what we started from —
            // someone may have edited in the GG client since we opened this screen.
            try? BackupStore.save(configuration: body)

            body.settings = encoded
            body.name = current.name
            body.undeployedSettings = current.undeployedSettings

            try await engine.putConfiguration(body)

            // The PUT only persists. Without the deploy the mouse keeps running its old
            // profile, which looks exactly like the save having failed.
            try await engine.deploy(configurationID: current.id)

            let confirmed = try await engine.configuration(id: current.id)
            apply(confirmed)
            await refreshSyncStatus(deviceID: confirmed.deviceId ?? selectedDeviceID ?? 0)
            refreshBackups()
            announce("Saved and deployed to the device.", error: false)
            return true
        } catch {
            announce(error.localizedDescription, error: true)
            return false
        }
    }

    /// Push the saved configuration to the hardware without re-saving it.
    ///
    /// Kept alongside `save()` because the two are genuinely different operations: this
    /// re-asserts what the engine already holds, which is how you recover after the
    /// device was switched to another profile.
    func deploy() async -> Bool {
        guard let engine, let current = draft else { return false }

        isBusy = true
        defer { isBusy = false }

        do {
            try await engine.deploy(configurationID: current.id)
            if let config = try? await engine.configuration(id: current.id) {
                apply(config)
            }
            await refreshSyncStatus(deviceID: current.deviceId ?? selectedDeviceID ?? 0)
            announce("Deployed to device.", error: false)
            return true
        } catch {
            announce(error.localizedDescription, error: true)
            return false
        }
    }

    private func candidateFor(_ configuration: DeviceConfiguration, settings: String) -> DeviceConfiguration {
        var copy = configuration
        copy.settings = settings
        return copy
    }

    // MARK: - Device status

    /// Called by the panel controller when the popover opens or closes.
    func panelVisibilityChanged(_ visible: Bool) {
        isPanelVisible = visible
        guard visible else { return }

        Task { [weak self] in
            guard let self else { return }
            await self.pollDeviceStatus()
            await self.refreshSyncStatus(deviceID: self.draft?.deviceId ?? self.selectedDeviceID ?? 0)
        }
    }

    /// Start the status poll. Idempotent.
    private func startStatusLoop() {
        guard statusLoop == nil else { return }

        statusLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.pollDeviceStatus()
                // Three seconds while the panel is open (the user is watching), eight
                // while it is closed (only the menu bar symbol depends on it).
                let interval: Duration = self.isPanelVisible ? .seconds(3) : .seconds(8)
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// One poll: attachment, wireless link, battery — and device hot-plug.
    ///
    /// Deliberately silent on failure. This runs for the life of the app, so surfacing
    /// every transport hiccup would flicker the panel between "connected" and an error
    /// banner; `bootstrap()` is where engine loss is reported.
    private func pollDeviceStatus() async {
        guard let engine, phase == .ready else { return }

        guard let list = try? await engine.devices() else { return }
        if list != devices { devices = list }

        // Hot-plug: nothing selected yet, or the selected device went away.
        if selectedDeviceID == nil, let first = list.first {
            await selectDevice(id: first.id)
            return
        }
        if let id = selectedDeviceID, !list.contains(where: { $0.id == id }) {
            if let first = list.first {
                await selectDevice(id: first.id)
            } else {
                selectedDeviceID = nil
                draft = nil
                mouseSettings = nil
            }
            return
        }

        guard let deviceID = selectedDeviceID,
              let device = list.first(where: { $0.id == deviceID }),
              device.connected.value
        else {
            linkPhase = .offline
            batteryStatus = nil
            return
        }

        let rf = await (try? engine.deviceCommand(id: deviceID, command: ["rf_status": .object([:])]))
        let resolved = LinkPhase(rfPayload: rf ?? .null)
        linkPhase = resolved

        guard resolved.isUsable else {
            batteryStatus = nil
            return
        }

        let charge = await (try? engine.deviceCommand(id: deviceID, command: ["charge_status": .object([:])]))
        batteryStatus = charge.flatMap { BatteryStatus(payload: $0) }
    }

    private func refreshSyncStatus(deviceID: Int) async {
        guard let engine, deviceID != 0 else { return }
        syncStatus = try? await engine.syncStatus(deviceID: deviceID)
    }

    // MARK: - Backups

    func refreshBackups() {
        guard let id = draft?.id else { backups = []; return }
        backups = BackupStore.list(configurationID: id)
    }

    /// Load a backup into the draft. Deliberately does *not* write to the engine —
    /// restoring is a local edit until the user saves it.
    func stageBackup(_ url: URL) {
        do {
            let restored = try BackupStore.read(url)
            var staged = draft ?? restored
            staged.settings = restored.settings
            staged.undeployedSettings = restored.undeployedSettings
            staged.name = restored.name
            apply(staged)
            isDirty = true
            announce("Backup loaded. Save to write it to the device.", error: false)
        } catch {
            announce(error.localizedDescription, error: true)
        }
    }

    // MARK: - Status

    func announce(_ message: String, error: Bool) {
        statusMessage = message
        statusIsError = error
    }

    func launchEngine() {
        do {
            _ = try EngineProcessGuard.launchSteelSeriesGG()
            announce("Starting SteelSeries GG…", error: false)
        } catch {
            announce(error.localizedDescription, error: true)
        }
    }
}
