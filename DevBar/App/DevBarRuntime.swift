import Foundation
import Network

@MainActor
final class DevBarRuntime: ObservableObject {
    let store: ToolbarStore
    let coordinator: RefreshCoordinator

    private let notificationService: NotificationService
    private let networkMonitor = NetworkMonitor()
    private var hasStarted = false

    init(providers: [any ToolbarProvider] = ProviderRegistry.all) {
        let store = ToolbarStore(providers: providers)
        let notificationService = NotificationService(
            tracker: NotificationTransitionTracker(initialItems: store.items)
        )

        self.store = store
        self.notificationService = notificationService
        coordinator = RefreshCoordinator {
            let result = await store.refreshAll()
            await notificationService.process(
                result.items,
                preferences: NotificationPreferences.load()
            )
            return result
        }
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        networkMonitor.start { [coordinator] isOnline in
            Task { await coordinator.setOnline(isOnline) }
        }
        await coordinator.start()
    }

    func stop() async {
        networkMonitor.stop()
        await coordinator.stop()
        hasStarted = false
    }
}

private final class NetworkMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "io.github.madhangokul.devbar.network-monitor", qos: .utility)
    private var isStarted = false

    func start(onChange: @escaping @Sendable (Bool) -> Void) {
        guard !isStarted else { return }
        isStarted = true
        monitor.pathUpdateHandler = { path in
            onChange(path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    func stop() {
        guard isStarted else { return }
        monitor.cancel()
        isStarted = false
    }
}
