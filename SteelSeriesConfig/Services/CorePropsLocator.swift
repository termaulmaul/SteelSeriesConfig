import Foundation

/// Finds and parses the engine's `coreProps.json`.
///
/// This is the entire discovery step of a login-free client: the GG core writes the
/// file on launch, so reading it gives us the current engine port without hardcoding
/// one and without ever touching the GG API's bearer token.
enum CorePropsLocator {
    static let defaultPath =
        "/Library/Application Support/SteelSeries GG/coreProps.json"

    /// Last-resort endpoint for when the file is absent (core starting up, or a
    /// portable install writing elsewhere). The default port has been stable across
    /// current GG builds, but it is still only a fallback — a mismatch fails loudly
    /// in `ConfigurationStore.bootstrap()` rather than being silently assumed.
    static let fallbackHostAndPort = "127.0.0.1:50530"

    static func locate(path: String = CorePropsLocator.defaultPath) -> CoreProps? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return parse(data)
    }

    static func parse(_ data: Data) -> CoreProps? {
        try? JSONDecoder().decode(CoreProps.self, from: data)
    }

    static func parse(_ raw: String) -> CoreProps? {
        parse(Data(raw.utf8))
    }

    /// Engine base URL, preferring the discovered file and falling back to the known
    /// default port. Returns `nil` only if neither yields a usable URL.
    static func resolveEngineURL(path: String = CorePropsLocator.defaultPath) -> URL? {
        if let url = locate(path: path)?.engineURL { return url }
        return CoreProps.baseURL(from: fallbackHostAndPort)
    }
}
