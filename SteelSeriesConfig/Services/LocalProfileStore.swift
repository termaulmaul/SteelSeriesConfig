import Foundation

/// The mouse profile, kept on disk because the mouse cannot report its settings back.
///
/// Stored in the same `DeviceConfiguration` shape the GG engine used, so the settings
/// model, the write-safety checks and the backup store all keep working unchanged.
enum LocalProfileStore {

    static let configurationID = "aerox-3-wireless"

    nonisolated(unsafe) static var fileURLOverride: URL?

    static var fileURL: URL {
        if let fileURLOverride { return fileURLOverride }
        return BackupStore.applicationSupportURL
            .appendingPathComponent("SteelSeriesConfig/profiles", isDirectory: true)
            .appendingPathComponent("\(configurationID).json")
    }

    /// The saved profile; on first launch, the newest backup taken while the app still
    /// ran on GG (so tuned settings carry over), else the factory defaults.
    static func load() -> DeviceConfiguration {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode(DeviceConfiguration.self, from: data) {
            return saved
        }
        var profile = newestBackup() ?? defaultConfiguration()
        profile.id = configurationID
        profile.deviceId = ConfigurationStore.deviceID
        return profile
    }

    static func save(_ configuration: DeviceConfiguration) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration).write(to: fileURL, options: .atomic)
    }

    private static func newestBackup() -> DeviceConfiguration? {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let walker = FileManager.default.enumerator(at: BackupStore.rootURL, includingPropertiesForKeys: keys)
        else { return nil }
        let files = walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "json" }
        let newestFirst = files.sorted {
            let a = (try? $0.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            return a > b
        }
        return newestFirst.lazy
            .compactMap { try? BackupStore.read($0) }
            .first { (try? MouseSettings(parsing: $0.settings))?.json["batch_resolution"] != nil }
    }

    /// rivalcfg's defaults for this mouse, in the engine's document layout.
    static func defaultConfiguration() -> DeviceConfiguration {
        DeviceConfiguration(
            id: configurationID,
            name: "Default",
            settings: defaultSettings,
            undeployedSettings: "{}",
            active: FlexibleBool(true),
            applications: .null,
            bindings: .array([]),
            universalTriggers: .null,
            isQuicksetAutoCreated: FlexibleBool(false),
            deviceId: ConfigurationStore.deviceID
        )
    }

    static let defaultSettings = """
    {"batch_resolution":{"active_level_index":0,"num_cpi_levels":5,"resolution_1":8,\
    "resolution_2":16,"resolution_3":24,"resolution_4":48,"resolution_5":64},\
    "polling_rate":{"hz":1000,"val":0},\
    "power_saving_timeout":{"timeout":300000},\
    "lighting_settings":{"idle_timeout":30000},\
    "default_lighting_enabled":{"default_lighting_enabled":1},\
    "reactive_lighting":{"enable_random_color":0,"color":{"r":255,"g":255,"b":255}},\
    "button_mappings":{"no_live_deploy":1,"buttons":[\
    {"function":1,"key_codes":[0,0,0,0]},{"function":2,"key_codes":[0,0,0,0]},\
    {"function":3,"key_codes":[0,0,0,0]},{"function":4,"key_codes":[0,0,0,0]},\
    {"function":5,"key_codes":[0,0,0,0]},{"function":48,"key_codes":[0,0,0,0]},\
    {"function":49,"key_codes":[0,0,0,0]},{"function":50,"key_codes":[0,0,0,0]}]}}
    """
}
