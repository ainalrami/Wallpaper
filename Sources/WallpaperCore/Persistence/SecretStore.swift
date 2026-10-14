import Foundation
import Security

/// Stores small secrets such as API keys.
public protocol SecretStoring: Sendable {
    func read(account: String) -> String?
    /// Saves `value`, or deletes the secret when `value` is `nil` or empty.
    func write(_ value: String?, account: String) throws
}

/// Keeps secrets in the user's login keychain.
public struct KeychainSecretStore: SecretStoring {
    public let service: String

    public init(service: String = WallpaperCore.bundleIdentifier) {
        self.service = service
    }

    public func read(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func write(_ value: String?, account: String) throws {
        let query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
