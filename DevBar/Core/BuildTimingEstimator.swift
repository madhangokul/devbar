import Foundation

enum BuildTimingEstimator {
    static let sampleSize = 3

    static func estimatedDuration(
        for item: ToolbarItem,
        among items: [ToolbarItem]
    ) -> TimeInterval? {
        let durations = items
            .filter {
                $0.providerId == item.providerId &&
                    $0.groupName == item.groupName &&
                    $0.id != item.id &&
                    $0.phase == .ready &&
                    $0.triggeredAt < item.triggeredAt &&
                    $0.completedBuildDuration != nil
            }
            .sorted { $0.triggeredAt > $1.triggeredAt }
            .prefix(sampleSize)
            .compactMap(\.completedBuildDuration)

        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / Double(durations.count)
    }

    static func addingEstimates(to items: [ToolbarItem]) -> [ToolbarItem] {
        items.map { item in
            guard item.phase.isActive else { return item }
            return item.withEstimatedBuildDuration(estimatedDuration(for: item, among: items))
        }
    }
}
