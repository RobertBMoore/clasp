import Foundation

enum CappedFileReadError: Error, LocalizedError, Equatable {
    case exceedsMaximumSize(maximumBytes: Int)

    var errorDescription: String? {
        switch self {
        case .exceedsMaximumSize(let maximumBytes):
            let limit = ByteCountFormatter.string(fromByteCount: Int64(maximumBytes), countStyle: .file)
            return "That Vault backup is larger than Clasp's \(limit) import limit."
        }
    }
}

enum CappedFileReader {
    /// Vault exports may contain many encrypted image notes, but a single import
    /// is capped at 512 MiB to keep decode memory bounded.
    static let vaultImportMaximumBytes = 512 * 1_024 * 1_024
    private static let readChunkBytes = 64 * 1_024

    static func read(_ url: URL, maximumBytes: Int) throws -> Data {
        guard maximumBytes >= 0, maximumBytes < Int.max else {
            throw CappedFileReadError.exceedsMaximumSize(maximumBytes: max(0, maximumBytes))
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let detectionLimit = maximumBytes + 1
        var result = Data()
        while result.count < detectionLimit {
            let count = min(readChunkBytes, detectionLimit - result.count)
            guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else { break }
            result.append(chunk)
        }
        guard result.count <= maximumBytes else {
            throw CappedFileReadError.exceedsMaximumSize(maximumBytes: maximumBytes)
        }
        return result
    }
}
