import XCTest
@testable import SteelSeriesConfig

final class BackupStoreTests: XCTestCase {

    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SteelSeriesConfigTests-\(UUID().uuidString)", isDirectory: true)
        BackupStore.rootURLOverride = tempRoot.appendingPathComponent("backups", isDirectory: true)
    }

    override func tearDownWithError() throws {
        BackupStore.rootURLOverride = nil
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    func testSaveWritesReadableFile() throws {
        let config = Fixture.makeConfiguration()

        let url = try XCTUnwrap(try BackupStore.save(configuration: config))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let restored = try BackupStore.read(url)
        XCTAssertEqual(restored.id, config.id)
        XCTAssertEqual(restored.name, config.name)
        XCTAssertEqual(restored.settings, config.settings)
    }

    func testSaveReturnsNilForInvalidConfiguration() {
        var config = Fixture.makeConfiguration()
        config.id = ""

        XCTAssertNil(try BackupStore.save(configuration: config))
    }

    func testListIsSortedNewestFirst() throws {
        let id = "backup-list-test"

        let first = try BackupStore.save(configuration: Fixture.makeConfiguration(id: id))
        Thread.sleep(forTimeInterval: 1.1)
        let second = try BackupStore.save(configuration: Fixture.makeConfiguration(id: id))

        let listed = BackupStore.list(configurationID: id)
        XCTAssertEqual(listed.count, 2)
        // Compare by name: `temporaryDirectory` resolves through the `/var` symlink,
        // so the same file can legitimately compare unequal as a full URL.
        XCTAssertEqual(listed.first?.lastPathComponent, second?.lastPathComponent)
        XCTAssertEqual(listed.last?.lastPathComponent, first?.lastPathComponent)
    }

    func testListOnlyReturnsRequestedConfiguration() throws {
        _ = try BackupStore.save(configuration: Fixture.makeConfiguration(id: "alpha"))
        _ = try BackupStore.save(configuration: Fixture.makeConfiguration(id: "beta"))

        let listed = BackupStore.list(configurationID: "alpha")
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed[0].deletingLastPathComponent().lastPathComponent, "alpha")
    }

    func testPruneKeepsMostRecent() throws {
        let id = "prune-test"
        var saved: [URL] = []
        for _ in 0..<8 {
            saved.append(try XCTUnwrap(try BackupStore.save(configuration: Fixture.makeConfiguration(id: id))))
            Thread.sleep(forTimeInterval: 1.05)
        }

        let removed = BackupStore.prune(configurationID: id, keep: 3)

        XCTAssertEqual(removed.count, 5)
        XCTAssertEqual(BackupStore.list(configurationID: id).count, 3)
        XCTAssertEqual(BackupStore.list(configurationID: id).first?.lastPathComponent, saved.last?.lastPathComponent)
    }

    func testPruneReturnsEmptyWhenNothingToDelete() throws {
        let url = try XCTUnwrap(try BackupStore.save(configuration: Fixture.makeConfiguration(id: "keep")))
        _ = url

        XCTAssertEqual(BackupStore.prune(configurationID: "keep", keep: 5).count, 0)
        XCTAssertEqual(BackupStore.list(configurationID: "keep").count, 1)
    }
}
