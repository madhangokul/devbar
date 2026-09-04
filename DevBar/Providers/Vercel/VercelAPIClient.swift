import Foundation

struct VercelAPIClient: Sendable {
    private let token: String
    private let teamId: String?
    private let session: URLSession

    init(token: String, teamId: String?, session: URLSession = .shared) {
        self.token = token
        self.teamId = teamId?.isEmpty == false ? teamId : nil
        self.session = session
    }

    func fetchItems() async throws -> [ToolbarItem] {
        let deploymentsResponse: VercelDeploymentsResponse = try await request(
            path: "/v7/deployments",
            queryItems: [URLQueryItem(name: "limit", value: "40")]
        )

        let items = deploymentsResponse.deployments.map { deployment in
            let branch = deployment.meta?.githubCommitRef
            let environment = deployment.target?.capitalized ?? "Preview"
            let subtitle = [environment, branch].compactMap { $0 }.joined(separator: " · ")
            let phase = phase(for: deployment.effectiveState)

            return ToolbarItem(
                id: deployment.uid,
                providerId: "vercel",
                groupName: deployment.name,
                title: deployment.name,
                subtitle: subtitle,
                status: status(for: phase),
                phase: phase,
                timestamp: date(fromMilliseconds: deployment.created),
                openURL: deployment.inspectorURL.flatMap(URL.init(string:)),
                siteURL: deployedSiteURL(from: deployment.url),
                startedAt: deployment.buildingAt.map(date(fromMilliseconds:)),
                completedAt: deployment.ready.map(date(fromMilliseconds:))
            )
        }
        return BuildTimingEstimator.addingEstimates(to: items)
    }

    private func request<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        var components = URLComponents(string: "https://api.vercel.com\(path)")
        components?.queryItems = queryItems + (teamId.map { [URLQueryItem(name: "teamId", value: $0)] } ?? [])
        guard let url = components?.url else { throw VercelError.invalidResponse }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw VercelError.invalidResponse }
        guard 200..<300 ~= httpResponse.statusCode else {
            let apiError = try? JSONDecoder().decode(VercelAPIErrorResponse.self, from: data)
            throw VercelError.api(
                statusCode: httpResponse.statusCode,
                message: apiError?.error.message ?? "Vercel request failed (\(httpResponse.statusCode)).",
                retryAfter: retryDelay(from: httpResponse)
            )
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func phase(for state: String?) -> ItemPhase {
        switch state?.uppercased() {
        case "READY": .ready
        case "BUILDING": .building
        case "QUEUED": .queued
        case "INITIALIZING": .initializing
        case "ERROR": .error
        case "CANCELED": .canceled
        case "BLOCKED": .blocked
        default: .unknown
        }
    }

    private func status(for phase: ItemPhase) -> ItemStatus {
        if phase == .ready { return .good }
        if phase.isActive { return .warning }
        if phase.isFailure { return .error }
        return .neutral
    }

    private func date(fromMilliseconds value: TimeInterval) -> Date {
        Date(timeIntervalSince1970: value / 1_000)
    }

    private func deployedSiteURL(from value: String?) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        if let url = URL(string: value), url.scheme != nil { return url }
        return URL(string: "https://\(value)")
    }

    private func retryDelay(from response: HTTPURLResponse, now: Date = Date()) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = TimeInterval(value), seconds >= 0 { return seconds }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        guard let date = formatter.date(from: value) else { return nil }
        return max(0, date.timeIntervalSince(now))
    }
}

private struct VercelAPIErrorResponse: Decodable {
    let error: VercelAPIError
}

private struct VercelAPIError: Decodable {
    let message: String
}
