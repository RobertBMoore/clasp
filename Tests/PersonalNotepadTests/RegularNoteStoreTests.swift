import Foundation
import XCTest
@testable import PersonalNotepad

final class RegularNoteStoreTests: XCTestCase {
    func testMarkdownRoundTripAndIndexRebuild() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RegularNoteStore(baseDirectory: root)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let note = Note(title: "Manual title", body: "# Markdown\n\n[OpenAI](https://openai.com)", tags: ["reference"], isPinned: true, createdAt: timestamp, updatedAt: timestamp)

        try await store.save(note)
        let loaded = try await store.load()
        XCTAssertEqual(loaded, [note])

        let notesDirectory = root.appendingPathComponent("Notes")
        try FileManager.default.removeItem(at: notesDirectory.appendingPathComponent("index.json"))
        let rebuilt = try await store.load()
        XCTAssertEqual(rebuilt.count, 1)
        XCTAssertEqual(rebuilt[0], note)
    }

    func testPermanentDeleteRemovesMarkdownAndIndexEntry() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RegularNoteStore(baseDirectory: root)
        let note = Note(body: "Disposable")
        try await store.save(note)
        try await store.permanentlyDelete(id: note.id)
        let remaining = try await store.load()
        XCTAssertTrue(remaining.isEmpty)
        let markdown = root.appendingPathComponent("Notes/\(note.id.uuidString.lowercased()).md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: markdown.path))
    }

    func testStoreUsesAtomicWriterBoundaryAndPropagatesFailure() async {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = FailingAtomicWriter()
        let store = RegularNoteStore(baseDirectory: root, writer: writer)
        do {
            try await store.save(Note(body: "Must not partially persist"))
            XCTFail("Expected atomic writer failure")
        } catch {
            XCTAssertTrue(error is AtomicWriteFailure)
        }
        XCTAssertGreaterThan(writer.calls, 0)
    }

    func testInterruptedIndexWriteRecoversBodyAndMetadataFromSidecar() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = FailOnCallAtomicWriter(failingCall: 4)
        let interruptedStore = RegularNoteStore(baseDirectory: root, writer: writer)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let note = Note(title: "Preserved title", body: "Body survives", tags: ["important"], isPinned: true, createdAt: timestamp, updatedAt: timestamp)

        do {
            try await interruptedStore.save(note)
            XCTFail("Expected the simulated index write interruption")
        } catch {
            XCTAssertTrue(error is AtomicWriteFailure)
        }

        let recoveredStore = RegularNoteStore(baseDirectory: root)
        let recovered = try await recoveredStore.load()
        XCTAssertEqual(recovered, [note])
    }

    func testImageAttachmentRoundTripsOutsideMarkdownAndIsRemovedWithNote() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RegularNoteStore(baseDirectory: root)
        let imageBytes = Data("BINARY-IMAGE-CONTENT".utf8)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let note = Note(
            title: "Clipped diagram",
            tags: ["image", "diagram"],
            createdAt: timestamp,
            updatedAt: timestamp,
            contentType: .image,
            attachments: [NoteAttachment(data: imageBytes)],
            extractedText: "Architecture diagram"
        )

        try await store.save(note)
        let loaded = try await store.load()
        XCTAssertEqual(loaded, [note])

        let notesDirectory = root.appendingPathComponent("Notes")
        let markdown = try Data(contentsOf: notesDirectory.appendingPathComponent("\(note.id.uuidString.lowercased()).md"))
        let index = try Data(contentsOf: notesDirectory.appendingPathComponent("index.json"))
        XCTAssertFalse(markdown.range(of: imageBytes) != nil)
        XCTAssertFalse(index.range(of: imageBytes) != nil)

        try await store.permanentlyDelete(id: note.id)
        let attachmentDirectory = notesDirectory.appendingPathComponent("Attachments/\(note.id.uuidString.lowercased())")
        XCTAssertFalse(FileManager.default.fileExists(atPath: attachmentDirectory.path))
    }

    func testPermanentDeleteBodyMoveFailureRestoresEveryArtifactAndIndex() async throws {
        try await assertPermanentDeleteMoveFailureRollsBack(.markdownBody)
    }

    func testPermanentDeleteSidecarMoveFailureRestoresEveryArtifactAndIndex() async throws {
        try await assertPermanentDeleteMoveFailureRollsBack(.metadataSidecar)
    }

    func testPermanentDeleteAttachmentMoveFailureRestoresEveryArtifactAndIndex() async throws {
        try await assertPermanentDeleteMoveFailureRollsBack(.attachments)
    }

    func testPermanentDeleteIndexWriteFailureRestoresEveryArtifactAndOriginalIndex() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = FailNextAtomicWriter()
        let store = RegularNoteStore(baseDirectory: root, writer: writer)
        let fixture = try await makeDeletionFixture(in: store, root: root)
        writer.failNextWrite()

        do {
            try await store.permanentlyDelete(id: fixture.note.id)
            XCTFail("Expected the injected index write failure")
        } catch {
            XCTAssertTrue(error is AtomicWriteFailure)
        }

        try await assertDeletionFixtureWasRestored(fixture, by: store)
    }

    func testSaveRejectsSubstitutedAttachmentDirectoryWithoutDeletingTargetFiles() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileManager = FileManager.default
        let store = RegularNoteStore(baseDirectory: root)
        let note = Note(
            body: "Original image",
            contentType: .image,
            attachments: [NoteAttachment(data: Data("ORIGINAL".utf8))]
        )
        try await store.save(note)

        let attachmentDirectory = root
            .appendingPathComponent("Notes/Attachments", isDirectory: true)
            .appendingPathComponent(note.id.uuidString.lowercased(), isDirectory: true)
        let targetDirectory = root.appendingPathComponent("unrelated-user-files", isDirectory: true)
        let targetFile = targetDirectory.appendingPathComponent("keep.txt")
        try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        try Data("DO NOT DELETE".utf8).write(to: targetFile)
        try fileManager.removeItem(at: attachmentDirectory)
        try fileManager.createSymbolicLink(at: attachmentDirectory, withDestinationURL: targetDirectory)

        var updated = note
        updated.attachments = [NoteAttachment(data: Data("REPLACEMENT".utf8))]
        do {
            try await store.save(updated)
            XCTFail("Expected the substituted attachment directory to be rejected")
        } catch {
            XCTAssertEqual(error as? RegularNoteStoreError, .unsafeAttachmentDirectory)
        }

        XCTAssertEqual(try Data(contentsOf: targetFile), Data("DO NOT DELETE".utf8))
    }

    func testOversizedIndexRebuildsFromBoundedMarkdownAndSidecarFiles() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let note = Note(
            title: "Recovered title",
            body: "Recovered body",
            tags: ["bounded"],
            createdAt: timestamp,
            updatedAt: timestamp
        )
        try await RegularNoteStore(baseDirectory: root).save(note)

        let indexURL = root.appendingPathComponent("Notes/index.json")
        let canonicalIndex = try Data(contentsOf: indexURL)
        var oversizedIndex = canonicalIndex
        oversizedIndex.append(0x20)
        try oversizedIndex.write(to: indexURL)
        var budget = RegularNoteStoreResourceBudget.standard
        budget.maximumIndexBytes = canonicalIndex.count

        let boundedStore = RegularNoteStore(baseDirectory: root, resourceBudget: budget)
        let recovered = try await boundedStore.load()
        XCTAssertEqual(recovered, [note])
        XCTAssertEqual(try Data(contentsOf: indexURL), canonicalIndex)
    }

    func testOversizedMarkdownBodyFailsClosedWithoutRewritingTheFile() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let note = Note(body: "safe")
        try await RegularNoteStore(baseDirectory: root).save(note)

        let bodyURL = root.appendingPathComponent("Notes/\(note.id.uuidString.lowercased()).md")
        let oversizedBody = Data("12345".utf8)
        try oversizedBody.write(to: bodyURL)
        var budget = RegularNoteStoreResourceBudget.standard
        budget.maximumMarkdownBodyBytes = oversizedBody.count - 1
        let boundedStore = RegularNoteStore(baseDirectory: root, resourceBudget: budget)

        do {
            _ = try await boundedStore.load()
            XCTFail("Expected the oversized Markdown body to fail closed")
        } catch {
            XCTAssertEqual(
                error as? RegularNoteStoreError,
                .artifactTooLarge(kind: .markdownBody, maximumBytes: oversizedBody.count - 1)
            )
        }
        XCTAssertEqual(try Data(contentsOf: bodyURL), oversizedBody)
    }

    func testOversizedMetadataSidecarFallsBackToMarkdownWithoutRewritingSidecar() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let note = Note(title: "Sidecar title", body: "Markdown survives", tags: ["sidecar"])
        try await RegularNoteStore(baseDirectory: root).save(note)

        let notesDirectory = root.appendingPathComponent("Notes")
        let sidecarURL = notesDirectory.appendingPathComponent("\(note.id.uuidString.lowercased()).metadata.json")
        let indexURL = notesDirectory.appendingPathComponent("index.json")
        let canonicalSidecar = try Data(contentsOf: sidecarURL)
        var oversizedSidecar = canonicalSidecar
        oversizedSidecar.append(0x20)
        try oversizedSidecar.write(to: sidecarURL)
        try FileManager.default.removeItem(at: indexURL)
        var budget = RegularNoteStoreResourceBudget.standard
        budget.maximumMetadataSidecarBytes = canonicalSidecar.count

        let boundedStore = RegularNoteStore(baseDirectory: root, resourceBudget: budget)
        let recovered = try await boundedStore.load()
        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered[0].id, note.id)
        XCTAssertEqual(recovered[0].body, note.body)
        XCTAssertEqual(recovered[0].title, "")
        XCTAssertEqual(recovered[0].tags, [])
        XCTAssertEqual(try Data(contentsOf: sidecarURL), oversizedSidecar)
    }

    func testOversizedAttachmentFailsClosedWithoutRewritingTheFile() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let attachment = NoteAttachment(data: Data("safe".utf8))
        let note = Note(
            body: "Image note",
            contentType: .image,
            attachments: [attachment]
        )
        try await RegularNoteStore(baseDirectory: root).save(note)

        let attachmentURL = root
            .appendingPathComponent("Notes/Attachments/\(note.id.uuidString.lowercased())", isDirectory: true)
            .appendingPathComponent("\(attachment.id.uuidString.lowercased()).png")
        let oversizedAttachment = Data("12345".utf8)
        try oversizedAttachment.write(to: attachmentURL)
        var budget = RegularNoteStoreResourceBudget.standard
        budget.maximumAttachmentBytes = oversizedAttachment.count - 1
        let boundedStore = RegularNoteStore(baseDirectory: root, resourceBudget: budget)

        do {
            _ = try await boundedStore.load()
            XCTFail("Expected the oversized attachment to fail closed")
        } catch {
            XCTAssertEqual(
                error as? RegularNoteStoreError,
                .artifactTooLarge(kind: .attachment, maximumBytes: oversizedAttachment.count - 1)
            )
        }
        XCTAssertEqual(try Data(contentsOf: attachmentURL), oversizedAttachment)
    }

    private func assertPermanentDeleteMoveFailureRollsBack(
        _ target: InjectedDeletionMoveTarget
    ) async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileOperator = FailOnceDeletionFileOperator(target: target)
        let store = RegularNoteStore(
            baseDirectory: root,
            deletionFileOperator: fileOperator
        )
        let fixture = try await makeDeletionFixture(in: store, root: root)

        do {
            try await store.permanentlyDelete(id: fixture.note.id)
            XCTFail("Expected the injected \(target) move failure")
        } catch {
            XCTAssertTrue(error is InjectedDeletionMoveFailure)
        }

        try await assertDeletionFixtureWasRestored(fixture, by: store)
    }

    private func makeDeletionFixture(
        in store: RegularNoteStore,
        root: URL
    ) async throws -> DeletionFixture {
        let attachment = NoteAttachment(
            id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
            data: Data("TRANSACTIONAL-ATTACHMENT".utf8)
        )
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let note = Note(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            title: "Recoverable deletion",
            body: "The body must survive an interrupted permanent delete.",
            tags: ["transaction"],
            isPinned: true,
            createdAt: timestamp,
            updatedAt: timestamp,
            contentType: .image,
            attachments: [attachment],
            extractedText: "Recovery fixture"
        )
        try await store.save(note)

        let notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        let bodyURL = notesDirectory.appendingPathComponent("\(note.id.uuidString.lowercased()).md")
        let sidecarURL = notesDirectory.appendingPathComponent("\(note.id.uuidString.lowercased()).metadata.json")
        let attachmentDirectory = notesDirectory
            .appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent(note.id.uuidString.lowercased(), isDirectory: true)
        let attachmentURL = attachmentDirectory
            .appendingPathComponent(attachment.id.uuidString.lowercased())
            .appendingPathExtension("png")
        let indexURL = notesDirectory.appendingPathComponent("index.json")

        return DeletionFixture(
            note: note,
            notesDirectory: notesDirectory,
            bodyURL: bodyURL,
            bodyData: try Data(contentsOf: bodyURL),
            sidecarURL: sidecarURL,
            sidecarData: try Data(contentsOf: sidecarURL),
            attachmentDirectory: attachmentDirectory,
            attachmentURL: attachmentURL,
            attachmentData: try Data(contentsOf: attachmentURL),
            indexURL: indexURL,
            indexData: try Data(contentsOf: indexURL)
        )
    }

    private func assertDeletionFixtureWasRestored(
        _ fixture: DeletionFixture,
        by store: RegularNoteStore
    ) async throws {
        XCTAssertEqual(try Data(contentsOf: fixture.bodyURL), fixture.bodyData)
        XCTAssertEqual(try Data(contentsOf: fixture.sidecarURL), fixture.sidecarData)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.attachmentDirectory.path))
        XCTAssertEqual(try Data(contentsOf: fixture.attachmentURL), fixture.attachmentData)
        XCTAssertEqual(try Data(contentsOf: fixture.indexURL), fixture.indexData)

        let quarantineResidue = try FileManager.default.contentsOfDirectory(
            at: fixture.notesDirectory,
            includingPropertiesForKeys: nil,
            options: []
        ).filter { $0.lastPathComponent.hasPrefix(".clasp-delete-transaction-") }
        XCTAssertTrue(quarantineResidue.isEmpty)

        let loaded = try await store.load()
        XCTAssertEqual(loaded, [fixture.note])
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

