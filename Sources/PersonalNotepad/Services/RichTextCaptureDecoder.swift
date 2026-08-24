import AppKit
import Foundation

@MainActor
enum RichTextCaptureDecoder {
    static let maximumStyledTextBytes = 10 * 1_024 * 1_024
    static let maximumMarkdownCharacters = 2_000_000

    static func rtf(_ data: Data) -> CapturedContent? {
        guard data.count <= maximumStyledTextBytes,
              let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
              ) else { return nil }
        return captured(attributed)
    }

    static func html(_ data: Data) -> CapturedContent? {
        guard data.count <= maximumStyledTextBytes,
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode) else { return nil }
        let markdown = SafeHTMLToMarkdown.convert(html)
        let plain = MarkdownRichTextCodec.attributedString(from: markdown).string
        guard !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return .styledText(
            markdown: String(markdown.prefix(maximumMarkdownCharacters)),
            plainText: String(plain.prefix(maximumMarkdownCharacters))
        )
    }

    private static func captured(_ attributed: NSAttributedString) -> CapturedContent? {
        let plain = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return nil }
        let markdown = MarkdownRichTextCodec.markdown(from: attributed)
        return .styledText(
            markdown: String(markdown.prefix(maximumMarkdownCharacters)),
            plainText: String(plain.prefix(maximumMarkdownCharacters))
        )
    }
}

private enum SafeHTMLToMarkdown {
    static func convert(_ html: String) -> String {
        var value = html
        value = replacing(#"(?is)<!--.*?-->"#, in: value, with: "")
        value = replacing(#"(?is)<(script|style|head|svg|iframe|object)\b[^>]*>.*?</\1\s*>"#, in: value, with: "")
        value = replacing(#"(?is)<(img|video|audio|source|link|meta|input)\b[^>]*>"#, in: value, with: "")
        value = replacingLinks(in: value)

        for level in 1...3 {
            value = replacing("(?i)<h\(level)\\b[^>]*>", in: value, with: String(repeating: "#", count: level) + " ")
            value = replacing("(?i)</h\(level)\\s*>", in: value, with: "\n\n")
        }
        let paired: [(String, String)] = [
            (#"(?i)<(strong|b)\b[^>]*>"#, "**"), (#"(?i)</(strong|b)\s*>"#, "**"),
            (#"(?i)<(em|i)\b[^>]*>"#, "*"), (#"(?i)</(em|i)\s*>"#, "*"),
            (#"(?i)<u\b[^>]*>"#, "<u>"), (#"(?i)</u\s*>"#, "</u>"),
            (#"(?i)<(s|del|strike)\b[^>]*>"#, "~~"), (#"(?i)</(s|del|strike)\s*>"#, "~~"),
            (#"(?i)<code\b[^>]*>"#, "`"), (#"(?i)</code\s*>"#, "`")
        ]
        for pair in paired { value = replacing(pair.0, in: value, with: pair.1) }
        value = replacing(#"(?i)<li\b[^>]*>"#, in: value, with: "- ")
        value = replacing(#"(?i)</li\s*>"#, in: value, with: "\n")
        value = replacing(#"(?i)<br\s*/?>"#, in: value, with: "\n")
        value = replacing(#"(?i)</?(p|div|section|article|header|footer|blockquote|pre|ul|ol|table|tr)\b[^>]*>"#, in: value, with: "\n")
        value = replacing(#"(?i)</?(td|th)\b[^>]*>"#, in: value, with: "\t")
        value = replacing(#"(?is)<[^>]+>"#, in: value, with: "")
        value = decodeEntities(value)
        value = replacing(#"[ \t]+\n"#, in: value, with: "\n")
        value = replacing(#"\n{3,}"#, in: value, with: "\n\n")
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replacingLinks(in input: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?is)<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a\s*>"#
        ) else { return input }
        let mutable = NSMutableString(string: input)
        let matches = regex.matches(in: input, range: NSRange(location: 0, length: mutable.length))
        for match in matches.reversed() {
            let destination = mutable.substring(with: match.range(at: 1))
            let label = mutable.substring(with: match.range(at: 2))
            let replacement = MarkdownRichTextCodec.isSafeLink(destination) ? "[\(label)](\(destination))" : label
            mutable.replaceCharacters(in: match.range, with: replacement)
        }
        return mutable as String
    }

    private static func replacing(_ pattern: String, in input: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        return regex.stringByReplacingMatches(
            in: input,
            range: NSRange(input.startIndex..., in: input),
            withTemplate: template
        )
    }

    private static func decodeEntities(_ input: String) -> String {
        var value = input
        let entities = ["&nbsp;": " ", "&#160;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'"]
        for (entity, replacement) in entities { value = value.replacingOccurrences(of: entity, with: replacement) }
        return value
    }
}
