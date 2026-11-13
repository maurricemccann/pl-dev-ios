import Foundation
import Security

/// One generic-password item per account, readable after the first unlock, never synced to another device.
/// Every call blocks, so callers stay off the main thread (ConfigStore is an actor).
enum KeyStore {
    struct Failure: Error, Sendable { let status: OSStatus }

    private static let service = Bundle.main.bundleIdentifier ?? "app"

    private static func item(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func save(_ data: Data, account: String) throws {
        _ = SecItemDelete(item(account) as CFDictionary)
        var add = item(account)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly   // background refresh reads it while locked
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    static func load(account: String) -> Data? {
        var find = item(account)
        find[kSecReturnData as String] = true
        find[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(find as CFDictionary, &found) == errSecSuccess else { return nil }
        return found as? Data
    }

    static func delete(account: String) {
        _ = SecItemDelete(item(account) as CFDictionary)
    }

    /// Writes, reads and removes one throwaway item. Nil when the Keychain works, else the reason.
    static func roundTrip() -> String? {
        let account = "probe.roundtrip"
        let token = Data(UUID().uuidString.utf8)
        defer { delete(account: account) }
        do {
            try save(token, account: account)
        } catch let failure as Failure {
            return "The Keychain refused the write (status \(failure.status))."
        } catch {
            return "The Keychain refused the write."
        }
        return load(account: account) == token ? nil : "The Keychain did not return what was written."
    }

    /// Tries a write and a read inside a shared access group, so the probe can say whether this signing lets
    /// the extensions see a Keychain item. Used only by the `sharedKeychain` probe; nothing real is stored there.
    static func sharedProbe(group: String) -> (ok: Bool, detail: String) {
        var base = item("probe.shared")
        base[kSecAttrAccessGroup as String] = group
        _ = SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data("probe".utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else {
            return (false, "This signing does not allow a shared Keychain group (status \(added)). Extensions hold no key anyway.")
        }
        var find = base
        find[kSecReturnData as String] = true
        find[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        let read = SecItemCopyMatching(find as CFDictionary, &found)
        _ = SecItemDelete(base as CFDictionary)
        if read == errSecSuccess { return (true, "A shared Keychain group can be written and read on this install.") }
        return (false, "The shared Keychain group took the write but not the read (status \(read)).")
    }
}
