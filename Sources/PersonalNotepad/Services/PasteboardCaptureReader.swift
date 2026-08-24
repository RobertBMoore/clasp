import AppKit
import Foundation
import ImageIO

enum PasteboardCaptureError: LocalizedError, Equatable {
    case unsupportedContent
    case imageTooLarge
    case imageDimensionsTooLarge
    case invalidImage
    case textTooLarge

    var errorDescription: String? {
        switch self {
        case .unsupportedContent: "The selection does not contain text or a supported image."
        case .imageTooLarge: "That image is larger than Clasp's 25 MB capture limit."
        case .imageDimensionsTooLarge: "That image's pixel dimensions are too large for safe capture."
        case .invalidImage: "Clasp could not read that image."
        case .textTooLarge: "That text is larger than Clasp's 2,000,000-character or 8 MB capture limit."
        }
    }
}

@MainActor
enum PasteboardCaptureReader {
    static let maximumImageBytes = 25 * 1_024 * 1_024
    static let maximumImageDimension = 12_000
    static let maximumImagePixels = 40_000_000
    static let maximumTextCharacters = 2_000_000
    static let maximumTextUTF8Bytes = 8 * 1_024 * 1_024

    static func read(
        from pasteboard: NSPasteboard,
        imageByteLimit: Int = maximumImageBytes
    ) throws -> CapturedContent {
        if let data = pasteboard.data(forType: .png) {
            return .image(try normalizedImage(from: data, maximumBytes: imageByteLimit))
        }
        if let data = pasteboard.data(forType: .tiff) {
            return .image(try normalizedImage(from: data, maximumBytes: imageByteLimit))
        }
        if let data = pasteboard.data(forType: .rtf), let styled = RichTextCaptureDecoder.rtf(data) {
            return styled
        }
        if let data = pasteboard.data(forType: .html), let styled = RichTextCaptureDecoder.html(data) {
            return styled
        }
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], let imageURL = urls.first(where: isSupportedImageURL) {
            let data: Data
            do {
                data = try CappedFileReader.read(imageURL, maximumBytes: imageByteLimit)
            } catch is CappedFileReadError {
                throw PasteboardCaptureError.imageTooLarge
            } catch {
                throw PasteboardCaptureError.invalidImage
            }
            return .image(try normalizedImage(from: data, maximumBytes: imageByteLimit))
        }
        if let rawLink = pasteboard.string(forType: .URL) {
            let link = rawLink.trimmingCharacters(in: .whitespacesAndNewlines)
            if !link.isEmpty {
                try validateTextBudget(link)
                if URL(string: link)?.scheme != nil { return .text(link) }
            }
        }
        if let text = pasteboard.string(forType: .string) {
            try validateTextBudget(text)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .text(text) }
        }
        throw PasteboardCaptureError.unsupportedContent
    }

    private static func normalizedImage(from data: Data, maximumBytes: Int) throws -> CapturedImage {
        guard data.count <= maximumBytes else { throw PasteboardCaptureError.imageTooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw PasteboardCaptureError.invalidImage
        }
        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow,
              width > 0,
              height > 0,
              width <= maximumImageDimension,
              height <= maximumImageDimension,
              pixels <= maximumImagePixels else {
            throw PasteboardCaptureError.imageDimensionsTooLarge
        }
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PasteboardCaptureError.invalidImage
        }
        let representation = NSBitmapImageRep(cgImage: cgImage)
        guard
              let png = representation.representation(using: .png, properties: [:]) else {
            throw PasteboardCaptureError.invalidImage
        }
        guard png.count <= maximumBytes else { throw PasteboardCaptureError.imageTooLarge }
        return CapturedImage(
            pngData: png,
            pixelWidth: width,
            pixelHeight: height
        )
    }

    private static func validateTextBudget(_ text: String) throws {
        guard text.utf8.count <= maximumTextUTF8Bytes,
              text.count <= maximumTextCharacters else {
            throw PasteboardCaptureError.textTooLarge
        }
    }

    private static func isSupportedImageURL(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "gif", "tif", "tiff", "heic", "webp"]
            .contains(url.pathExtension.lowercased())
    }
}
