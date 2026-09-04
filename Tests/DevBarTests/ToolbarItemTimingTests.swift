import XCTest
@testable import DevBar

final class ToolbarItemTimingTests: XCTestCase {
    func testActiveItemIgnoresStaleCompletionTimestamp() {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let item = ToolbarItem(
            id: "active",
            providerId: "vercel",
            groupName: "Project",
            title: "Project",
            subtitle: "Production",
            status: .warning,
            phase: .building,
            timestamp: startedAt.addingTimeInterval(-5),
            openURL: nil,
            startedAt: startedAt,
            completedAt: startedAt
        )

        XCTAssertNil(item.completedBuildDuration)
        XCTAssertEqual(
            item.currentBuildElapsed(at: startedAt.addingTimeInterval(42)),
            42
        )
    }
}
