import Foundation

struct VercelDeploymentsResponse: Decodable {
    let deployments: [VercelDeployment]
}

struct VercelDeployment: Decodable {
    let uid: String
    let name: String
    let url: String?
    let inspectorURL: String?
    let created: TimeInterval
    let readyState: String?
    let state: String?
    let target: String?
    let meta: VercelDeploymentMetadata?

    var effectiveState: String? { readyState ?? state }

    private enum CodingKeys: String, CodingKey {
        case uid
        case name
        case url
        case inspectorURL = "inspectorUrl"
        case created
        case createdAt
        case readyState
        case state
        case target
        case meta
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uid = try container.decode(String.self, forKey: .uid)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        inspectorURL = try container.decodeIfPresent(String.self, forKey: .inspectorURL)
        readyState = try container.decodeIfPresent(String.self, forKey: .readyState)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        target = try container.decodeIfPresent(String.self, forKey: .target)
        meta = try container.decodeIfPresent(VercelDeploymentMetadata.self, forKey: .meta)

        if let value = try container.decodeIfPresent(TimeInterval.self, forKey: .created) {
            created = value
        } else {
            created = try container.decode(TimeInterval.self, forKey: .createdAt)
        }
    }
}

struct VercelDeploymentMetadata: Decodable {
    let githubCommitRef: String?
}

protocol RetryAfterProviding {
    var retryAfter: TimeInterval? { get }
}

enum VercelError: LocalizedError, RetryAfterProviding {
    case missingToken
    case invalidResponse
    case api(statusCode: Int, message: String, retryAfter: TimeInterval?)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            "Add a Vercel access token in Settings."
        case .invalidResponse:
            "Vercel returned an invalid response."
        case .api(_, let message, _):
            message
        }
    }

    var retryAfter: TimeInterval? {
        guard case .api(_, _, let retryAfter) = self else { return nil }
        return retryAfter
    }
}
