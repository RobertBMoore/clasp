import Foundation

protocol AtomicFileWriting: Sendable {
    func write(_ data: Data, to url: URL) throws
}

struct SystemAtomicFileWriter: AtomicFileWriting {
    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}

struct AtomicWriteFailure: Error, LocalizedError {
    var errorDescription: String? { "The atomic save could not be completed." }
}
