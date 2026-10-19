import Foundation

/// HTTP client for the SteelSeries engine's local API.
///
/// Scope of this client, chosen deliberately:
///
/// - **Engine only** (the port in `coreProps.json`'s `encryptedAddress`). The GG
///   loadout API on 6327 requires a bearer token that only the bundled Electron
///   client ever receives, and everything this app needs — devices, configurations,
///   writes — is reachable without it.
/// - **Read-modify-write only.** There is no create, delete, or partial-update path;
///   `putConfiguration` is the single mutation and it always carries a complete body.
/// - **No retries on writes.** A retried non-idempotent request is exactly how you end
///   up deploying twice; failures surface to the caller instead.
///
/// The engine's own HTTP verbs are non-obvious: the GG client maps `submit` → POST,
/// `update` → PUT, `fetch` → GET. Those mappings are reproduced below.
actor EngineClient {
    enum ClientError: Error, LocalizedError {
        case invalidPath(String)
        case transport(String)
        case unexpectedStatus(Int, String)
        case malformedResponse(String)

        var errorDescription: String? {
            switch self {
            case .invalidPath(let path):
                return "Refusing to build a URL for '\(path)'."
            case .transport(let detail):
                return "Could not reach the SteelSeries engine: \(detail)"
            case .unexpectedStatus(let code, let detail):
                return "Engine returned HTTP \(code): \(detail)"
            case .malformedResponse(let detail):
                return "Engine response was not in the expected shape: \(detail)"
            }
        }
    }

    private let baseURL: URL
    private let session: URLSession

    init(engineURL: URL) {
        self.baseURL = engineURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 20
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(
            configuration: configuration,
            delegate: LocalhostTrustDelegate(engineURL: engineURL),
            delegateQueue: nil
        )
    }

    // MARK: - Transport

    private func url(for path: String) throws -> URL {
        // Endpoint segments we build are either literals or ids we received; this
        // rejects anything that could climb out of the API root before it is sent.
        guard !path.contains(".."), !path.contains("//") else {
            throw ClientError.invalidPath(path)
        }
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw ClientError.invalidPath(path)
        }
        return url
    }

    private func perform(
        _ method: String,
        _ path: String,
        body: Data?
    ) async throws -> Data {
        return try await send(method, url(for: path), body: body)
    }

    /// Executes a request against an already-built URL. Split out from `perform` because
    /// device artwork arrives as an absolute URL, which `url(for:)` would reject — it
    /// forbids `//`, and every scheme contains one.
    private func send(
        _ method: String,
        _ url: URL,
        body: Data?
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw ClientError.transport(error.localizedDescription)
        } catch {
            throw ClientError.transport(String(describing: error))
        }

        guard let http = response as? HTTPURLResponse else {
            throw ClientError.malformedResponse("Response was not HTTP.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(decoding: data.prefix(400), as: UTF8.self)
            throw ClientError.unexpectedStatus(http.statusCode, snippet)
        }
        return data
    }

    private func get<T: Decodable>(_ type: T.Type, _ path: String) async throws -> T {
        let data = try await perform("GET", path, body: nil)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ClientError.malformedResponse(String(describing: error))
        }
    }

    // MARK: - Reads

    func devices() async throws -> [Device] {
        try await get(DevicesResponse.self, "devices").devices
    }

    func configurations(deviceID: Int) async throws -> [DeviceConfiguration] {
        try await get(ConfigurationsResponse.self, "device/\(deviceID)/configurations").configurations
    }

    func configuration(id: String) async throws -> DeviceConfiguration {
        let response = try await get(ConfigurationResponse.self, "configuration/\(id)")
        return response.configuration
    }

    /// Read-only sync check: does the active configuration match the hardware.
    func syncStatus(deviceID: Int) async throws -> SyncStatus {
        let response = try await get(SyncEnvelope.self, "device/\(deviceID)/isSyncAndSynced")
        return response.isSyncAndSyncedDevice
    }

    /// Device artwork, served by the same self-signed endpoint as everything else.
    ///
    /// The response's `imageUrl` is absolute, so it is checked against the engine we
    /// discovered rather than passed through `url(for:)`: images come only from the
    /// engine itself, and anything else is refused so a stray URL in a response can
    /// never turn into an outbound request.
    func imageData(at absoluteURL: String) async throws -> Data {
        guard let url = URL(string: absoluteURL),
              url.scheme == baseURL.scheme,
              url.host == baseURL.host,
              url.port == baseURL.port
        else {
            throw ClientError.invalidPath(absoluteURL)
        }
        return try await send("GET", url, body: nil)
    }

    // MARK: - Device commands

    /// Run a read command against a device.
    ///
    /// The engine reaches device I/O through a single POST endpoint that takes the
    /// command as a *stringified* JSON document — the GG client gets there via its
    /// `submit` mapping. Only read commands are issued from here; the protocol's
    /// `writeCommand` / `writeCommandWithLightingPause` siblings are deliberately not
    /// implemented, because every write this app performs goes through
    /// `putConfiguration` or `liveDeploy`, where the safety policy applies.
    ///
    /// A `command_data` of `""` means the device did not answer — off, asleep, or out
    /// of range. That is returned as `.null`, not thrown, so callers can render
    /// "unknown" instead of treating a sleeping mouse as a failure.
    func deviceCommand(id: Int, command: [String: AnyJSONValue]) async throws -> AnyJSONValue {
        let commandDocument = try AnyJSONValue.object(command).compactString()
        let payload: [String: AnyJSONValue] = [
            "id": .int(id),
            "command": .string(commandDocument),
        ]
        let body = try JSONSerialization.data(
            withJSONObject: AnyJSONValue.object(payload).toJSONObject()
        )
        let data = try await perform("POST", "device/command", body: body)

        let envelope: DeviceCommandResponse
        do {
            envelope = try JSONDecoder().decode(DeviceCommandResponse.self, from: data)
        } catch {
            throw ClientError.malformedResponse(String(describing: error))
        }

        guard let raw = envelope.commandData, !raw.isEmpty else { return .null }
        return (try? AnyJSONValue.parse(raw)) ?? .null
    }

    // MARK: - Writes

    /// The single mutation this app performs: full replace of one configuration.
    ///
    /// Callers must have validated the body with `WriteSafetyPolicy` and taken a
    /// backup of the pre-write state. This type system cannot express that, so
    /// `ConfigurationStore.save()` is the only call site and the checks live there.
    func putConfiguration(_ configuration: DeviceConfiguration) async throws {
        let payload = AnyJSONValue.object(configuration.putBody())
        let body = try JSONSerialization.data(withJSONObject: payload.toJSONObject())
        _ = try await perform("PUT", "configuration/\(configuration.id)", body: body)
    }

    /// Pushes the configuration to the hardware. POST, matching the GG client's
    /// `submit` mapping — verified against the client bundle, but not exercised
    /// against this mouse (its configuration was already correct, so nothing needed
    /// deploying during development).
    func deploy(configurationID: String) async throws {
        let empty: [String: AnyJSONValue] = [:]
        let body = try JSONSerialization.data(withJSONObject: empty)
        _ = try await perform("POST", "configuration/\(configurationID)/deploy", body: body)
    }

    /// Apply a settings document to the device *without* committing a configuration
    /// revision. POST, matching the GG client's `submit` mapping.
    ///
    /// This is the endpoint the GG client fires while a slider is being dragged: the
    /// document reaches the hardware immediately, which is what makes a change visible
    /// on the mouse before anything is saved. It is not a substitute for
    /// `putConfiguration` — a live-applied change is not persisted as a revision, so
    /// `save()` still has to run for the change to survive a reconnect or a profile
    /// switch.
    ///
    /// Callers must have validated the document with `WriteSafetyPolicy` and produced
    /// it through ``MouseSettings/encodedStringForLiveDeploy()``, which drops the keys
    /// the engine refuses to live-apply.
    func liveDeploy(_ configuration: DeviceConfiguration, settings: String) async throws {
        var payload: [String: AnyJSONValue] = [
            "name": .string(configuration.name),
            "id": .string(configuration.id),
            "settings": .string(settings),
            "universal_triggers": configuration.universalTriggers,
        ]
        if let deviceId = configuration.deviceId {
            payload["device_id"] = .int(deviceId)
        }

        let body = try JSONSerialization.data(
            withJSONObject: AnyJSONValue.object(payload).toJSONObject()
        )
        _ = try await perform("POST", "configuration/liveDeploy", body: body)
    }

    func invalidate() {
        session.invalidateAndCancel()
    }
}

/// `POST device/command` replies with the device's own JSON as a *string* inside an
/// envelope, which is then re-parsed by the caller.
private struct DeviceCommandResponse: Decodable {
    let commandData: String?

    enum CodingKeys: String, CodingKey {
        case commandData = "command_data"
    }
}
