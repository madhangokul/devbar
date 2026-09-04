import Foundation
import UserNotifications

struct NotificationPreferences: Sendable, Equatable {
    static let enabledKey = "notificationsEnabled"
    static let successKey = "notifyOnSuccess"
    static let failureKey = "notifyOnFailure"

    var isEnabled: Bool
    var notifyOnSuccess: Bool
    var notifyOnFailure: Bool

    static func load(from defaults: UserDefaults = .standard) -> NotificationPreferences {
        NotificationPreferences(
            isEnabled: defaults.object(forKey: enabledKey) as? Bool ?? false,
            notifyOnSuccess: defaults.object(forKey: successKey) as? Bool ?? true,
            notifyOnFailure: defaults.object(forKey: failureKey) as? Bool ?? true
        )
    }
}

struct DeploymentNotification: Identifiable, Sendable, Equatable {
    enum Kind: String, Sendable {
        case success
        case failure
    }

    let itemId: String
    let providerId: String
    let projectName: String
    let phase: ItemPhase
    let kind: Kind
    let timestamp: Date

    var id: String { "\(providerId):\(itemId):\(phase.rawValue)" }

    var title: String {
        switch kind {
        case .success: "Deployment ready"
        case .failure: "Deployment \(phase.rawValue)"
        }
    }

    var body: String { projectName }
}

struct NotificationTransitionTracker: Sendable {
    private var hasHydrated = false
    private var phaseByItemId: [String: ItemPhase] = [:]
    private var announcedIds: Set<String> = []
    private var announcedIdOrder: [String] = []
    private let announcementLimit: Int

    init(announcementLimit: Int = 400) {
        self.announcementLimit = max(1, announcementLimit)
    }

    mutating func consume(_ items: [ToolbarItem], now: Date = Date()) -> [DeploymentNotification] {
        var currentPhases: [String: ItemPhase] = [:]
        for item in items {
            currentPhases[notificationItemKey(for: item)] = item.phase
        }

        guard hasHydrated else {
            hasHydrated = true
            phaseByItemId = currentPhases
            return []
        }

        var notifications: [DeploymentNotification] = []
        for item in items {
            let itemKey = notificationItemKey(for: item)
            let oldPhase = phaseByItemId[itemKey]
            guard oldPhase != item.phase else { continue }

            let kind: DeploymentNotification.Kind?
            if item.phase == .ready, oldPhase != nil {
                kind = .success
            } else if item.phase.isFailure {
                kind = .failure
            } else {
                kind = nil
            }

            guard let kind else { continue }
            let notification = DeploymentNotification(
                itemId: item.id,
                providerId: item.providerId,
                projectName: item.groupName,
                phase: item.phase,
                kind: kind,
                timestamp: now
            )
            guard announcedIds.insert(notification.id).inserted else { continue }
            announcedIdOrder.append(notification.id)
            notifications.append(notification)
        }

        phaseByItemId = currentPhases
        trimAnnouncementsIfNeeded()
        return notifications
    }

    private func notificationItemKey(for item: ToolbarItem) -> String {
        "\(item.providerId):\(item.id)"
    }

    private mutating func trimAnnouncementsIfNeeded() {
        guard announcedIdOrder.count > announcementLimit else { return }
        let overflow = announcedIdOrder.count - announcementLimit
        for id in announcedIdOrder.prefix(overflow) {
            announcedIds.remove(id)
        }
        announcedIdOrder.removeFirst(overflow)
    }
}

protocol NotificationDelivering: Sendable {
    func requestAuthorization() async throws -> Bool
    func deliver(_ notification: DeploymentNotification) async throws
}

final class SystemNotificationDelivery: NotificationDelivering, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func deliver(_ notification: DeploymentNotification) async throws {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = notification.kind == .failure ? .default : nil
        let request = UNNotificationRequest(
            identifier: notification.id,
            content: content,
            trigger: nil
        )
        try await center.add(request)
    }
}

actor NotificationService {
    private let delivery: any NotificationDelivering
    private var tracker: NotificationTransitionTracker
    private var authorizationGranted: Bool?
    private(set) var recentNotifications: [DeploymentNotification] = []

    init(
        delivery: any NotificationDelivering = SystemNotificationDelivery(),
        tracker: NotificationTransitionTracker = NotificationTransitionTracker()
    ) {
        self.delivery = delivery
        self.tracker = tracker
    }

    @discardableResult
    func process(
        _ items: [ToolbarItem],
        preferences: NotificationPreferences = .load()
    ) async -> [DeploymentNotification] {
        let transitions = tracker.consume(items)
        if !transitions.isEmpty {
            recentNotifications.insert(contentsOf: transitions.reversed(), at: 0)
            recentNotifications = Array(recentNotifications.prefix(100))
        }

        guard preferences.isEnabled else { return transitions }
        if authorizationGranted == nil {
            authorizationGranted = (try? await delivery.requestAuthorization()) ?? false
        }
        guard authorizationGranted == true else { return transitions }

        for transition in transitions where shouldDeliver(transition, preferences: preferences) {
            try? await delivery.deliver(transition)
        }
        return transitions
    }

    private func shouldDeliver(
        _ notification: DeploymentNotification,
        preferences: NotificationPreferences
    ) -> Bool {
        switch notification.kind {
        case .success: preferences.notifyOnSuccess
        case .failure: preferences.notifyOnFailure
        }
    }
}
