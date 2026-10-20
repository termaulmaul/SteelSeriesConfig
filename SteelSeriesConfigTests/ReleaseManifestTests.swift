import XCTest
@testable import SteelSeriesConfig

final class ReleaseManifestTests: XCTestCase {

    private let base = "https://github.com/termaulmaul/SteelSeriesConfig/releases/download/build-12/"

    private func release(
        tag: String = "build-12",
        draft: Bool = false,
        prerelease: Bool = false,
        assets: [String] = ["SteelSeriesConfig-0.1.0-build.12.dmg", "SteelSeriesConfig-0.1.0-build.12.dmg.sha256"]
    ) -> ReleaseManifest.Release {
        ReleaseManifest.Release(
            tagName: tag,
            draft: draft,
            prerelease: prerelease,
            assets: assets.map { name in
                ReleaseManifest.Release.Asset(name: name, browserDownloadURL: URL(string: base + name)!)
            }
        )
    }

    func testBuildNumberComesFromTag() {
        XCTAssertEqual(ReleaseManifest.buildNumber(fromTag: "build-42"), 42)
        XCTAssertNil(ReleaseManifest.buildNumber(fromTag: "v0.1.0"))
        XCTAssertNil(ReleaseManifest.buildNumber(fromTag: "build-x"))
    }

    func testOfferIsReturnedForNewerCompleteBuild() {
        let offer = ReleaseManifest.offer(for: release(), installedBuild: 11)

        XCTAssertEqual(offer?.build, 12)
        XCTAssertEqual(offer?.dmgName, "SteelSeriesConfig-0.1.0-build.12.dmg")
        XCTAssertEqual(offer?.checksumName, "SteelSeriesConfig-0.1.0-build.12.dmg.sha256")
    }

    func testNoOfferForSameOrOlderBuild() {
        XCTAssertNil(ReleaseManifest.offer(for: release(), installedBuild: 12))
        XCTAssertNil(ReleaseManifest.offer(for: release(), installedBuild: 13))
    }

    func testNoOfferForDraftOrPrerelease() {
        XCTAssertNil(ReleaseManifest.offer(for: release(draft: true), installedBuild: 1))
        XCTAssertNil(ReleaseManifest.offer(for: release(prerelease: true), installedBuild: 1))
    }

    func testNoOfferWhenAssetIsMissing() {
        XCTAssertNil(ReleaseManifest.offer(for: release(assets: ["SteelSeriesConfig-0.1.0-build.12.dmg"]), installedBuild: 1))
        XCTAssertNil(ReleaseManifest.offer(for: release(assets: ["SteelSeriesConfig-0.1.0-build.12.dmg.sha256"]), installedBuild: 1))
    }

    /// The whole point of the suffix match: a newer version string in the name still
    /// resolves for the build the tag names, and a different build never does.
    func testOfferMatchesByBuildSuffixRegardlessOfVersion() {
        let assets = ["SteelSeriesConfig-0.2.0-build.12.dmg", "SteelSeriesConfig-0.2.0-build.12.dmg.sha256"]
        XCTAssertEqual(ReleaseManifest.offer(for: release(assets: assets), installedBuild: 11)?.build, 12)

        let wrongBuild = ["SteelSeriesConfig-0.1.0-build.13.dmg", "SteelSeriesConfig-0.1.0-build.13.dmg.sha256"]
        XCTAssertNil(ReleaseManifest.offer(for: release(assets: wrongBuild), installedBuild: 1))
    }

    func testDmgNameAndChecksumNameRoundTrip() {
        let dmg = ReleaseManifest.dmgName(version: "0.1.0", build: 4)
        XCTAssertEqual(dmg, "SteelSeriesConfig-0.1.0-build.4.dmg")
        XCTAssertTrue(ReleaseManifest.isDmg(dmg, forBuild: 4))
        XCTAssertFalse(ReleaseManifest.isDmg(dmg, forBuild: 14))
        XCTAssertEqual(ReleaseManifest.checksumName(forDmg: dmg), "SteelSeriesConfig-0.1.0-build.4.dmg.sha256")
    }

    func testNoOfferFromUntrustedHost() {
        let foreign = ReleaseManifest.Release(
            tagName: "build-12",
            draft: false,
            prerelease: false,
            assets: [
                .init(name: "SteelSeriesConfig-0.1.0-build.12.dmg", browserDownloadURL: URL(string: "https://example.com/a.dmg")!),
                .init(name: "SteelSeriesConfig-0.1.0-build.12.dmg.sha256", browserDownloadURL: URL(string: "https://example.com/a.sha256")!),
            ]
        )
        XCTAssertNil(ReleaseManifest.offer(for: foreign, installedBuild: 1))
    }

    func testOnlyHttpsGitHubHostsAreTrusted() {
        XCTAssertTrue(ReleaseManifest.isTrusted(URL(string: "https://github.com/a/b")!))
        XCTAssertTrue(ReleaseManifest.isTrusted(URL(string: "https://objects.githubusercontent.com/x")!))
        XCTAssertFalse(ReleaseManifest.isTrusted(URL(string: "http://github.com/a/b")!))
        XCTAssertFalse(ReleaseManifest.isTrusted(URL(string: "https://github.com.evil.io/a")!))
        XCTAssertFalse(ReleaseManifest.isTrusted(URL(string: "https://evil-github.com/a")!))
    }

    func testChecksumIsReadForNamedFile() {
        let text = """
        ABC123  SteelSeriesConfig-0.1.0-build.11.dmg
        def456 *SteelSeriesConfig-0.1.0-build.12.dmg
        """

        XCTAssertEqual(ReleaseManifest.checksum(fromFileText: text, fileName: "SteelSeriesConfig-0.1.0-build.12.dmg"), "def456")
        XCTAssertEqual(ReleaseManifest.checksum(fromFileText: text, fileName: "SteelSeriesConfig-0.1.0-build.11.dmg"), "abc123")
        XCTAssertNil(ReleaseManifest.checksum(fromFileText: text, fileName: "SteelSeriesConfig-0.1.0-build.13.dmg"))
    }

    func testSha256MatchesKnownVector() {
        XCTAssertEqual(
            ReleaseManifest.sha256Hex(of: Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testBundleMustMatchIdentifierAndBuild() {
        XCTAssertTrue(ReleaseManifest.accepts(bundleIdentifier: "com.maul.steelseriesconfig", build: "12", expected: 12))
        XCTAssertFalse(ReleaseManifest.accepts(bundleIdentifier: "com.maul.steelseriesconfig", build: "11", expected: 12))
        XCTAssertFalse(ReleaseManifest.accepts(bundleIdentifier: "com.other.app", build: "12", expected: 12))
        XCTAssertFalse(ReleaseManifest.accepts(bundleIdentifier: nil, build: nil, expected: 12))
    }

    func testDecodesGitHubReleasePayload() throws {
        let json = """
        {
          "tag_name": "build-12",
          "draft": false,
          "prerelease": false,
          "assets": [
            {"name": "SteelSeriesConfig-0.1.0-build.12.dmg", "browser_download_url": "https://github.com/a/b/releases/download/build-12/SteelSeriesConfig-0.1.0-build.12.dmg"}
          ]
        }
        """

        let decoded = try JSONDecoder().decode(ReleaseManifest.Release.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.tagName, "build-12")
        XCTAssertEqual(decoded.assets.first?.name, "SteelSeriesConfig-0.1.0-build.12.dmg")
    }
}
