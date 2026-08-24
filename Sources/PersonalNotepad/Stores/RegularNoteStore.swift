import Foundation

protocol RegularNoteStoring: Sendable {
    func load() async throws -> [Note]
    func save(_ note: Note) async throws
    func permanentlyDelete(id: UUID) async throws
    func rebuildIndex() async throws -> [Note]
}

enum RegularNoteArtifactKind: String, Equatable, Sendable {
    case index
    case markdownBody
    case metadataSidecar
    case attachment

    var description: String {
        switch self {
        case .index: "index"
        case .markdownBody: "Markdown body"
        case .metadataSidecar: "metadata sidecar"
        case .attachment: "attachment"
        }
    }
}

struct RegularNoteStoreResourceBudget: Equatable, Sendable {
    /// Index metadata is compact, but 64 MiB still leaves room for roughly
    /// tens of thousands of ordinary notes without permitting an unbounded read.
    static let standard = Self(
        maximumIndexBytes: 64 * 1_024 * 1_024,
        // Twice the direct-capture UTF-8 limit leaves headroom for manual edits.
        maximumMarkdownBodyBytes: 16 * 1_024 * 1_024,
        // Sidecars contain metadata and bounded OCR text, never attachment bytes.
        maximumMetadataSidecarBytes: 2 * 1_024 * 1_024,
        // Matches the maximum normalized PNG accepted by capture.
        maximumAttachmentBytes: 25 * 1_024 * 1_024
    )

    var maximumIndexBytes: Int
    var maximumMarkdownBodyBytes: Int
    var maximumMetadataSidecarBytes: Int
    var maximumAttachmentBytes: Int
}

enum RegularNoteStoreError: Error, LocalizedError, Equatable {
    case unsafeAttachmentDirectory
    case artifactTooLarge(kind: RegularNoteArtifactKind, maximumBytes: Int)
    case invalidMarkdownEncoding

    var errorDescription: String? {
        switch self {
        case .unsafeAttachmentDirectory:
            return "The note attachment directory could not be used safely."
        case .artifactTooLarge(let kind, let maximumBytes):
            let limit = ByteCountFormatter.string(fromByteCount: Int64(maximumBytes), countStyle: .file)
            return "The note \(kind.description) is larger than Clasp's \(limit) per-file limit."
        case .invalidMarkdownEncoding:
            return "A note Markdown file is not valid UTF-8."
        }
    }
}

protocol RegularNoteDeletionFileOperating: Sendable {
    func createDirectory(at url: URL) throws
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws
    func removeItem(at url: URL) throws
}

struct SystemRegularNoteDeletionFileOperator: @unchecked Sendable, RegularNoteDeletionFileOperating {
    private let fileManager: FileManager

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
    }

    func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }
}

private struct RegularNoteDeletionRollbackFailure: Error, LocalizedError {
    let underlyingError: Error

    var errorDescription: String? {
        "Clasp could not restore every note file after the deletion was interrupted. The recoverable files remain in the Notes folder. \(underlyingError.localizedDescription)"
    }
}

