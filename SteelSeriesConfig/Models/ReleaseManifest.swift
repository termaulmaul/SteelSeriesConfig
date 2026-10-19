import CryptoKit
import Foundation

/// Rules for the in-app updater, kept free of networking and UI so they can be tested
/// on their own: which published build is newer, which assets belong to it, and whether
/// a download can be trusted.
///
/// Builds are GitHub releases tagged `build-<n>`, where `<n>` is the CI run number that
/// is also written into `CFBundleVersion`.
enum ReleaseManifest {

    static let tagPrefix = "build-"
    static let bundleIdentifier = "com.maul.steelseriesconfig"
    static let appName = "SteelSeriesConfig.app"

    struct Release: Decodable, Equatable {
        let tagName: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        struct Asset: Decodable, Equatable {
            let name: String
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case draft
            case prerelease
            case assets
        }
    }

    /// A build confirmed to be newer and complete, ready to download.
    struct Offer: Equatable {
        let build: Int
        let dmgName: String
        let dmgURL: URL
        let checksumName: String
        let checksumURL: URL
    }

    static func buildNumber(fromTag tag: String) -> Int? {
        guard tag.hasPrefix(tagPrefix) else { return nil }
        return Int(tag.dropFirst(tagPrefix.count))
    }

    static func dmgName(build: Int) -> String {
        "SteelSeriesConfig-\(build).dmg"
    }

    static func checksumName(build: Int) -> String {
        dmgName(build: build) + ".sha256"
    }

    /// The download for `release`, but only if it is a published, complete build
    /// strictly newer than `installedBuild`.
    static func offer(for release: Release, installedBuild: Int) -> Offer? {
        guard !release.draft,
              !release.prerelease,
              let build = buildNumber(fromTag: release.tagName),
              build > installedBuild
        else { return nil }

        let dmgFile = dmgName(build: build)
        let checksumFile = checksumName(build: build)
        guard let dmg = release.assets.first(where: { $0.name == dmgFile }),
              let checksum = release.assets.first(where: { $0.name == checksumFile }),
              isTrusted(dmg.browserDownloadURL),
              isTrusted(checksum.browserDownloadURL)
        else { return nil }

        return Offer(
            build: build,
            dmgName: dmgFile,
            dmgURL: dmg.browserDownloadURL,
            checksumName: checksumFile,
            checksumURL: checksum.browserDownloadURL
        )
    }

    /// HTTPS on GitHub's own hosts only. Release assets redirect from github.com to
    /// githubusercontent.com, so both are accepted and nothing else is.
    static func isTrusted(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "github.com"
            || host.hasSuffix(".github.com")
            || host.hasSuffix(".githubusercontent.com")
    }

    /// Reads `shasum -a 256` output: `<hex>  <name>`, or `<hex> *<name>` in binary mode.
    static func checksum(fromFileText text: String, fileName: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }

            var name = parts[1].trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("*") { name.removeFirst() }
            if name == fileName { return parts[0].lowercased() }
        }
        return nil
    }

    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Whether an unpacked app is the bundle and build this release promised.
    static func accepts(bundleIdentifier identifier: String?, build: String?, expected: Int) -> Bool {
        identifier == bundleIdentifier && build == String(expected)
    }
}
