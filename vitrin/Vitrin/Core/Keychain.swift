import Foundation
#if canImport(Security)
import Security

/// API anahtarları UserDefaults yerine Keychain'de saklanır.
enum Keychain {
    private static func base(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "Vitrin",
         kSecAttrAccount as String: key]
    }

    static func set(_ value: String, for key: String) {
        SecItemDelete(base(key) as CFDictionary)
        guard !value.isEmpty else { return }
        var q = base(key)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        var q = base(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
#else
/// Linux'ta (testler) Keychain yok; bellekte tutulur.
enum Keychain {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var store: [String: String] = [:]
    static func set(_ value: String, for key: String) { lock.lock(); store[key] = value.isEmpty ? nil : value; lock.unlock() }
    static func get(_ key: String) -> String? { lock.lock(); defer { lock.unlock() }; return store[key] }
}
#endif
