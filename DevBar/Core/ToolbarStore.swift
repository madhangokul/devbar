import Foundation

@MainActor
final class ToolbarStore: ObservableObject {
    @Published private(set) var items: [ToolbarItem] = []
    @Published private(set) var providerErrors: [String: String] = [:]
    @Published var selectedProviderId: String?
    @Published var selectedGroupName: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var enabledProviderIDs: Set<String>

    let providers: [any ToolbarProvider]
    private let snapshotCache: SnapshotCache?
    private let defaults: UserDefaults

    init(
        providers: [any ToolbarProvider],
        snapshotCache: SnapshotCache? = SnapshotCache.applicationSupport(),
        defaults: UserDefaults = .standard
    ) {
        self.providers = providers
        self.snapshotCache = snapshotCache
        self.defaults = defaults
        let saved = defaults.stringArray(forKey: "enabledProviderIDs")
        enabledProviderIDs = Set(saved ?? providers.map(\.id))
        if let snapshotCache, let cached = try? snapshotCache.load() {
            items = cached.filter { enabledProviderIDs.contains($0.providerId) }
        }
    }

    var enabledProviders: [any ToolbarProvider] {
        providers.filter { enabledProviderIDs.contains($0.id) }
    }

    var visibleItems: [ToolbarItem] {
        items.filter { item in
            (selectedProviderId == nil || item.providerId == selectedProviderId) &&
            (selectedGroupName == nil || item.groupName == selectedGroupName)
        }
    }

    var availableGroups: [String] {
        Array(Set(items
            .filter { selectedProviderId == nil || $0.providerId == selectedProviderId }
            .map(\.groupName)))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var aggregateStatus: ItemStatus {
        if !providerErrors.isEmpty || items.contains(where: { $0.status == .error }) { return .error }
        if items.contains(where: { $0.status == .warning }) { return .warning }
        if items.isEmpty { return .neutral }
        return .good
    }

    var issueCount: Int {
        items.filter { $0.status == .warning || $0.status == .error }.count + providerErrors.count
    }

    func isEnabled(_ providerId: String) -> Bool {
        enabledProviderIDs.contains(providerId)
    }

    func setEnabled(_ enabled: Bool, providerId: String) {
        if enabled {
            enabledProviderIDs.insert(providerId)
        } else {
            enabledProviderIDs.remove(providerId)
            items.removeAll { $0.providerId == providerId }
            providerErrors[providerId] = nil
            if selectedProviderId == providerId { selectedProviderId = nil }
        }
        defaults.set(Array(enabledProviderIDs), forKey: "enabledProviderIDs")
    }

    @discardableResult
    func refreshAll() async -> RefreshResult {
        guard !isRefreshing else {
            return RefreshResult(succeeded: false, items: items, retryAfter: nil)
        }
        isRefreshing = true
        defer { isRefreshing = false }

        let providerInputs = enabledProviders.compactMap { provider -> ((any ToolbarProvider), [String: String])? in
            let credentials = CredentialStore.credentials(for: provider)
            let isConfigured = !provider.credentialFields.contains { field in
                field.isRequired && credentials[field.key, default: ""].isEmpty
            }
            return isConfigured ? (provider, credentials) : nil
        }
        var fetchedByProvider: [String: [ToolbarItem]] = [:]
        var errors: [String: String] = [:]
        var retryAfter: TimeInterval?

        await withTaskGroup(of: ProviderFetchResult.self) { group in
            for (provider, credentials) in providerInputs {
                group.addTask {
                    do {
                        return .success(provider.id, try await provider.fetchItems(credentials: credentials))
                    } catch {
                        return .failure(
                            provider.id,
                            error.localizedDescription,
                            (error as? RetryAfterProviding)?.retryAfter
                        )
                    }
                }
            }

            for await result in group {
                switch result {
                case .success(let providerId, let fetched): fetchedByProvider[providerId] = fetched
                case .failure(let providerId, let message, let providerRetryAfter):
                    errors[providerId] = message
                    if let providerRetryAfter {
                        retryAfter = max(retryAfter ?? 0, providerRetryAfter)
                    }
                }
            }
        }

        let enabledIDs = enabledProviderIDs
        let successfulIDs = Set(fetchedByProvider.keys).intersection(enabledIDs)
        items = items.filter { enabledIDs.contains($0.providerId) && !successfulIDs.contains($0.providerId) }
        items.append(contentsOf: fetchedByProvider
            .filter { enabledIDs.contains($0.key) }
            .values
            .flatMap { $0 })
        items.sort { $0.timestamp > $1.timestamp }
        items = Array(items.prefix(SnapshotCache.maximumItemCount))
        providerErrors = errors.filter { enabledIDs.contains($0.key) }
        if !successfulIDs.isEmpty || enabledIDs.isEmpty {
            lastUpdated = Date()
            try? snapshotCache?.save(items)
        }

        if let group = selectedGroupName, !availableGroups.contains(group) {
            selectedGroupName = nil
        }

        return RefreshResult(
            succeeded: providerErrors.isEmpty,
            items: items,
            retryAfter: retryAfter
        )
    }
}

private enum ProviderFetchResult: Sendable {
    case success(String, [ToolbarItem])
    case failure(String, String, TimeInterval?)
}
