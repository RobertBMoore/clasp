#!/usr/bin/env swift

import CryptoKit
import Darwin
import Foundation

enum VerificationFailure: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case let .message(message): message
        }
    }
}

func decodeBase64(_ value: String, byteCount: Int, label: String) throws -> Data {
    guard let data = Data(base64Encoded: value), data.count == byteCount else {
        throw VerificationFailure.message("\(label) is not exactly \(byteCount) base64-decoded bytes")
    }
    return data
}

func verifier(publicKeyBase64: String) throws -> Curve25519.Signing.PublicKey {
    let rawKey = try decodeBase64(publicKeyBase64, byteCount: 32, label: "public key")
    do {
        return try Curve25519.Signing.PublicKey(rawRepresentation: rawKey)
    } catch {
        throw VerificationFailure.message("public key is not a valid Ed25519 key")
    }
}

func verify(data: Data, signatureBase64: String, publicKeyBase64: String) throws {
    let signature = try decodeBase64(signatureBase64, byteCount: 64, label: "signature")
    let publicKey = try verifier(publicKeyBase64: publicKeyBase64)
    guard publicKey.isValidSignature(signature, for: data) else {
        throw VerificationFailure.message("Ed25519 signature does not match the supplied public key and content")
    }
}

func verifyFile(path: String, signatureBase64: String, publicKeyBase64: String) throws {
    let data = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
    try verify(data: data, signatureBase64: signatureBase64, publicKeyBase64: publicKeyBase64)
}

func verifySignedFeed(path: String, publicKeyBase64: String) throws {
    let feed = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
    let prefix = Data("<!-- sparkle-signatures:\n".utf8)
    let suffix = Data("-->".utf8)

    guard let firstPrefix = feed.range(of: prefix),
          let lastPrefix = feed.range(of: prefix, options: .backwards),
          firstPrefix == lastPrefix else {
        throw VerificationFailure.message("feed must contain exactly one Sparkle signature block")
    }
    guard let suffixRange = feed.range(of: suffix, in: firstPrefix.upperBound..<feed.endIndex) else {
        throw VerificationFailure.message("feed signature block is not terminated")
    }
    let trailingData = Data(feed[suffixRange.upperBound..<feed.endIndex])
    guard trailingData == Data("\n".utf8) else {
        throw VerificationFailure.message("feed signature block must be the final block")
    }

    let blockData = Data(feed[firstPrefix.upperBound..<suffixRange.lowerBound])
    guard let block = String(data: blockData, encoding: .utf8) else {
        throw VerificationFailure.message("feed signature block is not UTF-8")
    }
    let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
    guard lines.count == 3,
          lines[0].hasPrefix("edSignature: "),
          lines[1].hasPrefix("length: "),
          lines[2].isEmpty else {
        throw VerificationFailure.message("feed signature block has an unexpected format")
    }

    let signature = String(lines[0].dropFirst("edSignature: ".count))
    let lengthText = String(lines[1].dropFirst("length: ".count))
    guard let expectedLength = Int(lengthText), expectedLength >= 0 else {
        throw VerificationFailure.message("feed signature block length is invalid")
    }
    let content = Data(feed[feed.startIndex..<firstPrefix.lowerBound])
    guard content.count == expectedLength else {
        throw VerificationFailure.message("feed signed-content length does not match the signature block")
    }
    try verify(data: content, signatureBase64: signature, publicKeyBase64: publicKeyBase64)
}

do {
    let arguments = CommandLine.arguments
    switch arguments.dropFirst().first {
    case "--file" where arguments.count == 5:
        try verifyFile(path: arguments[2], signatureBase64: arguments[3], publicKeyBase64: arguments[4])
    case "--signed-feed" where arguments.count == 4:
        try verifySignedFeed(path: arguments[2], publicKeyBase64: arguments[3])
    default:
        throw VerificationFailure.message("usage: verify_sparkle_signature.swift --file FILE SIGNATURE PUBLIC_KEY | --signed-feed APPCAST PUBLIC_KEY")
    }
} catch {
    let message = "Sparkle signature verification failed: \(error)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}
