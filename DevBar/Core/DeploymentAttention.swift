import Foundation

enum DeploymentAttention {
    static let dismissedKey = "dismissedFailureDeploymentIDs"
    static let monitoringWindow: TimeInterval = 24 * 60 * 60

    static func dismissedIDs(from defaults: UserDefaults = .standard) -> Set<String> {
        Set(
            defaults.string(forKey: dismissedKey)?
                .split(separator: "\n")
                .map(String.init) ?? []
        )
    }

    static func visibleFailures(
        in items: [ToolbarItem],
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> [ToolbarItem] {
        let dismissed = dismissedIDs(from: defaults)
        let cutoff = now.addingTimeInterval(-monitoringWindow)
        return items.filter {
            $0.phase.isFailure &&
                $0.triggeredAt >= cutoff &&
                !dismissed.contains($0.id)
        }
    }

    static func attentionCount(
        items: [ToolbarItem],
        providerErrors: [String: String],
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> Int {
        visibleFailures(in: items, defaults: defaults, now: now).count + providerErrors.count
    }

    static func displayStatus(
        items: [ToolbarItem],
        providerErrors: [String: String],
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> ItemStatus {
        if !providerErrors.isEmpty || !visibleFailures(in: items, defaults: defaults, now: now).isEmpty {
            return .error
        }
        if items.contains(where: { $0.phase.isActive }) { return .warning }
        return items.isEmpty ? .neutral : .good
    }
}
