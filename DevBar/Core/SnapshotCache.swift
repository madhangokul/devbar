import Foundation

struct SnapshotCache: Sendable {
    static let maximumItemCount = 200
    static let timeToLive: TimeInterval = 7 * 24 * 60 * 60

    let fileURL: URL

    static func applicationSupport(fileManager: FileManager = .default) -> SnapshotCache? {
        guard let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return SnapshotCache(fileURL: root
            .appendingPathComponent("DevBar", isDirectory: true)
            .appendingPathComponent("snapshot-v1.json"))
    }

    func load(now: Date = Date(), fileManager: FileManager = .default) throws -> [ToolbarItem]? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let envelope = try decoder.decode(Envelope.self, from: Data(contentsOf: fileURL))
        guard envelope.schemaVersion == 1,
              now.timeIntervalSince(envelope.savedAt) <= Self.timeToLive else {
            return nil
        }
        return Array(envelope.items
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(Self.maximumItemCount))
    }

    func save(
        _ items: [ToolbarItem],
        now: Date = Date(),
        fileManager: FileManager = .default
    ) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let boundedItems = Array(items
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(Self.maximumItemCount))
        let envelope = Envelope(schemaVersion: 1, savedAt: now, items: boundedItems)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(envelope).write(to: fileURL, options: [.atomic])
    }
}

private struct Envelope: Codable {
    let schemaVersion: Int
    let savedAt: Date
    let items: [ToolbarItem]
}
