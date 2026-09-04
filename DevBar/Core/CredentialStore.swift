import Foundation
import Security

enum CredentialStore {
    private static let servicePrefix = "io.github.madhangokul.devbar"

    static func save(_ value: String, key: String, providerId: String) throws {
        let query = baseQuery(key: key, providerId: providerId)
        SecItemDelete(query as CFDictionary)

        guard !value.isEmpty else { return }

        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw CredentialError.keychain(status) }
    }

    static func read(key: String, providerId: String) -> String? {
        var query = baseQuery(key: key, providerId: providerId)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func credentials(for provider: any ToolbarProvider) -> [String: String] {
        Dictionary(uniqueKeysWithValues: provider.credentialFields.compactMap { field in
            read(key: field.key, providerId: provider.id).map { (field.key, $0) }
        })
    }

    private static func baseQuery(key: String, providerId: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(servicePrefix).\(providerId).\(key)",
            kSecAttrAccount as String: key
        ]
    }
}

enum CredentialError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
        }
    }
}
