import Foundation

enum DeploymentAttention {
    static let dismissedKey = "dismissedFailureDeploymentIDs"

    static func dismissedIDs(from defaults: UserDefaults = .standard) -> Set<String> {
        Set(
            defaults.string(forKey: dismissedKey)?
                .split(separator: "\n")
                .map(String.init) ?? []
        )
    }

    static func visibleFailures(
        in items: [ToolbarItem],
        defaults: UserDefaults = .standard
    ) -> [ToolbarItem] {
        let dismissed = dismissedIDs(from: defaults)
        return items.filter { $0.phase.isFailure && !dismissed.contains($0.id) }
    }

    static func attentionCount(
        items: [ToolbarItem],
        providerErrors: [String: String],
        defaults: UserDefaults = .standard
    ) -> Int {
        visibleFailures(in: items, defaults: defaults).count + providerErrors.count
    }

    static func displayStatus(
        items: [ToolbarItem],
        providerErrors: [String: String],
        defaults: UserDefaults = .standard
    ) -> ItemStatus {
        if !providerErrors.isEmpty || !visibleFailures(in: items, defaults: defaults).isEmpty {
            return .error
        }
        if items.contains(where: { $0.phase.isActive }) { return .warning }
        return items.isEmpty ? .neutral : .good
    }
}
