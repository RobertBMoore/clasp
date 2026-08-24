import CryptoKit
import Foundation
import Security
import XCTest
@testable import PersonalNotepad

final class VaultCryptoTests: XCTestCase {
    func testAESRoundTripAndFreshNonces() throws {
        let key = VaultCrypto.generateKey()
        let plaintext = Data("SENSITIVE-BODY".utf8)
        let first = try VaultCrypto.encrypt(plaintext, using: key)
        let second = try VaultCrypto.encrypt(plaintext, using: key)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try VaultCrypto.decrypt(first, using: key), plaintext)
        XCTAssertEqual(try VaultCrypto.decrypt(second, using: key), plaintext)
    }

    func testTamperAndWrongKeyFailWithoutPlaintext() throws {
        let plaintext = Data("NEVER-RETURN-PARTIAL".utf8)
        let key = VaultCrypto.generateKey()
        var encrypted = try VaultCrypto.encrypt(plaintext, using: key)
        encrypted[encrypted.index(before: encrypted.endIndex)] ^= 0x01
        XCTAssertThrowsError(try VaultCrypto.decrypt(encrypted, using: key))

        let valid = try VaultCrypto.encrypt(plaintext, using: key)
        XCTAssertThrowsError(try VaultCrypto.decrypt(valid, using: VaultCrypto.generateKey()))
        XCTAssertFalse(String(decoding: encrypted, as: UTF8.self).contains("NEVER-RETURN-PARTIAL"))
    }

    func testVaultContainerAndExportContainNoSecretPlaintext() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let keyProvider = MemoryKeyProvider()
        let store = VaultStore(directory: root, keyProvider: keyProvider)
        _ = try await store.setup()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let secretImage = Data("SECRET-IMAGE-BYTES-608".utf8)
        let secret = Note(
            title: "SECRET-TITLE-731",
            body: "SECRET-BODY-924",
            tags: ["secret-tag-185"],
            createdAt: timestamp,
            updatedAt: timestamp,
            contentType: .image,
            attachments: [NoteAttachment(data: secretImage)],
            extractedText: "SECRET-OCR-TEXT-447"
        )
        try await store.save([secret])

        let container = try Data(contentsOf: root.appendingPathComponent("vault.pnvault"))
        let containerText = String(decoding: container, as: UTF8.self)
        XCTAssertFalse(containerText.contains("SECRET-TITLE-731"))
        XCTAssertFalse(containerText.contains("SECRET-BODY-924"))
        XCTAssertFalse(containerText.contains("secret-tag-185"))
        XCTAssertFalse(containerText.contains("SECRET-IMAGE-BYTES-608"))
        XCTAssertFalse(containerText.contains("SECRET-OCR-TEXT-447"))

        let exported = try await store.export(notes: [secret])
        let exportText = String(decoding: exported.data, as: UTF8.self)
        XCTAssertFalse(exportText.contains("SECRET-TITLE-731"))
        XCTAssertFalse(exportText.contains("SECRET-BODY-924"))
        XCTAssertFalse(exportText.contains("secret-tag-185"))
        XCTAssertFalse(exportText.contains("SECRET-IMAGE-BYTES-608"))
        XCTAssertFalse(exportText.contains("SECRET-OCR-TEXT-447"))

        try await store.save([])
        let imported = try await store.importVault(exported.data, recoveryKey: exported.recoveryKey)
        XCTAssertEqual(imported, [secret])
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("vault.previous.pnvault").path))
    }

    func testMissingContainerDoesNotSilentlyReplaceExistingKey() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let keyProvider = MemoryKeyProvider()
        _ = try await keyProvider.createKey(reason: "Test")
        let store = VaultStore(directory: root, keyProvider: keyProvider)

        do {
            _ = try await store.unlock()
            XCTFail("Expected a missing-container error")
        } catch {
            XCTAssertEqual(error as? VaultStoreError, .missingEncryptedContainer)
        }
    }

    func testSetupDoesNotReplaceExistingContainerWhenKeyIsMissing() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let originalStore = VaultStore(directory: root, keyProvider: MemoryKeyProvider())
        _ = try await originalStore.setup()
        try await originalStore.save([Note(title: "Preserve me", body: "Encrypted content")])
        let containerURL = root.appendingPathComponent("vault.pnvault")
        let originalContainer = try Data(contentsOf: containerURL)

        let storeWithMissingKey = VaultStore(directory: root, keyProvider: MemoryKeyProvider())
        do {
            _ = try await storeWithMissingKey.setup()
            XCTFail("Setup must not replace an existing encrypted container")
        } catch {}

        XCTAssertEqual(try Data(contentsOf: containerURL), originalContainer)
    }

    func testInitialSetupWriteFailureRollsBackOnlyItsNewKeyAndAllowsRetry() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let keyProvider = MemoryKeyProvider()
        let interruptedStore = VaultStore(
            directory: root,
            keyProvider: keyProvider,
            writer: VaultFailingAtomicWriter()
        )

        do {
            _ = try await interruptedStore.setup()
            XCTFail("Expected the injected initial container write failure")
        } catch {
            XCTAssertTrue(error is AtomicWriteFailure)
        }

        XCTAssertEqual(keyProvider.rollbackAttempts, 1)
        XCTAssertFalse(keyProvider.hasKey())
        XCTAssertNil(keyProvider.cachedKey())
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("vault.pnvault").path))

        let retryStore = VaultStore(directory: root, keyProvider: keyProvider)
        let retriedNotes = try await retryStore.setup()
        XCTAssertEqual(retriedNotes, [])
        XCTAssertTrue(keyProvider.hasKey())
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("vault.pnvault").path))
    }

    func testSetupRollbackRefusesToDeleteAReplacementKey() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let keyProvider = MemoryKeyProvider()
        let writer = VaultFailingAtomicWriter {
            keyProvider.replaceStoredKeyForTesting()
        }
        let store = VaultStore(directory: root, keyProvider: keyProvider, writer: writer)

        do {
            _ = try await store.setup()
            XCTFail("Expected setup rollback to fail closed after key replacement")
        } catch {
            XCTAssertEqual(error as? VaultStoreError, .initialSetupRollbackFailed)
        }

        XCTAssertEqual(keyProvider.rollbackAttempts, 1)
        XCTAssertTrue(keyProvider.hasKey(), "The replacement key must remain untouched")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("vault.pnvault").path))
    }

    func testMacOSPersistentReferenceRollbackQueriesUseMatchItemList() {
        let persistentReference = Data("test-persistent-reference".utf8)
        let readQuery = KeychainVaultRollbackQuery.read(
            persistentReference: persistentReference
        )
        let deleteQuery = KeychainVaultRollbackQuery.delete(
            persistentReference: persistentReference
        )

        XCTAssertEqual(
            readQuery[kSecMatchItemList as String] as? [Data],
            [persistentReference]
        )
        XCTAssertEqual(readQuery[kSecReturnData as String] as? Bool, true)
        XCTAssertNil(readQuery[kSecValuePersistentRef as String])
        XCTAssertEqual(
            deleteQuery[kSecMatchItemList as String] as? [Data],
            [persistentReference]
        )
        XCTAssertNil(deleteQuery[kSecValuePersistentRef as String])
    }

    func testUnlockRejectsLiveContainerAtMaximumPlusOne() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([0, 1, 2, 3, 4]).write(to: root.appendingPathComponent("vault.pnvault"))
        let keyProvider = MemoryKeyProvider()
        _ = try await keyProvider.createKey(reason: "Test")
        let store = VaultStore(
            directory: root,
            keyProvider: keyProvider,
            containerMaximumBytes: 4
        )

        do {
            _ = try await store.unlock()
            XCTFail("Expected the live Vault container budget to reject max + 1")
        } catch {
            XCTAssertEqual(
                error as? VaultStoreError,
                .encryptedContainerTooLarge(maximumBytes: 4)
            )
        }
    }

    func testEncryptedExportImportsWithFreshLocalKeyOnNewInstallation() async throws {
        let sourceRoot = temporaryDirectory()
        let destinationRoot = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: destinationRoot)
        }
        let source = VaultStore(directory: sourceRoot, keyProvider: MemoryKeyProvider())
        _ = try await source.setup()
        let note = Note(title: "Recovered", body: "Encrypted recovery payload")
        let exported = try await source.export(notes: [note])

        let freshProvider = MemoryKeyProvider()
        let destination = VaultStore(directory: destinationRoot, keyProvider: freshProvider)
        let imported = try await destination.importVault(exported.data, recoveryKey: exported.recoveryKey)

        XCTAssertEqual(imported.map(\.id), [note.id])
        XCTAssertTrue(freshProvider.hasKey())
        await destination.lock()
        let unlocked = try await destination.unlock()
        XCTAssertEqual(unlocked.map(\.id), [note.id])
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

