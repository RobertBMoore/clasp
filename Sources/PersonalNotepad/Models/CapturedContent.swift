import Foundation

struct CapturedImage: Equatable, Sendable {
    var pngData: Data
    var pixelWidth: Int?
    var pixelHeight: Int?
}

enum CapturedContent: Equatable, Sendable {
    case text(String)
    case styledText(markdown: String, plainText: String)
    case image(CapturedImage)
}

struct ClassifiedCapture: Equatable, Sendable {
    var title: String
    var body: String
    var tags: [String]
    var contentType: ClipContentType
    var attachments: [NoteAttachment]
    var extractedText: String

    func note() -> Note {
        Note(
            title: title,
            body: body,
            tags: tags,
            contentType: contentType,
            attachments: attachments,
            extractedText: extractedText
        )
    }
}
