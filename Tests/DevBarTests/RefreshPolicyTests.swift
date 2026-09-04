import XCTest
@testable import DevBar

final class RefreshPolicyTests: XCTestCase {
    func testAdaptiveIntervals() {
        let policy = RefreshPolicy()

        XCTAssertEqual(delay(policy, active: true, open: false), 5)
        XCTAssertEqual(delay(policy, active: false, open: true), 5)
        XCTAssertEqual(delay(policy, active: false, open: false), 5)
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

    func testTimerRefreshDoesNotCancelItsOwnNetworkTask() async {
        let recorder = RefreshRecorder()
        let sleeper = OneShotPollingSleeper()
        let coordinator = RefreshCoordinator(
            autoRefreshEnabled: true,
            refreshAction: { @MainActor in
                await recorder.recordCancellation(Task.isCancelled)
                return RefreshResult(succeeded: true, items: [], retryAfter: nil)
            },
            sleepAction: { _ in await sleeper.sleep() },
            randomAction: { 0.5 }
        )

        await coordinator.start()
        await sleeper.fire()
        while await recorder.callCount < 2 { await Task.yield() }
        await coordinator.stop()

        let cancellations = await recorder.cancellationStates
        XCTAssertEqual(cancellations.prefix(2), [false, false])
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
    private(set) var cancellationStates: [Bool] = []

    func recordCall() -> Int {
        callCount += 1
        return callCount
    }

    func recordCancellation(_ isCancelled: Bool) {
        callCount += 1
        cancellationStates.append(isCancelled)
    }
}

private actor OneShotPollingSleeper {
    private var continuation: CheckedContinuation<Void, Never>?
    private var shouldFire = false
    private var invocationCount = 0

    func sleep() async {
        invocationCount += 1
        if invocationCount > 1 {
            try? await Task.sleep(nanoseconds: UInt64.max)
            return
        }
        if shouldFire { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func fire() {
        shouldFire = true
        continuation?.resume()
        continuation = nil
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
