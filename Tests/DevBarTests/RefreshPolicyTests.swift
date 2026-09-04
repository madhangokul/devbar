import XCTest
@testable import DevBar

final class RefreshPolicyTests: XCTestCase {
    func testAdaptiveIntervals() {
        let policy = RefreshPolicy()

        XCTAssertEqual(delay(policy, active: true, open: false), 15)
        XCTAssertEqual(delay(policy, active: false, open: true), 30)
        XCTAssertEqual(delay(policy, active: false, open: false), 30)
    }

    func testFailureBackoffAndCapWithoutJitter() {
        let policy = RefreshPolicy(jitterFraction: 0)

        XCTAssertEqual(delay(policy, failures: 1), 15)
        XCTAssertEqual(delay(policy, failures: 2), 30)
        XCTAssertEqual(delay(policy, failures: 3), 60)
        XCTAssertEqual(delay(policy, failures: 20), 300)
    }

    func testRetryAfterTakesPrecedenceAndIsCapped() {
        let policy = RefreshPolicy(maximumFailureDelay: 300)

        XCTAssertEqual(delay(policy, failures: 3, retryAfter: 90), 90)
        XCTAssertEqual(delay(policy, failures: 3, retryAfter: 900), 300)
    }

    func testRefreshRequestsAreCoalescedWhileOneIsInFlight() async {
        let recorder = RefreshRecorder()
        let refreshGate = RefreshGate()
        let pollingGate = RefreshGate()
        let coordinator = RefreshCoordinator(
            autoRefreshEnabled: true,
            refreshAction: { @MainActor in
                let call = await recorder.recordCall()
                if call == 1 { await refreshGate.wait() }
                return RefreshResult(succeeded: true, items: [], retryAfter: nil)
            },
            sleepAction: { _ in await pollingGate.wait() },
            randomAction: { 0.5 }
        )

        let startTask = Task { await coordinator.start() }
        while await recorder.callCount == 0 { await Task.yield() }
        await coordinator.requestRefresh(.eventHint)
        await refreshGate.open()
        await startTask.value
        await coordinator.stop()

        let callCount = await recorder.callCount
        XCTAssertEqual(callCount, 2)
        await pollingGate.open()
    }

    private func delay(
        _ policy: RefreshPolicy,
        active: Bool = false,
        open: Bool = false,
        failures: Int = 0,
        retryAfter: TimeInterval? = nil
    ) -> TimeInterval {
        policy.nextDelay(
            hasActiveItems: active,
            popoverIsOpen: open,
            consecutiveFailures: failures,
            retryAfter: retryAfter,
            randomUnit: 0.5
        )
    }
}

private actor RefreshRecorder {
    private(set) var callCount = 0

    func recordCall() -> Int {
        callCount += 1
        return callCount
    }
}

private actor RefreshGate {
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
