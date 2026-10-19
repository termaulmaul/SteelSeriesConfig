import Foundation

/// Automatic, local, pre-write backups of the engine's own configuration documents.
///
/// Every save re-reads the configuration first; that fresh read is what gets backed
/// up, so a backup always represents the state *immediately before* the write that
/// triggered it. No cloud, no login, no SteelSeries involvement.
enum BackupStore {
    static let backupDirectoryName = "SteelSeriesConfig/backups"

    /// Tests redirect this so they never read or write the real Application Support
    /// folder. Production code never sets it. `nonisolated(unsafe)` because it is only
    /// ever written from `@MainActor` test setUp code.
    nonisolated(unsafe) static var rootURLOverride: URL?

    static var applicationSupportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static var rootURL: URL {
        if let rootURLOverride { return rootURLOverride }
        return applicationSupportURL.appendingPathComponent(backupDirectoryName, isDirectory: true)
    }

    /// Retained backups per configuration. Configs are small (tens of KB), so this is
    /// generous enough to walk back through a bad evening of tuning.
    static let retentionCount = 25

    static func directory(for configurationID: String) -> URL {
        rootURL.appendingPathComponent(sanitize(configurationID), isDirectory: true)
    }

    static func sanitize(_ configurationID: String) -> String {
        let filtered = String(configurationID.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
                ? character
                : Character("_")
        })
        return filtered.isEmpty ? "unknown" : filtered
    }

    /// Write a backup. Returns the file URL, or `nil` if the configuration has no id
    /// (nothing meaningful to name the file after).
    ///
    /// A failure here is reported to the caller but never blocks the write itself:
    /// the engine's own database still holds the state, and refusing a save because a
    /// convenience copy failed would push users toward editing outside the app.
    @discardableResult
    static func save(configuration: DeviceConfiguration) throws -> URL? {
        guard !configuration.id.isEmpty else { return nil }

        let folder = directory(for: configuration.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let payload = try encoder.encode(configuration)

        let stamp = Self.timestamp()
        let url = folder.appendingPathComponent("\(stamp).json")
        try payload.write(to: url, options: .atomic)

        prune(configurationID: configuration.id)
        return url
    }

    static func list(configurationID: String) -> [URL] {
        let folder = directory(for: configurationID)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func read(_ url: URL) throws -> DeviceConfiguration {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(DeviceConfiguration.self, from: data)
    }

    /// Delete all but the newest `keep` backups. Returns the removed file URLs.
    @discardableResult
    static func prune(configurationID: String, keep: Int = retentionCount) -> [URL] {
        let files = list(configurationID: configurationID)
        guard files.count > keep else { return [] }
        let doomed = Array(files.dropFirst(keep))
        for url in doomed {
            try? FileManager.default.removeItem(at: url)
        }
        return doomed
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
