import CryptoKit
import Foundation

enum VaultCryptoError: Error, LocalizedError, Equatable {
    case invalidKey
    case malformedContainer
    case unsupportedVersion
    case authenticationFailed

    var errorDescription: String? {
        switch self {
        case .invalidKey: "The recovery key is invalid."
        case .malformedContainer: "The Vault file is malformed or damaged."
        case .unsupportedVersion: "This Vault format is not supported by this version of Clasp."
        case .authenticationFailed: "The Vault could not be authenticated. It may be damaged or the key may be wrong."
        }
    }
}

struct EncryptedContainer: Codable, Equatable, Sendable {
    static let currentVersion = 1
    var formatVersion: Int = Self.currentVersion
    var ciphertext: Data
}

struct VaultPayload: Codable, Equatable, Sendable {
    var notes: [Note]
}

enum VaultCrypto {
    static func generateKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    static func encrypt(_ plaintext: Data, using key: SymmetricKey) throws -> Data {
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw VaultCryptoError.malformedContainer }
        return combined
    }

    static func decrypt(_ ciphertext: Data, using key: SymmetricKey) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw VaultCryptoError.authenticationFailed
        }
    }

    static func keyData(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    static func key(from data: Data) throws -> SymmetricKey {
        guard data.count == 32 else { throw VaultCryptoError.invalidKey }
        return SymmetricKey(data: data)
    }
}

struct RecoveryKey: Equatable, Sendable {
    let rawData: Data

    init() {
        rawData = VaultCrypto.keyData(VaultCrypto.generateKey())
    }

    init(encoded: String) throws {
        var base64 = encoded.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count.isMultiple(of: 4) == false { base64 += "=" }
        guard let data = Data(base64Encoded: base64), data.count == 32 else {
            throw VaultCryptoError.invalidKey
        }
        rawData = data
    }

    var encoded: String {
        rawData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    var symmetricKey: SymmetricKey { SymmetricKey(data: rawData) }
}

struct VaultExport: Codable, Equatable, Sendable {
    static let currentVersion = 1
    var formatVersion: Int = Self.currentVersion
    var ciphertext: Data
}
