import Foundation

/// Pre-flight checks every configuration write must pass.
///
/// The engine's `PUT /configuration/{id}` is replace-not-patch: fields missing from
/// the body are blanked, and an empty `settings` string wipes the device's config.
/// That failure mode is silent — the request still returns 200 — so the only place to
/// stop it is before the request is sent.
enum WriteSafetyPolicy {
    enum Violation: Error, LocalizedError, Equatable {
        case missingID
        case emptyName
        case emptySettings
        case settingsNotAnObject
        case invalidUndeployedSettings
        case suspiciousShrinkage(before: Int, after: Int)

        var errorDescription: String? {
            switch self {
            case .missingID:
                return "Configuration has no id; refusing to write an untargeted request."
            case .emptyName:
                return "Configuration name is empty."
            case .emptySettings:
                return "Settings document is empty — writing it would erase the device configuration."
            case .settingsNotAnObject:
                return "Settings document is not a JSON object — writing it would corrupt the device configuration."
            case .invalidUndeployedSettings:
                return "Undeployed settings document is not valid JSON."
            case .suspiciousShrinkage(let before, let after):
                return """
                Settings would shrink from \(before) to \(after) bytes. \
                This is the signature of an accidental wipe, so it is blocked. \
                If this is genuinely intended, edit the document rather than clearing it.
                """
            }
        }
    }

    /// Threshold below which a shrink is treated as a wipe rather than an edit.
    /// Real tuning edits move the document by kilobytes of *structure* at most;
    /// losing more than 90% of a non-trivial document has no legitimate cause.
    static let shrinkageRatio = 0.10
    static let shrinkageFloorBytes = 1_000

    static func validate(_ configuration: DeviceConfiguration) throws {
        guard !configuration.id.isEmpty else { throw Violation.missingID }
        guard !configuration.name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw Violation.emptyName
        }
        try validate(settings: configuration.settings)
        try validateUndeployed(configuration.undeployedSettings)
    }

    static func validate(settings: String) throws {
        guard !settings.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Violation.emptySettings
        }
        guard let value = try? AnyJSONValue.parse(settings),
              let object = value.objectValue,
              !object.isEmpty
        else {
            throw Violation.settingsNotAnObject
        }
    }

    /// An empty or absent undeployed document is legitimate (nothing pending), so this
    /// only rejects *malformed* content — never a document for being small.
    static func validateUndeployed(_ raw: String) throws {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        guard (try? AnyJSONValue.parse(trimmed)) != nil else {
            throw Violation.invalidUndeployedSettings
        }
    }

    /// Full check including the wipe heuristic against the freshly-read document.
    ///
    /// - Parameters:
    ///   - configuration: the body about to be sent.
    ///   - previous: the configuration as last read from the engine, used only for the
    ///     size comparison. Pass `nil` on first write (there is nothing to compare).
    static func validate(
        _ configuration: DeviceConfiguration,
        previous: DeviceConfiguration?
    ) throws {
        try validate(configuration)

        guard let previous else { return }
        let before = previous.settings.utf8.count
        let after = configuration.settings.utf8.count
        guard before >= shrinkageFloorBytes else { return }

        if Double(after) < Double(before) * shrinkageRatio {
            throw Violation.suspiciousShrinkage(before: before, after: after)
        }
    }
}
