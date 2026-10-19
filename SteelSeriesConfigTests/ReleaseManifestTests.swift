import XCTest
@testable import SteelSeriesConfig

final class ReleaseManifestTests: XCTestCase {

    private let base = "https://github.com/termaulmaul/SteelSeriesConfig/releases/download/build-12/"

    private func release(
        tag: String = "build-12",
        draft: Bool = false,
        prerelease: Bool = false,
        assets: [String] = ["SteelSeriesConfig-12.zip", "SteelSeriesConfig-12.zip.sha256"]
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
        XCTAssertEqual(offer?.zipName, "SteelSeriesConfig-12.zip")
        XCTAssertEqual(offer?.checksumName, "SteelSeriesConfig-12.zip.sha256")
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
        XCTAssertNil(ReleaseManifest.offer(for: release(assets: ["SteelSeriesConfig-12.zip"]), installedBuild: 1))
        XCTAssertNil(ReleaseManifest.offer(for: release(assets: ["SteelSeriesConfig-12.zip.sha256"]), installedBuild: 1))
    }

    func testNoOfferFromUntrustedHost() {
        let foreign = ReleaseManifest.Release(
            tagName: "build-12",
            draft: false,
            prerelease: false,
            assets: [
                .init(name: "SteelSeriesConfig-12.zip", browserDownloadURL: URL(string: "https://example.com/a.zip")!),
                .init(name: "SteelSeriesConfig-12.zip.sha256", browserDownloadURL: URL(string: "https://example.com/a.sha256")!),
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
        ABC123  SteelSeriesConfig-11.zip
        def456 *SteelSeriesConfig-12.zip
        """

        XCTAssertEqual(ReleaseManifest.checksum(fromFileText: text, fileName: "SteelSeriesConfig-12.zip"), "def456")
        XCTAssertEqual(ReleaseManifest.checksum(fromFileText: text, fileName: "SteelSeriesConfig-11.zip"), "abc123")
        XCTAssertNil(ReleaseManifest.checksum(fromFileText: text, fileName: "SteelSeriesConfig-13.zip"))
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
            {"name": "SteelSeriesConfig-12.zip", "browser_download_url": "https://github.com/a/b/releases/download/build-12/SteelSeriesConfig-12.zip"}
          ]
        }
        """

        let decoded = try JSONDecoder().decode(ReleaseManifest.Release.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.tagName, "build-12")
        XCTAssertEqual(decoded.assets.first?.name, "SteelSeriesConfig-12.zip")
    }
}
