import Foundation
import XCTest
@testable import DevBar

final class NotificationTransitionTrackerTests: XCTestCase {
    func testInitialHydrationDoesNotNotify() {
        var tracker = NotificationTransitionTracker()

        XCTAssertTrue(tracker.consume([item(phase: .error)]).isEmpty)
    }

    func testReadyAndFailureTransitionsNotifyOnce() {
        var tracker = NotificationTransitionTracker()
        _ = tracker.consume([item(phase: .building)])

        let ready = tracker.consume([item(phase: .ready)])
        let duplicateReady = tracker.consume([item(phase: .ready)])
        let failed = tracker.consume([item(phase: .error)])
        _ = tracker.consume([item(phase: .building)])
        let duplicateFailureState = tracker.consume([item(phase: .error)])

        XCTAssertEqual(ready.map(\.kind), [.success])
        XCTAssertTrue(duplicateReady.isEmpty)
        XCTAssertEqual(failed.map(\.kind), [.failure])
        XCTAssertTrue(duplicateFailureState.isEmpty)
    }

    func testNewFailureAfterHydrationNotifies() {
        var tracker = NotificationTransitionTracker()
        _ = tracker.consume([])

        let notifications = tracker.consume([item(id: "new", phase: .blocked)])

        XCTAssertEqual(notifications.first?.phase, .blocked)
        XCTAssertEqual(notifications.first?.kind, .failure)
    }

    func testServiceRequestsPermissionOnlyWhenEnabledAndHonorsKinds() async {
        let delivery = NotificationDeliverySpy()
        let service = NotificationService(delivery: delivery)
        let disabled = NotificationPreferences(
            isEnabled: false,
            notifyOnSuccess: true,
            notifyOnFailure: true
        )
        let failuresOnly = NotificationPreferences(
            isEnabled: true,
            notifyOnSuccess: false,
            notifyOnFailure: true
        )

        _ = await service.process([item(phase: .building)], preferences: disabled)
        let requestCountWhileDisabled = await delivery.authorizationRequestCount
        XCTAssertEqual(requestCountWhileDisabled, 0)

        _ = await service.process([item(phase: .ready)], preferences: failuresOnly)
        let requestCountAfterEnabling = await delivery.authorizationRequestCount
        let deliveredAfterSuccess = await delivery.delivered
        XCTAssertEqual(requestCountAfterEnabling, 1)
        XCTAssertTrue(deliveredAfterSuccess.isEmpty)

        _ = await service.process([item(phase: .blocked)], preferences: failuresOnly)
        let deliveredAfterFailure = await delivery.delivered
        XCTAssertEqual(deliveredAfterFailure.map(\.kind), [.failure])
    }

    private func item(id: String = "dpl_1", phase: ItemPhase) -> ToolbarItem {
        ToolbarItem(
            id: id,
            providerId: "vercel",
            groupName: "DevBar",
            title: "DevBar",
            subtitle: "Production",
            status: phase.isFailure ? .error : (phase.isActive ? .warning : .good),
            phase: phase,
            timestamp: Date(timeIntervalSince1970: 1),
            openURL: nil
        )
    }
}

private actor NotificationDeliverySpy: NotificationDelivering {
    private(set) var authorizationRequestCount = 0
    private(set) var delivered: [DeploymentNotification] = []

    func requestAuthorization() async throws -> Bool {
        authorizationRequestCount += 1
        return true
    }

    func deliver(_ notification: DeploymentNotification) async throws {
        delivered.append(notification)
    }
}