private struct DeletionFixture {
    var note: Note
    var notesDirectory: URL
    var bodyURL: URL
    var bodyData: Data
    var sidecarURL: URL
    var sidecarData: Data
    var attachmentDirectory: URL
    var attachmentURL: URL
    var attachmentData: Data
    var indexURL: URL
    var indexData: Data
}

private enum InjectedDeletionMoveTarget: CustomStringConvertible {
    case markdownBody
    case metadataSidecar
    case attachments

    var description: String {
        switch self {
        case .markdownBody: "Markdown body"
        case .metadataSidecar: "metadata sidecar"
        case .attachments: "attachment directory"
        }
    }

    func matches(_ sourceURL: URL) -> Bool {
        switch self {
        case .markdownBody:
            sourceURL.pathExtension == "md"
        case .metadataSidecar:
            sourceURL.lastPathComponent.hasSuffix(".metadata.json")
        case .attachments:
            sourceURL.deletingLastPathComponent().lastPathComponent == "Attachments"
        }
    }
}

private struct InjectedDeletionMoveFailure: Error {}

private final class FailOnceDeletionFileOperator: @unchecked Sendable, RegularNoteDeletionFileOperating {
    private let lock = NSLock()
    private let target: InjectedDeletionMoveTarget
    private var hasFailed = false
    private let fileManager = FileManager.default

