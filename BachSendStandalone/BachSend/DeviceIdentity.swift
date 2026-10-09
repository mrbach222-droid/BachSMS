import Foundation
import CryptoKit
import Security

// A stable, random device identity on this iPhone. The private capability is
// stored in the iOS Keychain, not UserDefaults, iCloud, or a file transfer.
struct BSendDeviceIdentity: Codable {
    let id: String             // 128-bit random ID (not a person's name)
    let ownerSecret: String    // 256-bit owner-only Keychain key. Never shared with PC.
    let linkSecret: String     // 256-bit capability for the PC's private link.

    var privateLink: String {
        "https://bachsend-relay.mrbach222.workers.dev/d/\(id)#\(linkSecret)"
    }

    static func loadOrCreate() throws -> BSendDeviceIdentity {
        let service = "com.mrbach222.BachSend.private-device.v06"
        let account = "device"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess {
            guard let data = result as? Data,
                  let identity = try? JSONDecoder().decode(Self.self, from: data),
                  identity.id.count == 32, identity.ownerSecret.count == 64,
                  identity.linkSecret.count == 64,
                  identity.id.allSatisfy({ $0.isHexDigit }),
                  identity.ownerSecret.allSatisfy({ $0.isHexDigit }),
                  identity.linkSecret.allSatisfy({ $0.isHexDigit }) else {
                throw NSError(domain: "B Send Keychain", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Danh tính thiết bị trong Keychain không hợp lệ."])
            }
            return identity
        }
        guard status == errSecItemNotFound else {
            throw NSError(domain: "B Send Keychain", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Không thể đọc Keychain (\(status))."])
        }

        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        func randomSecret() -> String {
            SymmetricKey(size: .bits256).withUnsafeBytes {
                $0.map { String(format: "%02x", $0) }.joined()
            }
        }
        let newIdentity = Self(id: id, ownerSecret: randomSecret(), linkSecret: randomSecret())
        let data = try JSONEncoder().encode(newIdentity)
        let create: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        let saved = SecItemAdd(create as CFDictionary, nil)
        guard saved == errSecSuccess else {
            throw NSError(domain: "B Send Keychain", code: Int(saved),
                          userInfo: [NSLocalizedDescriptionKey: "Không thể lưu danh tính thiết bị (\(saved))."])
        }
        return newIdentity
    }
}
