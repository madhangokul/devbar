import Foundation

struct DeploymentOverlayTracker {
    private var previousItemsByKey: [String: ToolbarItem]
    private let startedAt: Date
    private let recentCompletionWindow: TimeInterval

    init(
        initialItems: [ToolbarItem] = [],
        startedAt: Date = Date(),
        recentCompletionWindow: TimeInterval = 90
    ) {
        previousItemsByKey = Dictionary(
            uniqueKeysWithValues: initialItems
                .filter { !$0.phase.isActive }
                .map { (Self.key(for: $0), $0) }
        )
        self.startedAt = startedAt
        self.recentCompletionWindow = recentCompletionWindow
    }

    mutating func consume(
        _ items: [ToolbarItem],
        excluding dismissedIDs: Set<String> = []
    ) -> ToolbarItem? {
        let currentByKey = Dictionary(
            uniqueKeysWithValues: items.map { (Self.key(for: $0), $0) }
        )
        defer { previousItemsByKey = currentByKey }

        return items
            .filter { item in
                guard !dismissedIDs.contains(item.id) else { return false }
                guard item.phase.isActive || item.phase == .ready || item.phase.isFailure else { return false }

                if let previous = previousItemsByKey[Self.key(for: item)] {
                    return previous.phase != item.phase && (item.phase.isActive || previous.phase.isActive)
                }

                if item.phase.isActive { return true }
                return item.triggeredAt >= startedAt.addingTimeInterval(-recentCompletionWindow)
            }
            .max { $0.triggeredAt < $1.triggeredAt }
    }

    private static func key(for item: ToolbarItem) -> String {
        "\(item.providerId):\(item.id)"
    }
}
