import XCTest
@testable import DevBar

final class ToolbarStoreTests: XCTestCase {
    @MainActor
    func testAggregateStatusUsesWorstItem() async {
        let store = ToolbarStore(
            providers: [StubProvider(status: .good), StubProvider(id: "warning", status: .warning)],
            snapshotCache: nil,
            defaults: testDefaults()
        )
        await store.refreshAll()

        XCTAssertEqual(store.aggregateStatus, .warning)
        XCTAssertEqual(store.issueCount, 1)
    }

    @MainActor
    func testProviderFailureDoesNotDiscardSuccessfulItems() async {
        let store = ToolbarStore(
            providers: [StubProvider(status: .good), StubProvider(id: "broken", error: StubError.failed)],
            snapshotCache: nil,
            defaults: testDefaults()
        )
        await store.refreshAll()

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.providerErrors.keys.sorted(), ["broken"])
        XCTAssertEqual(store.aggregateStatus, .error)
    }

    @MainActor
    func testProviderFailurePreservesItsLastGoodSnapshot() async {
        let provider = ScriptedProvider()
        let store = ToolbarStore(
            providers: [provider],
            snapshotCache: nil,
            defaults: testDefaults()
        )
        await store.refreshAll()

        await provider.setShouldFail(true)
        let result = await store.refreshAll()

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(store.items.map(\.id), ["first"])
        XCTAssertEqual(store.providerErrors.keys.sorted(), ["scripted"])
    }

    @MainActor
    func testMissingRequiredCredentialsRemainNeutralUntilConfigured() async {
        let store = ToolbarStore(
            providers: [UnconfiguredProvider()],
            snapshotCache: nil,
            defaults: testDefaults()
        )

        let result = await store.refreshAll()

        XCTAssertTrue(result.succeeded)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.providerErrors.isEmpty)
        XCTAssertEqual(store.aggregateStatus, .neutral)
    }

    private func testDefaults() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString)!
    }
}

private struct StubProvider: ToolbarProvider {
    let id: String
    let displayName = "Stub"
    let iconSystemName = "circle"
    let credentialFields: [CredentialField] = []
    let status: ItemStatus
    let error: StubError?

    init(id: String = "stub", status: ItemStatus = .good, error: StubError? = nil) {
        self.id = id
        self.status = status
        self.error = error
    }

    func fetchItems(credentials: [String: String]) async throws -> [ToolbarItem] {
        if let error { throw error }
        return [ToolbarItem(
            id: id,
            providerId: id,
            groupName: "Project",
            title: "Deployment",
            subtitle: "Production",
            status: status,
            timestamp: Date(),
            openURL: nil
        )]
    }
}

private enum StubError: Error {
    case failed
}

private struct UnconfiguredProvider: ToolbarProvider {
    let id = "unconfigured-\(UUID().uuidString)"
    let displayName = "Unconfigured"
    let iconSystemName = "circle"
    let credentialFields = [
        CredentialField(
            key: "required-token",
            label: "Token",
            placeholder: "Required",
            isSecret: true,
            isRequired: true
        )
    ]

    func fetchItems(credentials: [String: String]) async throws -> [ToolbarItem] {
        throw StubError.failed
    }
}

private actor ScriptedProvider: ToolbarProvider {
    nonisolated let id = "scripted"
    nonisolated let displayName = "Scripted"
    nonisolated let iconSystemName = "circle"
    nonisolated let credentialFields: [CredentialField] = []

    private var shouldFail = false

    func setShouldFail(_ value: Bool) {
        shouldFail = value
    }

    func fetchItems(credentials: [String: String]) async throws -> [ToolbarItem] {
        if shouldFail { throw StubError.failed }
        return [ToolbarItem(
            id: "first",
            providerId: id,
            groupName: "Project",
            title: "Deployment",
            subtitle: "Production",
            status: .good,
            phase: .ready,
            timestamp: Date(timeIntervalSince1970: 1),
            openURL: nil
        )]
    }
}
