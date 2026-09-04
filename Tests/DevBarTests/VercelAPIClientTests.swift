import Foundation
import XCTest
@testable import DevBar

final class VercelAPIClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testUsesV7DeploymentListAndInspectorURL() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v7/deployments")
            XCTAssertEqual(request.url?.query?.contains("limit=40"), true)
            XCTAssertEqual(request.url?.query?.contains("teamId=team_123"), true)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token_123")

            return Self.response(
                for: request,
                body: """
                {"deployments":[{
                  "uid":"dpl_1",
                  "name":"devbar",
                  "url":"devbar-git-main.vercel.app",
                  "inspectorUrl":"https://vercel.com/acme/devbar/dpl_1",
                  "created":1788500000000,
                  "readyState":"BUILDING",
                  "target":"production",
                  "meta":{"githubCommitRef":"main","numericValue":42}
                }]}
                """
            )
        }

        let client = VercelAPIClient(token: "token_123", teamId: "team_123", session: makeSession())
        let items = try await client.fetchItems()

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].groupName, "devbar")
        XCTAssertEqual(items[0].phase, .building)
        XCTAssertEqual(items[0].status, .warning)
        XCTAssertEqual(items[0].subtitle, "Production · main")
        XCTAssertEqual(items[0].openURL?.absoluteString, "https://vercel.com/acme/devbar/dpl_1")
    }

    func testMapsEverySupportedLifecycleState() async throws {
        let states = ["READY", "BUILDING", "QUEUED", "INITIALIZING", "ERROR", "CANCELED", "BLOCKED"]
        let deployments = states.enumerated().map { index, state in
            "{\"uid\":\"dpl_\(index)\",\"name\":\"app\",\"createdAt\":1788500000000,\"state\":\"\(state)\"}"
        }.joined(separator: ",")
        MockURLProtocol.handler = { request in
            Self.response(for: request, body: "{\"deployments\":[\(deployments)]}")
        }

        let items = try await VercelAPIClient(token: "token", teamId: nil, session: makeSession()).fetchItems()

        XCTAssertEqual(items.map(\.phase), [.ready, .building, .queued, .initializing, .error, .canceled, .blocked])
        XCTAssertEqual(items.map(\.status), [.good, .warning, .warning, .warning, .error, .error, .error])
    }

    func testRateLimitExposesRetryAfter() async throws {
        MockURLProtocol.handler = { request in
            Self.response(
                for: request,
                statusCode: 429,
                headers: ["Retry-After": "75"],
                body: "{\"error\":{\"message\":\"Too many requests\"}}"
            )
        }

        do {
            _ = try await VercelAPIClient(token: "token", teamId: nil, session: makeSession()).fetchItems()
            XCTFail("Expected a rate-limit error")
        } catch let VercelError.api(statusCode, message, retryAfter) {
            XCTAssertEqual(statusCode, 429)
            XCTAssertEqual(message, "Too many requests")
            XCTAssertEqual(retryAfter, 75)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(
        for request: URLRequest,
        statusCode: Int = 200,
        headers: [String: String] = [:],
        body: String
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!
        return (response, Data(body.utf8))
    }
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
