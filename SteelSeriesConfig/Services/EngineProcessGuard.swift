import Foundation
import AppKit

/// Handles the case where the SteelSeries GG core is not running.
///
/// `coreProps.json` is written on core launch but survives a quit, so a stale file can
/// point at a port nothing is listening on. Probing the real endpoint — rather than
/// trusting the file — is what keeps the app's status line honest.
@MainActor
enum EngineProcessGuard {
    static let installCandidates = [
        "/Applications/SteelSeries GG/SteelSeries GG.app",
        "/Applications/SteelSeriesGG.app",
    ]

    static var installedAppURL: URL? {
        installCandidates
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// A live round trip to the engine, not a port-open check — the engine can be
    /// listening before its routes are ready.
    static func engineReachable(using client: EngineClient) async -> Bool {
        do {
            _ = try await client.devices()
            return true
        } catch {
            return false
        }
    }

    static func launchSteelSeriesGG() throws -> URL {
        guard let url = installedAppURL else {
            throw LaunchError.notInstalled
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                NSLog("SteelSeriesConfig: failed to launch GG core: \(error.localizedDescription)")
            }
        }
        return url
    }

    enum LaunchError: Error, LocalizedError {
        case notInstalled
        var errorDescription: String? {
            switch self {
            case .notInstalled:
                return "SteelSeries GG is not installed in /Applications."
            }
        }
    }
}
