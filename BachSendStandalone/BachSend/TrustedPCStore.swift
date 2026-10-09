import Foundation
import Security

// Explicitly trusted personal-computer public ECDH keys. The PC's private
// ECDH key remains non-extractable in that browser's IndexedDB.
enum BSendTrustedPCStore {
    private static let service = "com.mrbach222.BachSend.personal-trusted-pcs.v062"
    private static let account = "ecdhe-public-keys"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func list() throws -> [Data] {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &found)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let data = found as? Data else {
            throw NSError(domain: "B Send Trusted PC Keychain", code: Int(status))
        }
        return try JSONDecoder().decode([Data].self, from: data)
    }

    static func contains(_ publicKey: Data) throws -> Bool {
        guard publicKey.count == 65 else { return false }
        return try list().contains(publicKey)
    }

    static func add(_ publicKey: Data) throws {
        guard publicKey.count == 65 else { return }
        var keys = try list()
        if keys.contains(publicKey) { return }
        // Bound Keychain storage. Explicit "Forget" lets users reset trust.
        if keys.count >= 12 { keys.removeFirst(keys.count - 11) }
        keys.append(publicKey)
        let data = try JSONEncoder().encode(keys)
        var changes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var create = query
            create[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            create[kSecValueData as String] = data
            let newStatus = SecItemAdd(create as CFDictionary, nil)
            guard newStatus == errSecSuccess else {
                throw NSError(domain: "B Send Trusted PC Keychain", code: Int(newStatus))
            }
        } else if status != errSecSuccess {
            throw NSError(domain: "B Send Trusted PC Keychain", code: Int(status))
        }
    }

    static func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: "B Send Trusted PC Keychain", code: Int(status))
        }
    }
}
