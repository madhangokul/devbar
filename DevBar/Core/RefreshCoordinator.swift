import Foundation

enum RefreshTrigger: Sendable {
    case launch
    case popoverOpened
    case wake
    case connectivityRestored
    case manual
    case eventHint
    case timer
}

struct ProviderEventHint: Sendable, Equatable {
    let providerId: String
    let eventId: String?
}

protocol EventHintSource: Sendable {
    func events() -> AsyncStream<ProviderEventHint>
}

struct RefreshResult: Sendable {
    let succeeded: Bool
    let items: [ToolbarItem]
    let retryAfter: TimeInterval?

    var hasActiveItems: Bool { items.contains { $0.phase.isActive } }
}

struct RefreshPolicy: Sendable {
    let activeInterval: TimeInterval
    let openSettledInterval: TimeInterval
    let closedSettledInterval: TimeInterval
    let initialFailureDelay: TimeInterval
    let maximumFailureDelay: TimeInterval
    let jitterFraction: Double

    init(
        activeInterval: TimeInterval = 5,
        openSettledInterval: TimeInterval = 5,
        closedSettledInterval: TimeInterval = 5,
        initialFailureDelay: TimeInterval = 15,
        maximumFailureDelay: TimeInterval = 300,
        jitterFraction: Double = 0.2
    ) {
        self.activeInterval = activeInterval
        self.openSettledInterval = openSettledInterval
        self.closedSettledInterval = closedSettledInterval
        self.initialFailureDelay = initialFailureDelay
        self.maximumFailureDelay = maximumFailureDelay
        self.jitterFraction = jitterFraction
    }

    func nextDelay(
        hasActiveItems: Bool,
        popoverIsOpen: Bool,
        consecutiveFailures: Int,
        retryAfter: TimeInterval?,
        randomUnit: Double
    ) -> TimeInterval {
        if let retryAfter, retryAfter >= 0 {
            return min(maximumFailureDelay, retryAfter)
        }

        guard consecutiveFailures > 0 else {
            if hasActiveItems { return activeInterval }
            return popoverIsOpen ? openSettledInterval : closedSettledInterval
        }

        let exponent = min(consecutiveFailures - 1, 10)
        let exponential = min(maximumFailureDelay, initialFailureDelay * pow(2, Double(exponent)))
        let unit = min(1, max(0, randomUnit))
        let jitter = exponential * jitterFraction * ((unit * 2) - 1)
        return max(1, min(maximumFailureDelay, exponential + jitter))
    }
}

actor RefreshCoordinator {
    static let autoRefreshEnabledKey = "autoRefreshEnabled"

    typealias RefreshAction = @MainActor @Sendable () async -> RefreshResult
    typealias SleepAction = @Sendable (TimeInterval) async -> Void
    typealias RandomAction = @Sendable () -> Double

    private let policy: RefreshPolicy
    private let refreshAction: RefreshAction
    private let sleepAction: SleepAction
    private let randomAction: RandomAction

    private var isRunning = false
    private var isOnline = true
    private var popoverIsOpen = false
    private var autoRefreshEnabled: Bool
    private var refreshInProgress = false
    private var refreshPending = false
    private var pollingTask: Task<Void, Never>?
    private var eventHintTask: Task<Void, Never>?
    private var consecutiveFailures = 0
    private var lastResult: RefreshResult?

    init(
        policy: RefreshPolicy = RefreshPolicy(),
        autoRefreshEnabled: Bool = UserDefaults.standard.object(forKey: "autoRefreshEnabled") as? Bool ?? true,
        refreshAction: @escaping RefreshAction,
        sleepAction: @escaping SleepAction = { delay in
            let nanoseconds = UInt64(max(0, delay) * 1_000_000_000)
            try? await Task<Never, Never>.sleep(nanoseconds: nanoseconds)
        },
        randomAction: @escaping RandomAction = { Double.random(in: 0...1) }
    ) {
        self.policy = policy
        self.autoRefreshEnabled = autoRefreshEnabled
        self.refreshAction = refreshAction
        self.sleepAction = sleepAction
        self.randomAction = randomAction
    }

    func start() async {
        guard !isRunning else { return }
        isRunning = true
        await requestRefresh(.launch)
    }

    func stop() {
        isRunning = false
        pollingTask?.cancel()
        pollingTask = nil
        eventHintTask?.cancel()
        eventHintTask = nil
        refreshPending = false
    }

    func connectEventHints(from source: any EventHintSource) {
        eventHintTask?.cancel()
        eventHintTask = Task { [weak self] in
            for await _ in source.events() {
                guard !Task.isCancelled else { return }
                await self?.requestRefresh(.eventHint)
            }
        }
    }

    func setAutoRefreshEnabled(_ enabled: Bool) async {
        autoRefreshEnabled = enabled
        if enabled {
            await requestRefresh(.manual)
        } else {
            pollingTask?.cancel()
            pollingTask = nil
        }
    }

    func setPopoverOpen(_ isOpen: Bool) async {
        popoverIsOpen = isOpen
        if isOpen { await requestRefresh(.popoverOpened) }
    }

    func setOnline(_ online: Bool) async {
        guard isOnline != online else { return }
        isOnline = online
        if online {
            await requestRefresh(.connectivityRestored)
        } else {
            pollingTask?.cancel()
            pollingTask = nil
        }
    }

    func requestRefresh(_ trigger: RefreshTrigger) async {
        guard isOnline, isRunning, autoRefreshEnabled || trigger == .manual else { return }
        if case .timer = trigger {
            // The timer invokes this method from pollingTask itself. Cancelling it here
            // also cancels the URLSession request started below.
        } else {
            pollingTask?.cancel()
        }
        pollingTask = nil

        if refreshInProgress {
            refreshPending = true
            return
        }

        refreshInProgress = true
        repeat {
            refreshPending = false
            let result = await refreshAction()
            lastResult = result
            if result.succeeded {
                consecutiveFailures = 0
            } else {
                consecutiveFailures += 1
            }
        } while refreshPending && isRunning && isOnline
        refreshInProgress = false

        scheduleNextRefresh()
    }

    private func scheduleNextRefresh() {
        guard isRunning, isOnline, autoRefreshEnabled else { return }
        let delay = policy.nextDelay(
            hasActiveItems: lastResult?.hasActiveItems ?? false,
            popoverIsOpen: popoverIsOpen,
            consecutiveFailures: consecutiveFailures,
            retryAfter: lastResult?.retryAfter,
            randomUnit: randomAction()
        )
        let sleepAction = sleepAction
        pollingTask = Task { [weak self] in
            await sleepAction(delay)
            guard !Task.isCancelled else { return }
            await self?.requestRefresh(.timer)
        }
    }
}
