import SwiftUI

enum ItemStatus: Int, Codable, Comparable, Sendable {
    case neutral = 0
    case good = 1
    case warning = 2
    case error = 3

    static func < (lhs: ItemStatus, rhs: ItemStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var color: Color {
        switch self {
        case .good: .green
        case .warning: .orange
        case .error: .red
        case .neutral: .secondary
        }
    }

    var label: String {
        switch self {
        case .good: "Healthy"
        case .warning: "In progress"
        case .error: "Needs attention"
        case .neutral: "Unknown"
        }
    }
}

enum ItemPhase: String, Codable, CaseIterable, Sendable {
    case ready
    case building
    case queued
    case initializing
    case error
    case canceled
    case blocked
    case unknown

    var isActive: Bool {
        self == .building || self == .queued || self == .initializing
    }

    var isFailure: Bool {
        self == .error || self == .canceled || self == .blocked
    }
}

struct ToolbarItem: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let providerId: String
    let groupName: String
    let title: String
    let subtitle: String
    let status: ItemStatus
    let phase: ItemPhase
    let timestamp: Date
    let inspectorURL: URL?
    let siteURL: URL?
    let startedAt: Date?
    let completedAt: Date?
    let estimatedBuildDuration: TimeInterval?

    var triggeredAt: Date { timestamp }
    var readyAt: Date? { completedAt }
    var openURL: URL? { inspectorURL ?? siteURL }

    var completedBuildDuration: TimeInterval? {
        guard let startedAt, let completedAt else { return nil }
        return max(0, completedAt.timeIntervalSince(startedAt))
    }

    func triggerAge(at now: Date = Date()) -> TimeInterval {
        max(0, now.timeIntervalSince(triggeredAt))
    }

    func currentBuildElapsed(at now: Date = Date()) -> TimeInterval? {
        guard phase.isActive else { return nil }
        return max(0, now.timeIntervalSince(startedAt ?? triggeredAt))
    }

    init(
        id: String,
        providerId: String,
        groupName: String,
        title: String,
        subtitle: String,
        status: ItemStatus,
        phase: ItemPhase = .unknown,
        timestamp: Date,
        openURL: URL?,
        siteURL: URL? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        estimatedBuildDuration: TimeInterval? = nil
    ) {
        self.id = id
        self.providerId = providerId
        self.groupName = groupName
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.phase = phase
        self.timestamp = timestamp
        self.inspectorURL = openURL
        self.siteURL = siteURL
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.estimatedBuildDuration = estimatedBuildDuration
    }

    func withEstimatedBuildDuration(_ duration: TimeInterval?) -> ToolbarItem {
        ToolbarItem(
            id: id,
            providerId: providerId,
            groupName: groupName,
            title: title,
            subtitle: subtitle,
            status: status,
            phase: phase,
            timestamp: timestamp,
            openURL: inspectorURL,
            siteURL: siteURL,
            startedAt: startedAt,
            completedAt: completedAt,
            estimatedBuildDuration: duration
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case providerId
        case groupName
        case title
        case subtitle
        case status
        case phase
        case timestamp
        case inspectorURL
        case siteURL
        case startedAt
        case completedAt
        case estimatedBuildDuration
        case legacyOpenURL = "openURL"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        providerId = try container.decode(String.self, forKey: .providerId)
        groupName = try container.decode(String.self, forKey: .groupName)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decode(String.self, forKey: .subtitle)
        status = try container.decode(ItemStatus.self, forKey: .status)
        phase = try container.decodeIfPresent(ItemPhase.self, forKey: .phase) ?? .unknown
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        inspectorURL = try container.decodeIfPresent(URL.self, forKey: .inspectorURL)
            ?? container.decodeIfPresent(URL.self, forKey: .legacyOpenURL)
        siteURL = try container.decodeIfPresent(URL.self, forKey: .siteURL)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        estimatedBuildDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .estimatedBuildDuration)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(providerId, forKey: .providerId)
        try container.encode(groupName, forKey: .groupName)
        try container.encode(title, forKey: .title)
        try container.encode(subtitle, forKey: .subtitle)
        try container.encode(status, forKey: .status)
        try container.encode(phase, forKey: .phase)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(inspectorURL, forKey: .inspectorURL)
        try container.encodeIfPresent(siteURL, forKey: .siteURL)
        try container.encodeIfPresent(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(estimatedBuildDuration, forKey: .estimatedBuildDuration)
    }
}

struct CredentialField: Identifiable, Hashable, Sendable {
    let key: String
    let label: String
    let placeholder: String
    let isSecret: Bool
    let isRequired: Bool

    var id: String { key }
}

protocol ToolbarProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var iconSystemName: String { get }
    var credentialFields: [CredentialField] { get }

    func fetchItems(credentials: [String: String]) async throws -> [ToolbarItem]
}
