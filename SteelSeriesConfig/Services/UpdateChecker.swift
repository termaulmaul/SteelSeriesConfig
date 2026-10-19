import AppKit
import Foundation
import Observation

/// Finds, downloads and verifies the newest published build in the background, then
/// installs it when the user asks. Nothing on disk is replaced until that confirmation,
/// and nothing is replaced while a save is in flight or edits have not been saved.
@MainActor
@Observable
final class UpdateChecker {

    static let shared = UpdateChecker()

    /// Repository whose `build-<n>` releases are the update source.
    static let repository = "termaulmaul/SteelSeriesConfig"
    static let checkInterval: Duration = .seconds(6 * 60 * 60)

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case downloading(build: Int)
        case ready(build: Int)
        case failed(String)
    }

    enum UpdateError: LocalizedError {
        case http(Int)
        case integrity
        case invalidBundle
        case toolFailed(tool: String, output: String)
        case notWritable(String)
        case blocked(String)

        var errorDescription: String? {
            switch self {
            case .http(let code):
                return "GitHub responded with HTTP \(code)."
            case .integrity:
                return "The download does not match its published checksum."
            case .invalidBundle:
                return "The downloaded app is not the build that was published."
            case .toolFailed(let tool, let output):
                return "\(tool) failed: \(output)"
            case .notWritable(let path):
                return "Cannot write to \(path). Move the app to a folder you own, or download the release by hand."
            case .blocked(let reason):
                return reason
            }
        }
    }

    private(set) var state: State = .idle
    /// The verified build on disk, waiting for the user to install it.
    private(set) var readyBuild: Int?

    private var stagedAppURL: URL?
    private var schedule: Task<Void, Never>?
    private let store: ConfigurationStore

    private init(store: ConfigurationStore = .shared) {
        self.store = store
    }

    static var installedBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    static var installedDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return "\(version) (build \(installedBuild))"
    }

    /// Why installing is not possible right now, or `nil` when it is.
    var installBlockReason: String? {
        if store.isBusy || store.isLiveApplying {
            return "Wait for the current save to finish."
        }
        if store.isDirty {
            return "Save or discard your edits first."
        }
        return nil
    }

    var isWorking: Bool {
        switch state {
        case .checking, .downloading:
            return true
        default:
            return false
        }
    }

    /// A check shortly after launch, then one every few hours.
    func start() {
        guard schedule == nil else { return }
        schedule = Task {
            try? await Task.sleep(for: .seconds(15))
            while !Task.isCancelled {
                await checkForUpdates()
                try? await Task.sleep(for: Self.checkInterval)
            }
        }
    }

    /// Looks for a newer build and downloads it. Failures stay in `state`; the next
    /// scheduled check retries, which is safe because nothing outside this Mac changes.
    func checkForUpdates() async {
        guard !isWorking else { return }
        state = .checking

        do {
            guard let release = try await Self.fetchLatestRelease(),
                  let offer = ReleaseManifest.offer(for: release, installedBuild: Self.installedBuild)
            else {
                state = settledState
                return
            }

            if let readyBuild, readyBuild >= offer.build {
                state = settledState
                return
            }

            state = .downloading(build: offer.build)
            readyBuild = nil
            stagedAppURL = nil

            let app = try await Self.download(offer)
            readyBuild = offer.build
            stagedAppURL = app
            state = .ready(build: offer.build)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Replaces the running app with the verified build and relaunches it. The old app
    /// stays in place until the new copy has landed.
    func install() {
        do {
            try installStagedBuild()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private var settledState: State {
        readyBuild.map { .ready(build: $0) } ?? .upToDate
    }

    private func installStagedBuild() throws {
        guard let stagedAppURL else { return }
        if let reason = installBlockReason {
            throw UpdateError.blocked(reason)
        }

        let destination = Bundle.main.bundleURL
        let parent = destination.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw UpdateError.notWritable(parent.path)
        }

        let script = Self.updatesRoot.appendingPathComponent("install-update.sh")
        try Self.installScript.write(to: script, atomically: true, encoding: .utf8)
        let log = Self.updatesRoot.appendingPathComponent("install.log")

        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = [
            script.path,
            String(ProcessInfo.processInfo.processIdentifier),
            destination.path,
            stagedAppURL.path,
            log.path,
        ]
        try helper.run()
        NSApp.terminate(nil)
    }

    private static func fetchLatestRelease() async throws -> ReleaseManifest.Release? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SteelSeriesConfig/\(installedBuild)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }  // no release published yet
        guard status == 200 else { throw UpdateError.http(status) }
        return try JSONDecoder().decode(ReleaseManifest.Release.self, from: data)
    }

    private static func download(_ offer: ReleaseManifest.Offer) async throws -> URL {
        let folder = try prepareStagingFolder(build: offer.build)
        let dmgFile = folder.appendingPathComponent(offer.dmgName)

        let (downloaded, dmgResponse) = try await URLSession.shared.download(from: offer.dmgURL)
        try requireOK(dmgResponse)
        try FileManager.default.moveItem(at: downloaded, to: dmgFile)

        let (checksum, checksumResponse) = try await URLSession.shared.data(from: offer.checksumURL)
        try requireOK(checksumResponse)

        return try await Task.detached {
            try verifyAndCopyOut(dmg: dmgFile, checksum: checksum, offer: offer)
        }.value
    }

    private static func requireOK(_ response: URLResponse) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateError.http(status) }
    }

    /// Only one staged build is kept, so any earlier attempt is cleared first.
    nonisolated private static func prepareStagingFolder(build: Int) throws -> URL {
        let folder = updatesRoot.appendingPathComponent("build-\(build)", isDirectory: true)
        try? FileManager.default.removeItem(at: updatesRoot)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Checks the image against its published checksum, then copies the app out of it.
    /// The image is mounted read-only and detached again before this returns.
    nonisolated private static func verifyAndCopyOut(
        dmg: URL,
        checksum: Data,
        offer: ReleaseManifest.Offer
    ) throws -> URL {
        let published = ReleaseManifest.checksum(
            fromFileText: String(decoding: checksum, as: UTF8.self),
            fileName: offer.dmgName
        )
        let actual = ReleaseManifest.sha256Hex(of: try Data(contentsOf: dmg))
        guard let published, published == actual else { throw UpdateError.integrity }

        let folder = dmg.deletingLastPathComponent()
        let mountPoint = folder.appendingPathComponent("mounted", isDirectory: true)
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", [
            "attach", "-readonly", "-nobrowse", "-noautoopen",
            "-mountpoint", mountPoint.path, dmg.path,
        ])
        defer { try? run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"]) }

        let mounted = mountPoint.appendingPathComponent(ReleaseManifest.appName, isDirectory: true)
        guard let bundle = Bundle(url: mounted),
              ReleaseManifest.accepts(
                  bundleIdentifier: bundle.bundleIdentifier,
                  build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
                  expected: offer.build
              )
        else { throw UpdateError.invalidBundle }

        // Copy out before verifying: the signature is checked on the bundle that will be
        // installed, and the image is detached as soon as this function returns.
        let app = folder.appendingPathComponent(ReleaseManifest.appName, isDirectory: true)
        try run("/usr/bin/ditto", [mounted.path, app.path])
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        return app
    }

    /// Runs a tool to completion and throws with its output if it exits non-zero.
    nonisolated private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()

        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.toolFailed(tool: tool, output: text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    nonisolated private static var updatesRoot: URL {
        BackupStore.applicationSupportURL.appendingPathComponent("SteelSeriesConfig/updates", isDirectory: true)
    }

    /// Runs after this process has exited. The old bundle is only removed once the new
    /// one is in place, so a failed copy leaves a working app behind.
    private static let installScript = #"""
    #!/bin/sh
    # Arguments: <pid> <installed app> <verified new app> <log file>
    exec >>"$4" 2>&1
    pid="$1"; dest="$2"; src="$3"
    echo "$(date): waiting for pid $pid"
    while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
    backup="$dest.previous"
    rm -rf "$backup"
    if ! mv "$dest" "$backup"; then
      echo "could not move $dest aside, keeping it"
      open "$dest"
      exit 1
    fi
    if /usr/bin/ditto "$src" "$dest"; then
      /usr/bin/xattr -dr com.apple.quarantine "$dest"
      rm -rf "$backup"
      echo "$(date): installed"
    else
      echo "$(date): copy failed, restoring previous app"
      rm -rf "$dest"
      mv "$backup" "$dest"
    fi
    open "$dest"
    """#
}
