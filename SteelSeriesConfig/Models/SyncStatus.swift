import Foundation

/// Response of `GET /device/{id}/isSyncAndSynced`.
///
/// Tells us whether the active configuration matches what the hardware is actually
/// running — the read-only check used after every restore or save, so we never have
/// to deploy to find out whether a write was right.
struct SyncStatus: Codable, Equatable, Sendable {
    let deviceId: Int
    let syncConfigId: String
    let isSync: FlexibleBool
    let isSynced: FlexibleBool

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case syncConfigId = "sync_config_id"
        case isSync = "is_sync"
        case isSynced = "is_synced"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceId = (try? container.decode(Int.self, forKey: .deviceId)) ?? 0
        syncConfigId = (try? container.decode(String.self, forKey: .syncConfigId)) ?? ""
        isSync = (try? container.decode(FlexibleBool.self, forKey: .isSync)) ?? FlexibleBool(false)
        isSynced = (try? container.decode(FlexibleBool.self, forKey: .isSynced)) ?? FlexibleBool(false)
    }
}

struct SyncEnvelope: Decodable, Sendable {
    let isSyncAndSyncedDevice: SyncStatus

    enum CodingKeys: String, CodingKey {
        case isSyncAndSyncedDevice = "is_sync_and_synced_device"
    }
}
