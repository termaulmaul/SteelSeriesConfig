import Foundation

/// One row of `GET /configuration/{id}` — which is also, field for field, the shape
/// `PUT /configuration/{id}` accepts.
///
/// The engine's write semantics are replace-not-patch: fields absent from the body
/// are blanked. That is what wiped this app's predecessor-in-spirit during research,
/// so every write path here sends the full, freshly-read object with only the edited
/// fields changed. See `WriteSafetyPolicy` for the guard that enforces it.
struct DeviceConfiguration: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    /// Serialised settings document. Kept as a `String` because that is exactly what
    /// the engine stores and returns; parsing happens in `MouseSettings`.
    var settings: String
    /// Pending, not-yet-deployed edits. The GG client writes these too, so they are
    /// round-tripped verbatim rather than being reset to `{}`.
    var undeployedSettings: String
    var active: FlexibleBool
    var applications: AnyJSONValue
    var bindings: AnyJSONValue
    var universalTriggers: AnyJSONValue
    var isQuicksetAutoCreated: FlexibleBool

    // Metadata carried for display; never edited by this app.
    var deviceId: Int?
    var lastDeployed: FlexibleBool?
    var mutable: FlexibleBool?
    var isDeleted: FlexibleBool?
    var syncConfig: FlexibleBool?
    var onboardProfileSlot: Int?
    var extraProperties: String?
    var configPageModalLocalizationKey: String?
    var cloudLastUpdatedAt: String?
    var onDeploySseCommandId: String?

    enum CodingKeys: String, CodingKey {
        case id, name, settings, active, applications, bindings
        case undeployedSettings
        case universalTriggers = "universal_triggers"
        case isQuicksetAutoCreated = "is_quickset_auto_created"
        case deviceId = "device_id"
        case lastDeployed = "last_deployed"
        case mutable
        case isDeleted = "is_deleted"
        case syncConfig = "sync_config"
        case onboardProfileSlot = "onboard_profile_slot"
        case extraProperties = "extra_properties"
        case configPageModalLocalizationKey = "config_page_modal_localization_key"
        case cloudLastUpdatedAt = "cloud_last_updated_at"
        case onDeploySseCommandId = "on_deploy_sse_command_id"
    }

    init(
        id: String,
        name: String,
        settings: String,
        undeployedSettings: String,
        active: FlexibleBool,
        applications: AnyJSONValue,
        bindings: AnyJSONValue,
        universalTriggers: AnyJSONValue,
        isQuicksetAutoCreated: FlexibleBool,
        deviceId: Int? = nil,
        lastDeployed: FlexibleBool? = nil,
        mutable: FlexibleBool? = nil,
        isDeleted: FlexibleBool? = nil,
        syncConfig: FlexibleBool? = nil,
        onboardProfileSlot: Int? = nil,
        extraProperties: String? = nil,
        configPageModalLocalizationKey: String? = nil,
        cloudLastUpdatedAt: String? = nil,
        onDeploySseCommandId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.settings = settings
        self.undeployedSettings = undeployedSettings
        self.active = active
        self.applications = applications
        self.bindings = bindings
        self.universalTriggers = universalTriggers
        self.isQuicksetAutoCreated = isQuicksetAutoCreated
        self.deviceId = deviceId
        self.lastDeployed = lastDeployed
        self.mutable = mutable
        self.isDeleted = isDeleted
        self.syncConfig = syncConfig
        self.onboardProfileSlot = onboardProfileSlot
        self.extraProperties = extraProperties
        self.configPageModalLocalizationKey = configPageModalLocalizationKey
        self.cloudLastUpdatedAt = cloudLastUpdatedAt
        self.onDeploySseCommandId = onDeploySseCommandId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? ""
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        settings = Self.decodeDocument(container, key: .settings)
        undeployedSettings = Self.decodeDocument(container, key: .undeployedSettings)
        active = (try? container.decode(FlexibleBool.self, forKey: .active)) ?? FlexibleBool(false)
        applications = (try? container.decodeIfPresent(AnyJSONValue.self, forKey: .applications)) ?? .null
        bindings = (try? container.decodeIfPresent(AnyJSONValue.self, forKey: .bindings)) ?? .array([])
        universalTriggers = (try? container.decodeIfPresent(AnyJSONValue.self, forKey: .universalTriggers)) ?? .null
        isQuicksetAutoCreated =
            (try? container.decode(FlexibleBool.self, forKey: .isQuicksetAutoCreated)) ?? FlexibleBool(false)

        deviceId = (try? container.decode(Int.self, forKey: .deviceId)) ?? nil
        lastDeployed = (try? container.decode(FlexibleBool.self, forKey: .lastDeployed)) ?? nil
        mutable = (try? container.decode(FlexibleBool.self, forKey: .mutable)) ?? nil
        isDeleted = (try? container.decode(FlexibleBool.self, forKey: .isDeleted)) ?? nil
        syncConfig = (try? container.decode(FlexibleBool.self, forKey: .syncConfig)) ?? nil
        onboardProfileSlot = (try? container.decode(Int.self, forKey: .onboardProfileSlot)) ?? nil
        extraProperties = (try? container.decode(String.self, forKey: .extraProperties)) ?? nil
        configPageModalLocalizationKey =
            (try? container.decode(String.self, forKey: .configPageModalLocalizationKey)) ?? nil
        cloudLastUpdatedAt = (try? container.decode(String.self, forKey: .cloudLastUpdatedAt)) ?? nil
        onDeploySseCommandId = (try? container.decode(String.self, forKey: .onDeploySseCommandId)) ?? nil
    }

    /// The engine normally returns these as JSON strings. If a build ever returns a
    /// live object instead, re-serialise rather than losing the document.
    private static func decodeDocument(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> String {
        if let raw = try? container.decode(String.self, forKey: key) { return raw }
        if let value = try? container.decode(AnyJSONValue.self, forKey: key) {
            return (try? value.compactString()) ?? ""
        }
        return ""
    }

    /// The exact eight fields the GG client sends on update. Everything else in the
    /// response is read-back metadata, so it is deliberately left out of the body.
    func putBody() -> [String: AnyJSONValue] {
        [
            "name": .string(name),
            "settings": .string(settings),
            "undeployedSettings": .string(undeployedSettings),
            "active": .bool(active.value),
            "applications": applications,
            "bindings": bindings,
            "universal_triggers": universalTriggers,
            "is_quickset_auto_created": .bool(isQuicksetAutoCreated.value),
        ]
    }
}

struct ConfigurationResponse: Decodable, Sendable {
    let configuration: DeviceConfiguration
}

struct ConfigurationsResponse: Decodable, Sendable {
    let configurations: [DeviceConfiguration]
}
