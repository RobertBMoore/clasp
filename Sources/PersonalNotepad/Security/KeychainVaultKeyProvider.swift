import CryptoKit
import Foundation
import LocalAuthentication
import Security

protocol VaultKeyProviding: AnyObject, Sendable {
    func hasKey() -> Bool
    func createKey(reason: String) async throws -> SymmetricKey
    func deleteKeyIfMatching(_ key: SymmetricKey) throws
    func commitKeyCreation(_ key: SymmetricKey)
    func unlock(reason: String) async throws -> SymmetricKey
    func cachedKey() -> SymmetricKey?
    func lock()
}

extension VaultKeyProviding {
    func commitKeyCreation(_ key: SymmetricKey) {}
}

enum KeychainKeyError: Error, LocalizedError {
    case duplicate
    case notFound
    case cancelled
    case authenticationUnavailable
    case rollbackKeyMismatch
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .duplicate: "A Vault key already exists."
        case .notFound: "The Vault key is missing from this Mac's Keychain."
        case .cancelled: "Vault authentication was cancelled."
        case .authenticationUnavailable: "macOS could not verify your identity for Vault access."
        case .rollbackKeyMismatch: "The Vault key changed before setup could be rolled back, so Clasp left the current Keychain item untouched."
        case .status(let status): "Keychain returned error \(status)."
        }
    }
}

/// `SecItem.h` requires persistent-reference lookups and deletions on macOS to
/// pass the returned CFData inside `kSecMatchItemList`. (`kSecValuePersistentRef`
/// is the corresponding iOS query shape.) Keeping this construction testable
/// prevents a platform-key mix-up from silently disabling setup rollback.
enum KeychainVaultRollbackQuery {
    static func read(persistentReference: Data) -> [String: Any] {
        [
            kSecMatchItemList as String: [persistentReference],
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
    }

    static func delete(persistentReference: Data) -> [String: Any] {
        [kSecMatchItemList as String: [persistentReference]]
    }
}

final class KeychainVaultKeyProvider: @unchecked Sendable, VaultKeyProviding {
    private let service = "com.robertmoore.personalnotepad.vault"
    private let account = "primary-vault-key"
    private let lockState = NSLock()
    private var memoryKey: SymmetricKey?
    private var rollbackCandidateKeyData: Data?
    private var rollbackCandidatePersistentReference: Data?

    func hasKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    func createKey(reason: String) async throws -> SymmetricKey {
        guard !hasKey() else { throw KeychainKeyError.duplicate }
        try await verifyUserPresence(reason: reason)

        let key = VaultCrypto.generateKey()
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: VaultCrypto.keyData(key),
            kSecReturnPersistentRef as String: true
        ]
        var result: CFTypeRef?
        let status = SecItemAdd(attributes as CFDictionary, &result)
        guard status == errSecSuccess else { throw KeychainKeyError.status(status) }
        setCreatedKey(key, persistentReference: result as? Data)
        return key
    }

    /// Removes a just-created setup key only while the exact same key is still
    /// stored under Clasp's service/account pair. A replacement key is never
    /// deleted during rollback.
    func deleteKeyIfMatching(_ key: SymmetricKey) throws {
        let expectedData = VaultCrypto.keyData(key)
        let persistentReference = lockState.withLock {
            rollbackCandidateKeyData == expectedData
                ? rollbackCandidatePersistentReference
                : nil
        }
        if let persistentReference {
            try deleteKey(
                expectedData: expectedData,
                readQuery: KeychainVaultRollbackQuery.read(
                    persistentReference: persistentReference
                ),
                deleteQuery: KeychainVaultRollbackQuery.delete(
                    persistentReference: persistentReference
                )
            )
            return
        }

        // `SecItemAdd` should always return the requested persistent reference.
        // Keep a value-checked fallback so an unexpected platform result still
        // permits a safe first-setup retry rather than stranding the new key.
        let readQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        try deleteKey(expectedData: expectedData, readQuery: readQuery, deleteQuery: deleteQuery)
    }

    func commitKeyCreation(_ key: SymmetricKey) {
        let expectedData = VaultCrypto.keyData(key)
        lockState.withLock {
            guard rollbackCandidateKeyData == expectedData else { return }
            rollbackCandidateKeyData = nil
            rollbackCandidatePersistentReference = nil
        }
    }

    func unlock(reason: String) async throws -> SymmetricKey {
        if let key = cachedKey() { return key }
        try await verifyUserPresence(reason: reason)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecUserCanceled || status == errSecAuthFailed { throw KeychainKeyError.cancelled }
        if status == errSecItemNotFound { throw KeychainKeyError.notFound }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainKeyError.status(status)
        }
        let key = try VaultCrypto.key(from: data)
        setCached(key)
        return key
    }

    func cachedKey() -> SymmetricKey? {
        lockState.lock()
        defer { lockState.unlock() }
        return memoryKey
    }

    func lock() {
        lockState.withLock {
            memoryKey = nil
            rollbackCandidateKeyData = nil
            rollbackCandidatePersistentReference = nil
        }
    }

    private func setCached(_ key: SymmetricKey?) {
        lockState.lock()
        memoryKey = key
        lockState.unlock()
    }

    private func setCreatedKey(_ key: SymmetricKey, persistentReference: Data?) {
        lockState.withLock {
            memoryKey = key
            rollbackCandidateKeyData = VaultCrypto.keyData(key)
            rollbackCandidatePersistentReference = persistentReference
        }
    }

    private func deleteKey(
        expectedData: Data,
        readQuery: [String: Any],
        deleteQuery: [String: Any]
    ) throws {
        var result: CFTypeRef?
        let readStatus = SecItemCopyMatching(readQuery as CFDictionary, &result)
        if readStatus == errSecItemNotFound {
            clearRollbackState(ifMatching: expectedData)
            return
        }
        guard readStatus == errSecSuccess, let currentData = result as? Data else {
            throw KeychainKeyError.status(readStatus)
        }
        guard currentData == expectedData else {
            throw KeychainKeyError.rollbackKeyMismatch
        }

        let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw KeychainKeyError.status(deleteStatus)
        }
        clearRollbackState(ifMatching: expectedData)
    }

    private func clearRollbackState(ifMatching expectedData: Data) {
        lockState.withLock {
            if let memoryKey, VaultCrypto.keyData(memoryKey) == expectedData {
                self.memoryKey = nil
            }
            if rollbackCandidateKeyData == expectedData {
                rollbackCandidateKeyData = nil
                rollbackCandidatePersistentReference = nil
            }
        }
    }

    private func verifyUserPresence(reason: String) async throws {
        let context = LAContext()
        var availabilityError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &availabilityError) else {
            throw KeychainKeyError.authenticationUnavailable
        }
        do {
            guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) else {
                throw KeychainKeyError.authenticationUnavailable
            }
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel:
                throw KeychainKeyError.cancelled
            default:
                throw KeychainKeyError.authenticationUnavailable
            }
        }
    }
}
