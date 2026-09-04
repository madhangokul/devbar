import XCTest
@testable import DevBar

final class DeploymentOverlayTrackerTests: XCTestCase {
    func testFirstLiveRefreshDetectsDeploymentAbsentFromLaunchCache() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let cached = item(id: "old", phase: .ready, timestamp: now.addingTimeInterval(-300))
        let building = item(id: "new", phase: .building, timestamp: now)
        var tracker = DeploymentOverlayTracker(initialItems: [cached], startedAt: now)

        XCTAssertEqual(tracker.consume([building, cached])?.id, "new")
    }

    func testActiveDeploymentTransitionsToReady() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let building = item(id: "new", phase: .building, timestamp: now)
        var tracker = DeploymentOverlayTracker(initialItems: [building], startedAt: now)

        XCTAssertEqual(tracker.consume([building])?.phase, .building)
        XCTAssertEqual(tracker.consume([item(id: "new", phase: .ready, timestamp: now)])?.phase, .ready)
        XCTAssertNil(tracker.consume([item(id: "new", phase: .ready, timestamp: now)]))
    }

    func testActiveDeploymentInLaunchCacheAppearsOnFirstRefresh() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let building = item(id: "active", phase: .building, timestamp: now.addingTimeInterval(-300))
        var tracker = DeploymentOverlayTracker(initialItems: [building], startedAt: now)

        XCTAssertEqual(tracker.consume([building])?.id, "active")
    }

    func testFirstRefreshDoesNotShowAnOldCompletedDeployment() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let oldReady = item(id: "old", phase: .ready, timestamp: now.addingTimeInterval(-300))
        var tracker = DeploymentOverlayTracker(startedAt: now)

        XCTAssertNil(tracker.consume([oldReady]))
    }

    func testRecentlyCompletedDeploymentCanAppearOnFirstRefreshWithoutCache() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let ready = item(id: "new", phase: .ready, timestamp: now.addingTimeInterval(-30))
        var tracker = DeploymentOverlayTracker(startedAt: now)

        XCTAssertEqual(tracker.consume([ready])?.id, "new")
    }

    private func item(id: String, phase: ItemPhase, timestamp: Date) -> ToolbarItem {
        ToolbarItem(
            id: id,
            providerId: "vercel",
            groupName: "Project",
            title: "Deployment",
            subtitle: "Production",
            status: phase.isFailure ? .error : (phase.isActive ? .warning : .good),
            phase: phase,
            timestamp: timestamp,
            openURL: nil
        )
    }
}
