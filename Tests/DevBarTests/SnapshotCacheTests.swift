import Foundation
import XCTest
@testable import DevBar

final class SnapshotCacheTests: XCTestCase {
    func testRoundTripCapsItemsAndContainsNoCredentials() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = SnapshotCache(fileURL: directory.appendingPathComponent("snapshot.json"))
        let now = Date(timeIntervalSince1970: 2_000_000)
        let items = (0..<250).map { index in
            ToolbarItem(
                id: "dpl_\(index)",
                providerId: "vercel",
                groupName: "Project",
                title: "Deploy \(index)",
                subtitle: "Production",
                status: .good,
                phase: .ready,
                timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                openURL: nil
            )
        }

        try cache.save(items, now: now)
        let loaded = try XCTUnwrap(cache.load(now: now))
        let cacheText = try String(contentsOf: cache.fileURL, encoding: .utf8)

        XCTAssertEqual(loaded.count, SnapshotCache.maximumItemCount)
        XCTAssertEqual(loaded.first?.id, "dpl_249")
        XCTAssertFalse(cacheText.localizedCaseInsensitiveContains("token"))
        XCTAssertFalse(cacheText.localizedCaseInsensitiveContains("credential"))
    }

    func testExpiredSnapshotIsIgnored() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = SnapshotCache(fileURL: directory.appendingPathComponent("snapshot.json"))
        let savedAt = Date(timeIntervalSince1970: 1_000_000)

        try cache.save([], now: savedAt)

        XCTAssertNil(try cache.load(now: savedAt.addingTimeInterval(SnapshotCache.timeToLive + 1)))
    }

    func testLoadsLegacySnapshotWithoutTimingAndSeparateURLs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = SnapshotCache(fileURL: directory.appendingPathComponent("snapshot.json"))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacyJSON = """
        {
          "schemaVersion": 1,
          "savedAt": 2000000,
          "items": [{
            "id": "legacy",
            "providerId": "vercel",
            "groupName": "DevBar",
            "title": "DevBar",
            "subtitle": "Production",
            "status": 1,
            "phase": "ready",
            "timestamp": 1999000,
            "openURL": "https://vercel.com/acme/devbar/legacy"
          }]
        }
        """
        try Data(legacyJSON.utf8).write(to: cache.fileURL)

        let loaded = try XCTUnwrap(cache.load(now: Date(timeIntervalSince1970: 2_000)))
        let item = try XCTUnwrap(loaded.first)

        XCTAssertEqual(item.inspectorURL?.absoluteString, "https://vercel.com/acme/devbar/legacy")
        XCTAssertEqual(item.openURL, item.inspectorURL)
        XCTAssertNil(item.siteURL)
        XCTAssertNil(item.startedAt)
        XCTAssertNil(item.completedAt)
        XCTAssertNil(item.estimatedBuildDuration)
    }
}