final class MemoryKeyProvider: @unchecked Sendable, VaultKeyProviding {
    private let lockState = NSLock()
    private var stored: SymmetricKey?
    private var memory: SymmetricKey?
    private var rollbackAttemptCount = 0

    var rollbackAttempts: Int { lockState.withLock { rollbackAttemptCount } }

    func hasKey() -> Bool { lockState.withLock { stored != nil } }
    func createKey(reason: String) async throws -> SymmetricKey {
        try lockState.withLock {
            if stored != nil { throw KeychainKeyError.duplicate }
            let key = VaultCrypto.generateKey()
            stored = key
            memory = key
            return key
        }
    }
    func deleteKeyIfMatching(_ key: SymmetricKey) throws {
        let expectedData = VaultCrypto.keyData(key)
        try lockState.withLock {
            rollbackAttemptCount += 1
            guard let stored else {
                if let memory, VaultCrypto.keyData(memory) == expectedData { self.memory = nil }
                return
            }
            guard VaultCrypto.keyData(stored) == expectedData else {
                throw KeychainKeyError.rollbackKeyMismatch
            }
            self.stored = nil
            if let memory, VaultCrypto.keyData(memory) == expectedData { self.memory = nil }
        }
    }
    func unlock(reason: String) async throws -> SymmetricKey {
        try lockState.withLock {
            guard let stored else { throw KeychainKeyError.notFound }
            memory = stored
            return stored
        }
    }
    func cachedKey() -> SymmetricKey? { lockState.withLock { memory } }
    func lock() { lockState.withLock { memory = nil } }

    func replaceStoredKeyForTesting() {
        lockState.withLock {
            let replacement = VaultCrypto.generateKey()
            stored = replacement
            memory = replacement
        }
    }
}

private final class VaultFailingAtomicWriter: @unchecked Sendable, AtomicFileWriting {
    private let beforeFailure: @Sendable () -> Void

    init(beforeFailure: @escaping @Sendable () -> Void = {}) {
        self.beforeFailure = beforeFailure
    }

    func write(_ data: Data, to url: URL) throws {
        beforeFailure()
        throw AtomicWriteFailure()
    }
}
