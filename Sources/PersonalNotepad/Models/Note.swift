import Foundation

enum ClipContentType: String, Codable, CaseIterable, Sendable {
    case note
    case link
    case image
    case code
    case checklist
    case contact

    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .note: AppIcon.Content.note
        case .link: AppIcon.Content.link
        case .image: AppIcon.Content.image
        case .code: AppIcon.Content.code
        case .checklist: AppIcon.Content.checklist
        case .contact: AppIcon.Content.contact
        }
    }
}

struct NoteAttachment: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var mediaType: String
    var fileExtension: String
    var data: Data

    init(id: UUID = UUID(), mediaType: String = "image/png", fileExtension: String = "png", data: Data) {
        self.id = id
        self.mediaType = mediaType
        self.fileExtension = fileExtension
        self.data = data
    }
}

struct Note: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var body: String
    var tags: [String]
    var isPinned: Bool
    var isArchived: Bool
    var isInInbox: Bool
    var trashedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var contentType: ClipContentType
    var attachments: [NoteAttachment]
    var extractedText: String

    init(
        id: UUID = UUID(),
        title: String = "",
        body: String = "",
        tags: [String] = [],
        isPinned: Bool = false,
        isArchived: Bool = false,
        isInInbox: Bool = true,
        trashedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        contentType: ClipContentType = .note,
        attachments: [NoteAttachment] = [],
        extractedText: String = ""
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.tags = Self.normalizedTags(tags)
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.isInInbox = isInInbox
        self.trashedAt = trashedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.contentType = contentType
        self.attachments = attachments
        self.extractedText = extractedText
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.deriveTitle(from: body) : trimmed
    }

    var excerpt: String {
        let source = body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? extractedText : body
        return source
            .split(whereSeparator: \Character.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .dropFirst(displayTitle == Self.deriveTitle(from: body) ? 1 : 0)
            .joined(separator: " ")
            .prefix(160)
            .description
    }

    static func deriveTitle(from body: String) -> String {
        let first = body
            .split(whereSeparator: \Character.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? "Untitled Note"
        let withoutMarkdown = first.replacingOccurrences(
            of: #"^\s{0,3}[#>*+-]+\s*"#,
            with: "",
            options: .regularExpression
        )
        let derived = String(withoutMarkdown.prefix(120)).trimmingCharacters(in: .whitespaces)
        return derived.isEmpty ? "Untitled Note" : derived
    }

    static func normalizedTags(_ tags: [String]) -> [String] {
        Array(Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty })).sorted()
    }

    mutating func deriveInitialTitleIfNeeded() {
        let current = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard current.isEmpty || current == "Untitled Note" else { return }
        let derived = Self.deriveTitle(from: body)
        guard derived != "Untitled Note" else { return }
        title = derived
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, body, tags, isPinned, isArchived, isInInbox, trashedAt, createdAt, updatedAt
        case contentType, attachments, extractedText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        tags = try container.decode([String].self, forKey: .tags)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        isArchived = try container.decode(Bool.self, forKey: .isArchived)
        isInInbox = try container.decode(Bool.self, forKey: .isInInbox)
        trashedAt = try container.decodeIfPresent(Date.self, forKey: .trashedAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        contentType = try container.decodeIfPresent(ClipContentType.self, forKey: .contentType) ?? .note
        attachments = try container.decodeIfPresent([NoteAttachment].self, forKey: .attachments) ?? []
        extractedText = try container.decodeIfPresent(String.self, forKey: .extractedText) ?? ""
    }
}

struct NoteAttachmentReference: Codable, Equatable, Sendable {
    var id: UUID
    var mediaType: String
    var fileExtension: String

    init(attachment: NoteAttachment) {
        id = attachment.id
        mediaType = attachment.mediaType
        fileExtension = attachment.fileExtension
    }
}

struct NoteMetadata: Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var tags: [String]
    var isPinned: Bool
    var isArchived: Bool
    var isInInbox: Bool
    var trashedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var contentType: ClipContentType?
    var attachments: [NoteAttachmentReference]?
    var extractedText: String?

    init(note: Note) {
        id = note.id
        title = note.title
        tags = note.tags
        isPinned = note.isPinned
        isArchived = note.isArchived
        isInInbox = note.isInInbox
        trashedAt = note.trashedAt
        createdAt = note.createdAt
        updatedAt = note.updatedAt
        contentType = note.contentType
        attachments = note.attachments.map(NoteAttachmentReference.init)
        extractedText = note.extractedText
    }

    func note(body: String, loadedAttachments: [NoteAttachment] = []) -> Note {
        Note(
            id: id,
            title: title,
            body: body,
            tags: tags,
            isPinned: isPinned,
            isArchived: isArchived,
            isInInbox: isInInbox,
            trashedAt: trashedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            contentType: contentType ?? .note,
            attachments: loadedAttachments,
            extractedText: extractedText ?? ""
        )
    }
}

struct NoteIndex: Codable, Equatable, Sendable {
    static let currentVersion = 1
    var version: Int = Self.currentVersion
    var notes: [NoteMetadata]
}