actor RegularNoteStore: RegularNoteStoring {
    let notesDirectory: URL
    private let indexURL: URL
    private let fileManager: FileManager
    private let deletionFileOperator: any RegularNoteDeletionFileOperating
    private let writer: any AtomicFileWriting
    private let resourceBudget: RegularNoteStoreResourceBudget
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        baseDirectory: URL = AppPaths.applicationSupportDirectory,
        fileManager: FileManager = .default,
        writer: any AtomicFileWriting = SystemAtomicFileWriter(),
        deletionFileOperator: (any RegularNoteDeletionFileOperating)? = nil,
        resourceBudget: RegularNoteStoreResourceBudget = .standard
    ) {
        notesDirectory = baseDirectory.appendingPathComponent("Notes", isDirectory: true)
        indexURL = notesDirectory.appendingPathComponent("index.json")
        self.fileManager = fileManager
        self.writer = writer
        self.deletionFileOperator = deletionFileOperator
            ?? SystemRegularNoteDeletionFileOperator(fileManager: fileManager)
        self.resourceBudget = resourceBudget
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    func load() throws -> [Note] {
        try ensureDirectory()
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return try rebuildIndex()
        }
        do {
            let index = try decoder.decode(
                NoteIndex.self,
                from: readArtifact(
                    at: indexURL,
                    maximumBytes: resourceBudget.maximumIndexBytes,
                    kind: .index
                )
            )
            guard index.version == NoteIndex.currentVersion else { return try rebuildIndex() }
            let markdownIDs = try Set(markdownURLs().compactMap {
                UUID(uuidString: $0.deletingPathExtension().lastPathComponent)
            })
            guard markdownIDs == Set(index.notes.map(\.id)) else { return try rebuildIndex() }
            return try index.notes.map { metadata in
                let bodyURL = bodyURL(for: metadata.id)
                return metadata.note(
                    body: try readMarkdown(at: bodyURL),
                    loadedAttachments: try loadAttachments(metadata.attachments ?? [], noteID: metadata.id)
                )
            }.sorted(by: Self.sortNotes)
        } catch {
            return try rebuildIndex()
        }
    }

    func save(_ note: Note) throws {
        try ensureDirectory()
        let existing = try load()
        let previousAttachments = existing.first { $0.id == note.id }?.attachments ?? []
        let bodyData = Data(note.body.utf8)
        try enforceWriteLimit(
            bodyData,
            maximumBytes: resourceBudget.maximumMarkdownBodyBytes,
            kind: .markdownBody
        )
        let metadataData = try encoder.encode(NoteMetadata(note: note))
        try enforceWriteLimit(
            metadataData,
            maximumBytes: resourceBudget.maximumMetadataSidecarBytes,
            kind: .metadataSidecar
        )
        for attachment in note.attachments {
            try enforceWriteLimit(
                attachment.data,
                maximumBytes: resourceBudget.maximumAttachmentBytes,
                kind: .attachment
            )
        }
        try writer.write(bodyData, to: bodyURL(for: note.id))
        try saveAttachments(note.attachments, replacing: previousAttachments, noteID: note.id)
        try writer.write(metadataData, to: metadataURL(for: note.id))
        var notes = existing.filter { $0.id != note.id }
        notes.append(note)
        try writeIndex(notes)
    }

    func permanentlyDelete(id: UUID) throws {
        var notes = try load()
        notes.removeAll { $0.id == id }

        // Keep every destructive step on the same volume and reversible until
        // the atomic index write commits the logical deletion. A late index
        // failure can therefore put the exact files back instead of leaving
        // AppState to report a rollback after the note data was already lost.
        let artifacts = [
            bodyURL(for: id),
            metadataURL(for: id),
            attachmentDirectory(for: id)
        ].filter { fileManager.fileExists(atPath: $0.path) }

        guard !artifacts.isEmpty else {
            try writeIndex(notes)
            return
        }

        let quarantineURL = notesDirectory.appendingPathComponent(
            ".clasp-delete-transaction-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        try deletionFileOperator.createDirectory(at: quarantineURL)

        var quarantinedArtifacts: [(original: URL, quarantined: URL)] = []
        do {
            for originalURL in artifacts {
                let quarantinedURL = quarantineURL.appendingPathComponent(
                    originalURL.lastPathComponent,
                    isDirectory: originalURL == attachmentDirectory(for: id)
                )
                try deletionFileOperator.moveItem(at: originalURL, to: quarantinedURL)
                quarantinedArtifacts.append((originalURL, quarantinedURL))
            }

            try writeIndex(notes)
        } catch let deletionError {
            do {
                for artifact in quarantinedArtifacts.reversed() {
                    try deletionFileOperator.moveItem(
                        at: artifact.quarantined,
                        to: artifact.original
                    )
                }
                try deletionFileOperator.removeItem(at: quarantineURL)
            } catch let rollbackError {
                throw RegularNoteDeletionRollbackFailure(underlyingError: rollbackError)
            }
            throw deletionError
        }

        // The index is now committed without the note. Cleanup is deliberately
        // best-effort: a cleanup error must not turn a completed deletion into
        // a false UI rollback. Any residue stays isolated and recoverable in a
        // hidden transaction directory rather than at the live note paths.
        try? deletionFileOperator.removeItem(at: quarantineURL)
    }

    func rebuildIndex() throws -> [Note] {
        try ensureDirectory()
        let urls = try markdownURLs()

        let notes = try urls.compactMap { url -> Note? in
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { return nil }
            let body = try readMarkdown(at: url)
            let sidecar = metadataURL(for: id)
            if fileManager.fileExists(atPath: sidecar.path),
               let metadataData = try? readArtifact(
                   at: sidecar,
                   maximumBytes: resourceBudget.maximumMetadataSidecarBytes,
                   kind: .metadataSidecar
               ),
               let metadata = try? decoder.decode(NoteMetadata.self, from: metadataData),
               metadata.id == id {
                return metadata.note(
                    body: body,
                    loadedAttachments: try loadAttachments(metadata.attachments ?? [], noteID: id)
                )
            }
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            return Note(
                id: id,
                body: body,
                createdAt: values.creationDate ?? Date(),
                updatedAt: values.contentModificationDate ?? Date()
            )
        }.sorted(by: Self.sortNotes)
        try writeIndex(notes)
        return notes
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
    }

    private func bodyURL(for id: UUID) -> URL {
        notesDirectory.appendingPathComponent(id.uuidString.lowercased()).appendingPathExtension("md")
    }

    private func metadataURL(for id: UUID) -> URL {
        notesDirectory.appendingPathComponent("\(id.uuidString.lowercased()).metadata.json")
    }

    private func attachmentDirectory(for noteID: UUID) -> URL {
        attachmentsDirectory
            .appendingPathComponent(noteID.uuidString.lowercased(), isDirectory: true)
    }

    private var attachmentsDirectory: URL {
        notesDirectory.appendingPathComponent("Attachments", isDirectory: true)
    }

    private func attachmentURL(for reference: NoteAttachmentReference, noteID: UUID) -> URL {
        attachmentDirectory(for: noteID)
            .appendingPathComponent(reference.id.uuidString.lowercased())
            .appendingPathExtension(reference.fileExtension)
    }

    private func isSupported(_ reference: NoteAttachmentReference) -> Bool {
        reference.mediaType == "image/png" && reference.fileExtension == "png"
    }

    private func saveAttachments(
        _ attachments: [NoteAttachment],
        replacing previousAttachments: [NoteAttachment],
        noteID: UUID
    ) throws {
        let supported = attachments.filter { isSupported(NoteAttachmentReference(attachment: $0)) }
        let expected = Set(supported.map { "\($0.id.uuidString.lowercased()).\($0.fileExtension)" })
        let staleReferences = previousAttachments
            .map(NoteAttachmentReference.init)
            .filter { isSupported($0) && !expected.contains("\($0.id.uuidString.lowercased()).\($0.fileExtension)") }

        guard !supported.isEmpty || !staleReferences.isEmpty else { return }
        guard let directory = try validatedAttachmentDirectory(
            for: noteID,
            createIfMissing: !supported.isEmpty
        ) else { return }

        for attachment in supported {
            let reference = NoteAttachmentReference(attachment: attachment)
            try enforceWriteLimit(
                attachment.data,
                maximumBytes: resourceBudget.maximumAttachmentBytes,
                kind: .attachment
            )
            try writer.write(attachment.data, to: attachmentURL(for: reference, noteID: noteID))
        }

        for reference in staleReferences {
            try validateSafeDirectory(directory)
            let url = attachmentURL(for: reference, noteID: noteID)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            guard !isDirectory.boolValue else { throw RegularNoteStoreError.unsafeAttachmentDirectory }
            try fileManager.removeItem(at: url)
        }
    }

    private func validatedAttachmentDirectory(
        for noteID: UUID,
        createIfMissing: Bool
    ) throws -> URL? {
        try validateSafeDirectory(notesDirectory)

        if !fileManager.fileExists(atPath: attachmentsDirectory.path) {
            guard createIfMissing else { return nil }
            try fileManager.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: false)
        }
        try validateSafeDirectory(attachmentsDirectory)

        let directory = attachmentDirectory(for: noteID)
        if !fileManager.fileExists(atPath: directory.path) {
            guard createIfMissing else { return nil }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        }
        try validateSafeDirectory(directory)
        return directory
    }

    private func validateSafeDirectory(_ directory: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw RegularNoteStoreError.unsafeAttachmentDirectory
        }
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw RegularNoteStoreError.unsafeAttachmentDirectory
        }
    }

    private func loadAttachments(_ references: [NoteAttachmentReference], noteID: UUID) throws -> [NoteAttachment] {
        try references.compactMap { reference in
            guard isSupported(reference) else { return nil }
            let url = attachmentURL(for: reference, noteID: noteID)
            guard fileManager.fileExists(atPath: url.path) else { return nil }
            return NoteAttachment(
                id: reference.id,
                mediaType: reference.mediaType,
                fileExtension: reference.fileExtension,
                data: try readArtifact(
                    at: url,
                    maximumBytes: resourceBudget.maximumAttachmentBytes,
                    kind: .attachment
                )
            )
        }
    }

    private func markdownURLs() throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: notesDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "md" }
    }

    private func writeIndex(_ notes: [Note]) throws {
        let index = NoteIndex(notes: notes.map(NoteMetadata.init))
        let data = try encoder.encode(index)
        try enforceWriteLimit(
            data,
            maximumBytes: resourceBudget.maximumIndexBytes,
            kind: .index
        )
        try writer.write(data, to: indexURL)
    }

    private func readMarkdown(at url: URL) throws -> String {
        let data = try readArtifact(
            at: url,
            maximumBytes: resourceBudget.maximumMarkdownBodyBytes,
            kind: .markdownBody
        )
        guard let body = String(data: data, encoding: .utf8) else {
            throw RegularNoteStoreError.invalidMarkdownEncoding
        }
        return body
    }

    private func readArtifact(
        at url: URL,
        maximumBytes: Int,
        kind: RegularNoteArtifactKind
    ) throws -> Data {
        do {
            return try CappedFileReader.read(url, maximumBytes: maximumBytes)
        } catch is CappedFileReadError {
            throw RegularNoteStoreError.artifactTooLarge(kind: kind, maximumBytes: maximumBytes)
        }
    }

    private func enforceWriteLimit(
        _ data: Data,
        maximumBytes: Int,
        kind: RegularNoteArtifactKind
    ) throws {
        guard data.count <= maximumBytes else {
            throw RegularNoteStoreError.artifactTooLarge(kind: kind, maximumBytes: maximumBytes)
        }
    }

    private static func sortNotes(_ lhs: Note, _ rhs: Note) -> Bool {
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
        return lhs.updatedAt > rhs.updatedAt
    }
}
