import Foundation
import Observation

/// Central state for the app: engine discovery, device list, the configuration being
/// edited, and the save pipeline.
///
/// Three invariants this type exists to hold:
///
/// 1. **Never edit from a stale document.** `save()` re-reads the configuration from
///    the engine first and writes against *that*, so a change made elsewhere (the GG
///    client, another tool) is merged rather than clobbered.
/// 2. **Never write an unchecked body.** Everything passes `WriteSafetyPolicy` and is
///    preceded by a backup of the pre-write state.
/// 3. **Never claim success the engine did not confirm.** After a write the
///    configuration is re-read and the UI is refreshed from the response, not from
///    what we hoped we sent.
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

    var isBusy = false
    /// True when the local edits diverge from what the engine last returned.
    var isDirty = false

    var statusMessage: String?
    var statusIsError = false

    /// Backups for the currently open configuration, newest first.
    var backups: [URL] = []

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
            } else {
                selectedDeviceID = nil
                draft = nil
                mouseSettings = nil
                announce("No SteelSeries devices detected.", error: false)
            }
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
            syncStatus = try? await engine.syncStatus(deviceID: config.deviceId ?? selectedDeviceID ?? 0)
            refreshBackups()
        } catch {
            announce(error.localizedDescription, error: true)
        }
    }

    private func apply(_ config: DeviceConfiguration) {
        draft = config
        selectedConfigurationID = config.id
        isDirty = false

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

    /// Apply a change to the parsed settings and mark the draft dirty.
    ///
    /// Changes are local until `save()` runs: the popover shows exactly what would be
    /// written, and nothing reaches the mouse without an explicit save.
    func mutate(_ changes: (inout MouseSettings) -> Void) {
        guard var settings = mouseSettings else { return }
        changes(&settings)
        mouseSettings = settings
        isDirty = true
    }

    func reloadDraft() {
        guard let draft else { return }
        apply(draft)
        announce("Edits discarded.", error: false)
    }

    /// Read-modify-write. See the type-level documentation for why every step exists.
    func save() async -> Bool {
        guard let engine, let current = draft, let settings = mouseSettings else { return false }

        isBusy = true
        defer { isBusy = false }

        do {
            var body = try await engine.configuration(id: current.id)

            let encoded = try settings.encodedString()
            try WriteSafetyPolicy.validate(
                {
                    var candidate = body
                    candidate.settings = encoded
                    candidate.name = current.name
                    candidate.undeployedSettings = current.undeployedSettings
                    return candidate
                }(),
                previous: current
            )

            // Backup what the engine holds right now, not what we started from —
            // someone may have edited in the GG client since we opened this screen.
            if let backupURL = try BackupStore.save(configuration: body) {
                _ = backupURL
            }

            body.settings = encoded
            body.name = current.name
            body.undeployedSettings = current.undeployedSettings

            try await engine.putConfiguration(body)

            let confirmed = try await engine.configuration(id: current.id)
            apply(confirmed)
            syncStatus = try? await engine.syncStatus(deviceID: confirmed.deviceId ?? selectedDeviceID ?? 0)
            refreshBackups()
            announce("Saved.", error: false)
            return true
        } catch {
            announce(error.localizedDescription, error: true)
            return false
        }
    }

    /// Push the saved configuration to the hardware. POST, matching the GG client's
    /// `submit` verb — callers must confirm with the user first.
    func deploy() async -> Bool {
        guard let engine, let id = draft?.id else { return false }

        isBusy = true
        defer { isBusy = false }

        do {
            try await engine.deploy(configurationID: id)
            if let config = try? await engine.configuration(id: id) {
                apply(config)
            }
            syncStatus = try? await engine.syncStatus(deviceID: draft?.deviceId ?? selectedDeviceID ?? 0)
            announce("Deployed to device.", error: false)
            return true
        } catch {
            announce(error.localizedDescription, error: true)
            return false
        }
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
