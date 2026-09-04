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
    let openURL: URL?

    init(
        id: String,
        providerId: String,
        groupName: String,
        title: String,
        subtitle: String,
        status: ItemStatus,
        phase: ItemPhase = .unknown,
        timestamp: Date,
        openURL: URL?
    ) {
        self.id = id
        self.providerId = providerId
        self.groupName = groupName
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.phase = phase
        self.timestamp = timestamp
        self.openURL = openURL
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
