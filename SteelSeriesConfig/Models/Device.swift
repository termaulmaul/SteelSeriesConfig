import Foundation

/// Device category, derived from `deviceTypeName` rather than the numeric `type`
/// field, whose numbering is an internal engine enum we have no stable mapping for.
enum DeviceCategory: String, CaseIterable, Sendable, Identifiable {
    case mouse = "Mouse"
    case keyboard = "Keyboard"
    case headset = "Headset"
    case other = "Other"

    var id: String { rawValue }

    init(deviceTypeName: String) {
        let lowered = deviceTypeName.lowercased()
        if lowered.contains("mouse") { self = .mouse }
        else if lowered.contains("key") { self = .keyboard }
        else if lowered.contains("head") || lowered.contains("ear") { self = .headset }
        else { self = .other }
    }
}

/// One row of `GET /devices`.
///
/// Decoding is deliberately lenient per field: a single odd value must not be able to
/// discard the entire device list, because the list is the app's front door.
struct Device: Identifiable, Codable, Equatable, Sendable {
    let id: Int
    let name: String
    let fullName: String
    let displayName: String
    let deviceTypeName: String
    let type: Int
    let productId: Int
    let connected: FlexibleBool
    let imageUrl: String?
    let configurationMetadata: [ConfigurationMetadata]?

    enum CodingKeys: String, CodingKey {
        case id, name, type, imageUrl, connected
        case fullName = "full_name"
        case displayName = "display_name"
        case deviceTypeName = "deviceTypeName"
        case productId = "product_id"
        case configurationMetadata = "configuration_metadata"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        fullName = (try? container.decode(String.self, forKey: .fullName)) ?? ""
        deviceTypeName = (try? container.decode(String.self, forKey: .deviceTypeName)) ?? ""
        displayName = (try? container.decode(String.self, forKey: .displayName)) ?? fullName
        type = (try? container.decode(Int.self, forKey: .type)) ?? 0
        productId = (try? container.decode(Int.self, forKey: .productId)) ?? 0
        connected = (try? container.decode(FlexibleBool.self, forKey: .connected)) ?? FlexibleBool(false)
        imageUrl = (try? container.decodeIfPresent(String.self, forKey: .imageUrl)) ?? nil
        configurationMetadata =
            (try? container.decodeIfPresent([ConfigurationMetadata].self, forKey: .configurationMetadata)) ?? nil
    }

    var category: DeviceCategory { DeviceCategory(deviceTypeName: deviceTypeName) }

    var isMouse: Bool { category == .mouse }

    /// Prefer the short display name, fall back to the marketing name.
    var localizedName: String {
        let candidate = displayName.isEmpty ? fullName : displayName
        return candidate.isEmpty ? name : candidate
    }
}

/// Row of `configuration_metadata` — a cheap config index embedded in the device
/// payload, so the sidebar can show names without a second round trip.
struct ConfigurationMetadata: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let name: String
    let deviceId: Int
    let lastDeployed: FlexibleBool
    let active: FlexibleBool

    enum CodingKeys: String, CodingKey {
        case id, name, active
        case deviceId = "device_id"
        case lastDeployed = "last_deployed"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        deviceId = (try? container.decode(Int.self, forKey: .deviceId)) ?? 0
        lastDeployed = (try? container.decode(FlexibleBool.self, forKey: .lastDeployed)) ?? FlexibleBool(false)
        active = (try? container.decode(FlexibleBool.self, forKey: .active)) ?? FlexibleBool(false)
    }
}

struct DevicesResponse: Decodable, Sendable {
    let devices: [Device]
}
