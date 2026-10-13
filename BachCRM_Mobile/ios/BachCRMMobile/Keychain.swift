import Foundation
import Security

struct SecureSettings {
    static let endpointKey = "bachcrm.endpoint"
    static let tokenKey = "bachcrm.reader.token"

    static func save(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                     kSecAttrService as String: "vn.bachcrm.mobile",
                                     kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        var updated = query
        updated[kSecValueData as String] = data
        updated[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(updated as CFDictionary, nil)
    }

    static func read(_ key: String) -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                     kSecAttrService as String: "vn.bachcrm.mobile",
                                     kSecAttrAccount as String: key,
                                     kSecReturnData as String: true,
                                     kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}