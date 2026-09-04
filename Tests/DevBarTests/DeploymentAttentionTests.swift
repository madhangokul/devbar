import XCTest
@testable import DevBar

final class DeploymentAttentionTests: XCTestCase {
    func testDismissedFailuresDoNotContributeToAttentionStatusOrCount() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set("failed-1", forKey: DeploymentAttention.dismissedKey)
        let items = [
            item(id: "failed-1", phase: .error),
            item(id: "ready-1", phase: .ready)
        ]

        XCTAssertEqual(
            DeploymentAttention.attentionCount(items: items, providerErrors: [:], defaults: defaults),
            0
        )
        XCTAssertEqual(
            DeploymentAttention.displayStatus(items: items, providerErrors: [:], defaults: defaults),
            .good
        )
    }

    func testUndismissedFailureRemainsVisible() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let now = Date(timeIntervalSince1970: 2_000_000)
        let items = [item(id: "failed-1", phase: .blocked, timestamp: now)]

        XCTAssertEqual(
            DeploymentAttention.attentionCount(
                items: items,
                providerErrors: [:],
                defaults: defaults,
                now: now
            ),
            1
        )
        XCTAssertEqual(
            DeploymentAttention.displayStatus(
                items: items,
                providerErrors: [:],
                defaults: defaults,
                now: now
            ),
            .error
        )
    }

    func testFailureOlderThanTwentyFourHoursIsIgnored() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let now = Date(timeIntervalSince1970: 2_000_000)
        let items = [
            item(
                id: "old-failure",
                phase: .error,
                timestamp: now.addingTimeInterval(-DeploymentAttention.monitoringWindow - 1)
            )
        ]

        XCTAssertTrue(
            DeploymentAttention.visibleFailures(in: items, defaults: defaults, now: now).isEmpty
        )
        XCTAssertEqual(
            DeploymentAttention.displayStatus(
                items: items,
                providerErrors: [:],
                defaults: defaults,
                now: now
            ),
            .good
        )
    }

    private func item(id: String, phase: ItemPhase, timestamp: Date = Date()) -> ToolbarItem {
        ToolbarItem(
            id: id,
            providerId: "vercel",
            groupName: "Project",
            title: "Deployment",
            subtitle: "Production",
            status: phase.isFailure ? .error : .good,
            phase: phase,
            timestamp: timestamp,
            openURL: nil
        )
    }
}