    init(target: InjectedDeletionMoveTarget) {
        self.target = target
    }

    func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        let shouldFail = lock.withLock {
            guard !hasFailed, target.matches(sourceURL) else { return false }
            hasFailed = true
            return true
        }
        if shouldFail { throw InjectedDeletionMoveFailure() }
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
    }

    func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }
}

private final class FailNextAtomicWriter: @unchecked Sendable, AtomicFileWriting {
    private let lock = NSLock()
    private var shouldFailNextWrite = false
    private let underlying = SystemAtomicFileWriter()

    func failNextWrite() {
        lock.withLock { shouldFailNextWrite = true }
    }

    func write(_ data: Data, to url: URL) throws {
        let shouldFail = lock.withLock {
            defer { shouldFailNextWrite = false }
            return shouldFailNextWrite
        }
        if shouldFail { throw AtomicWriteFailure() }
        try underlying.write(data, to: url)
    }
}

private final class FailOnCallAtomicWriter: @unchecked Sendable, AtomicFileWriting {
    private let lock = NSLock()
    private let failingCall: Int
    private var calls = 0
    private let underlying = SystemAtomicFileWriter()

    init(failingCall: Int) { self.failingCall = failingCall }

    func write(_ data: Data, to url: URL) throws {
        let shouldFail = lock.withLock {
            calls += 1
            return calls == failingCall
        }
        if shouldFail { throw AtomicWriteFailure() }
        try underlying.write(data, to: url)
    }
}

private final class FailingAtomicWriter: @unchecked Sendable, AtomicFileWriting {
    private let lock = NSLock()
    private var storage = 0
    var calls: Int { lock.withLock { storage } }
    func write(_ data: Data, to url: URL) throws {
        lock.withLock { storage += 1 }
        throw AtomicWriteFailure()
    }
}
