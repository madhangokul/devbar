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
        let items = [item(id: "failed-1", phase: .blocked)]

        XCTAssertEqual(
            DeploymentAttention.attentionCount(items: items, providerErrors: [:], defaults: defaults),
            1
        )
        XCTAssertEqual(
            DeploymentAttention.displayStatus(items: items, providerErrors: [:], defaults: defaults),
            .error
        )
    }

    private func item(id: String, phase: ItemPhase) -> ToolbarItem {
        ToolbarItem(
            id: id,
            providerId: "vercel",
            groupName: "Project",
            title: "Deployment",
            subtitle: "Production",
            status: phase.isFailure ? .error : .good,
            phase: phase,
            timestamp: Date(),
            openURL: nil
        )
    }
}
