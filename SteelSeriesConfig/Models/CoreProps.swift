import Foundation

/// Contents of `/Library/Application Support/SteelSeries GG/coreProps.json`.
///
/// This file is the whole "how do I find the engine" contract. It is written by the
/// SteelSeries GG core on launch, so reading it is both the login-free discovery
/// mechanism and the way to survive a non-default port.
struct CoreProps: Codable, Equatable, Sendable {
    /// Plain-text host:port for the engine API. `https` despite the "encrypted"
    /// name — the value itself is not encrypted, it just names the TLS endpoint.
    let encryptedAddress: String?
    /// Host:port for the GG (loadout/cloud) API. Requires a bearer token that only
    /// the Electron client receives, so this app never talks to it.
    let ggEncryptedAddress: String?
    /// Legacy plain-HTTP endpoint; mostly 404s in current builds.
    let address: String?

    /// Engine base URL. TLS with a self-signed `O=SteelSeries ApS` certificate —
    /// trust is granted narrowly in `LocalhostTrustDelegate`.
    var engineURL: URL? { CoreProps.baseURL(from: encryptedAddress) }

    static func baseURL(from hostAndPort: String?) -> URL? {
        guard let hostAndPort, !hostAndPort.isEmpty else { return nil }
        return URL(string: "https://\(hostAndPort)")
    }
}
