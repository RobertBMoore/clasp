import CryptoKit
import Foundation

protocol VaultStoring: Sendable {
    func isConfigured() async -> Bool
    func setup() async throws -> [Note]
    func unlock() async throws -> [Note]
    func save(_ notes: [Note]) async throws
    func lock() async
    func export(notes: [Note]) async throws -> (data: Data, recoveryKey: RecoveryKey)
    func importVault(_ data: Data, recoveryKey: RecoveryKey) async throws -> [Note]
}

enum VaultStoreError: Error, LocalizedError, Equatable {
    case missingEncryptedContainer
    case missingKeyForEncryptedContainer
    case encryptedContainerTooLarge(maximumBytes: Int)
    case initialSetupRollbackFailed

    var errorDescription: String? {
        switch self {
        case .missingEncryptedContainer:
            return "The encrypted Vault container is missing while its Keychain key still exists. Restore a Vault backup rather than creating an empty replacement."
        case .missingKeyForEncryptedContainer:
            return "An encrypted Vault already exists, but its Keychain key is missing. Import an encrypted backup rather than replacing the existing Vault."
        case .encryptedContainerTooLarge(let maximumBytes):
            let limit = ByteCountFormatter.string(fromByteCount: Int64(maximumBytes), countStyle: .file)
            return "The encrypted Vault is larger than Clasp's \(limit) safety limit. Restore a smaller Vault backup."
        case .initialSetupRollbackFailed:
            return "Clasp could not finish the first Vault container or safely roll back its new Keychain key. No existing key was deleted."
        }
    }
}

actor VaultStore: VaultStoring {
    private let directory: URL
    private let containerURL: URL
    private let backupURL: URL
    private let keyProvider: any VaultKeyProviding
    private let writer: any AtomicFileWriting
    private let fileManager: FileManager
    private let containerMaximumBytes: Int
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        directory: URL = AppPaths.vaultDirectory,
        keyProvider: any VaultKeyProviding = KeychainVaultKeyProvider(),
        writer: any AtomicFileWriting = SystemAtomicFileWriter(),
        fileManager: FileManager = .default,
        containerMaximumBytes: Int = CappedFileReader.vaultImportMaximumBytes
    ) {
        self.directory = directory
        containerURL = directory.appendingPathComponent("vault.pnvault")
        backupURL = directory.appendingPathComponent("vault.previous.pnvault")
        self.keyProvider = keyProvider
        self.writer = writer
        self.fileManager = fileManager
        self.containerMaximumBytes = containerMaximumBytes
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    func isConfigured() -> Bool {
        keyProvider.hasKey() && fileManager.fileExists(atPath: containerURL.path)
    }

    func setup() async throws -> [Note] {
        try ensureDirectory()
        if fileManager.fileExists(atPath: containerURL.path) {
            guard keyProvider.hasKey() else { throw VaultStoreError.missingKeyForEncryptedContainer }
            throw KeychainKeyError.duplicate
        }
        let key = try await keyProvider.createKey(reason: "Create your Clasp Vault")
        do {
            try persist([], key: key)
        } catch let persistenceError {
            do {
                try keyProvider.deleteKeyIfMatching(key)
            } catch {
                throw VaultStoreError.initialSetupRollbackFailed
            }
            throw persistenceError
        }
        keyProvider.commitKeyCreation(key)
        return []
    }

    func unlock() async throws -> [Note] {
        guard fileManager.fileExists(atPath: containerURL.path) else {
            guard !keyProvider.hasKey() else { throw VaultStoreError.missingEncryptedContainer }
            return try await setup()
        }
        let key = try await keyProvider.unlock(reason: "Unlock your Clasp Vault")
        let data: Data
        do {
            data = try CappedFileReader.read(containerURL, maximumBytes: containerMaximumBytes)
        } catch is CappedFileReadError {
            throw VaultStoreError.encryptedContainerTooLarge(maximumBytes: containerMaximumBytes)
        }
        return try decodeContainer(data, key: key).notes
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ notes: [Note]) throws {
        guard let key = keyProvider.cachedKey() else { throw KeychainKeyError.cancelled }
        try persist(notes, key: key)
    }

    func lock() {
        keyProvider.lock()
    }

    func export(notes: [Note]) throws -> (data: Data, recoveryKey: RecoveryKey) {
        let recoveryKey = RecoveryKey()
        let plaintext = try encoder.encode(VaultPayload(notes: notes))
        let export = VaultExport(ciphertext: try VaultCrypto.encrypt(plaintext, using: recoveryKey.symmetricKey))
        return (try encoder.encode(export), recoveryKey)
    }

    func importVault(_ data: Data, recoveryKey: RecoveryKey) async throws -> [Note] {
        guard data.count <= CappedFileReader.vaultImportMaximumBytes else {
            throw CappedFileReadError.exceedsMaximumSize(
                maximumBytes: CappedFileReader.vaultImportMaximumBytes
            )
        }
        let envelope: VaultExport
        do { envelope = try decoder.decode(VaultExport.self, from: data) }
        catch { throw VaultCryptoError.malformedContainer }
        guard envelope.formatVersion == VaultExport.currentVersion else {
            throw VaultCryptoError.unsupportedVersion
        }
        let plaintext = try VaultCrypto.decrypt(envelope.ciphertext, using: recoveryKey.symmetricKey)
        let payload: VaultPayload
        do { payload = try decoder.decode(VaultPayload.self, from: plaintext) }
        catch { throw VaultCryptoError.malformedContainer }

        try ensureDirectory()
        if fileManager.fileExists(atPath: containerURL.path) {
            if fileManager.fileExists(atPath: backupURL.path) { try fileManager.removeItem(at: backupURL) }
            try fileManager.copyItem(at: containerURL, to: backupURL)
        }
        let key: SymmetricKey
        if let cached = keyProvider.cachedKey() {
            key = cached
        } else if !keyProvider.hasKey() {
            key = try await keyProvider.createKey(reason: "Create a local key for your imported Clasp Vault")
        } else {
            key = try await keyProvider.unlock(reason: "Authenticate to import into your Vault")
        }
        try persist(payload.notes, key: key)
        return payload.notes.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func persist(_ notes: [Note], key: SymmetricKey) throws {
        try ensureDirectory()
        let plaintext = try encoder.encode(VaultPayload(notes: notes))
        let envelope = EncryptedContainer(ciphertext: try VaultCrypto.encrypt(plaintext, using: key))
        try writer.write(try encoder.encode(envelope), to: containerURL)
    }

    private func decodeContainer(_ data: Data, key: SymmetricKey) throws -> VaultPayload {
        let envelope: EncryptedContainer
        do { envelope = try decoder.decode(EncryptedContainer.self, from: data) }
        catch { throw VaultCryptoError.malformedContainer }
        guard envelope.formatVersion == EncryptedContainer.currentVersion else {
            throw VaultCryptoError.unsupportedVersion
        }
        let plaintext = try VaultCrypto.decrypt(envelope.ciphertext, using: key)
        do { return try decoder.decode(VaultPayload.self, from: plaintext) }
        catch { throw VaultCryptoError.malformedContainer }
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
