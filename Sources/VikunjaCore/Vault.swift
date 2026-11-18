import Foundation
import Security

public struct Credentials: Codable, Sendable, Equatable {
    public let server: URL
    public let token: String

    public init(server: URL, token: String) {
        self.server = server
        self.token = token
    }
}

/// The server and API token, as one keychain item.
public enum Vault {
    static let service = "com.nimrc.vikunja-bar"
    static let account = "credentials"

    static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public static func load() -> Credentials? {
        var q = query
        q[kSecReturnData as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    public static func save(_ credentials: Credentials) throws {
        let data = try JSONEncoder().encode(credentials)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query
            q[kSecValueData as String] = data
            status = SecItemAdd(q as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    public static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
