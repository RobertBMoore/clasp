import AppKit
import Foundation

enum ExternalLinkPolicy {
    nonisolated static func allows(_ destination: String) -> Bool {
        guard let url = URL(string: destination) else { return false }
        return allows(url)
    }

    nonisolated static func allows(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "mailto"].contains(scheme)
    }

    nonisolated static func filterAllowed(_ urls: [URL]) -> [URL] {
        urls.filter(allows)
    }
}

@MainActor
enum MarkdownRichTextCodec {
    static let bodyFont = readingFont(ofSize: 17)
    static let italicObliqueness: CGFloat = 0.16
    static let maximumInlineParseOperations = 2_000_000

    static func readingFont(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let systemFont = NSFont.systemFont(ofSize: size, weight: weight)
        guard let readingDescriptor = systemFont.fontDescriptor.withDesign(.serif) else { return systemFont }
        return NSFont(descriptor: readingDescriptor, size: size) ?? systemFont
    }

    static func bodyParagraphStyle() -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        paragraph.paragraphSpacing = 10
        return paragraph
    }

    static func attributedString(
        from markdown: String,
        inlineParseBudget: Int = maximumInlineParseOperations
    ) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let lines = markdown.components(separatedBy: "\n")
        var remainingParseOperations = max(0, inlineParseBudget)

        for (index, rawLine) in lines.enumerated() {
            var line = rawLine
            var font = bodyFont
            var prefix = ""

            if let heading = headingPrefix(in: line) {
                line.removeFirst(heading.count + 1)
                let size: CGFloat = heading.count == 1 ? 26 : heading.count == 2 ? 22 : 18
                font = readingFont(ofSize: size, weight: .bold)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                line.removeFirst(2)
                prefix = "•\t"
            } else if let range = line.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                prefix = String(line[range]).trimmingCharacters(in: .whitespaces) + "\t"
                line.removeSubrange(range)
            }

            let paragraph = bodyParagraphStyle().mutableCopy() as! NSMutableParagraphStyle
            if !prefix.isEmpty {
                paragraph.headIndent = 22
                paragraph.firstLineHeadIndent = 0
                paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 18)]
            }
            let base: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
            if !prefix.isEmpty { output.append(NSAttributedString(string: prefix, attributes: base)) }
            appendInline(
                line[...],
                to: output,
                attributes: base,
                remainingParseOperations: &remainingParseOperations
            )
            if index < lines.count - 1 { output.append(NSAttributedString(string: "\n", attributes: base)) }
        }
        return output
    }

    static func markdown(from attributed: NSAttributedString) -> String {
        guard attributed.length > 0 else { return "" }
        let source = attributed.string as NSString
        var lines: [String] = []
        var location = 0

        while location < source.length {
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            var contentRange = lineRange
            while contentRange.length > 0 {
                let character = source.character(at: contentRange.location + contentRange.length - 1)
                guard character == 10 || character == 13 else { break }
                contentRange.length -= 1
            }
            let line = attributed.attributedSubstring(from: contentRange)
            var prefix = headingMarkdownPrefix(for: line)
            var inlineRange = NSRange(location: 0, length: line.length)
            let plain = line.string as NSString

            if plain.hasPrefix("•\t") || plain.hasPrefix("• ") {
                prefix = "- "
                inlineRange.location = 2
                inlineRange.length = max(0, inlineRange.length - 2)
            } else if let numbered = line.string.range(of: #"^\d+\.[\t ]"#, options: .regularExpression) {
                let nsRange = NSRange(numbered, in: line.string)
                prefix = plain.substring(with: nsRange).trimmingCharacters(in: .whitespacesAndNewlines) + " "
                inlineRange.location = nsRange.length
                inlineRange.length = max(0, inlineRange.length - nsRange.length)
            } else if prefix.isEmpty,
                      line.length > 0,
                      let style = line.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle,
                      let list = style.textLists.first {
                prefix = list.markerFormat == .decimal ? "1. " : "- "
            }

            lines.append(prefix + inlineMarkdown(
                from: line,
                range: inlineRange,
                suppressHeadingBold: prefix.hasPrefix("#")
            ))
            location = NSMaxRange(lineRange)
        }
        if source.hasSuffix("\n") { lines.append("") }
        return lines.joined(separator: "\n")
    }

    private static func headingPrefix(in line: String) -> String? {
        guard let range = line.range(of: #"^#{1,3}(?=\s)"#, options: .regularExpression) else { return nil }
        return String(line[range])
    }

    private static func headingMarkdownPrefix(for line: NSAttributedString) -> String {
        guard line.length > 0 else { return "" }
        var largest: CGFloat = 0
        line.enumerateAttribute(.font, in: NSRange(location: 0, length: line.length)) { value, _, _ in
            if let font = value as? NSFont { largest = max(largest, font.pointSize) }
        }
        if largest >= 24 { return "# " }
        if largest >= 20 { return "## " }
        if largest >= 18 { return "### " }
        return ""
    }

    private static func inlineMarkdown(
        from attributed: NSAttributedString,
        range: NSRange,
        suppressHeadingBold: Bool = false
    ) -> String {
        guard range.length > 0 else { return "" }
        var result = ""
        attributed.enumerateAttributes(in: range) { attributes, runRange, _ in
            var text = (attributed.string as NSString).substring(with: runRange)
                .replacingOccurrences(of: "\u{FFFC}", with: "")
            guard !text.isEmpty else { return }

            let font = attributes[.font] as? NSFont ?? bodyFont
            let traits = font.fontDescriptor.symbolicTraits
            let isBold = traits.contains(.bold) && !suppressHeadingBold
            let obliqueness = (attributes[.obliqueness] as? NSNumber)?.doubleValue ?? 0
            let isItalic = traits.contains(.italic) || abs(obliqueness) > 0.001
            let isMonospaced = traits.contains(.monoSpace)
            let hasLink = attributes[.link] != nil
            text = escapeMarkdown(text, forCode: isMonospaced)

            if isMonospaced { text = "`\(text)`" }
            if isBold && isItalic { text = "***\(text)***" }
            else if isBold { text = "**\(text)**" }
            else if isItalic { text = "*\(text)*" }
            if !hasLink, (attributes[.underlineStyle] as? Int ?? 0) != 0 { text = "<u>\(text)</u>" }
            if (attributes[.strikethroughStyle] as? Int ?? 0) != 0 { text = "~~\(text)~~" }
            if let link = attributes[.link] {
                let destination = (link as? URL)?.absoluteString ?? String(describing: link)
                if isSafeLink(destination) { text = "[\(text)](\(destination))" }
            }
            result += text
        }
        return result
    }

    private static func appendInline(
        _ input: Substring,
        to output: NSMutableAttributedString,
        attributes: [NSAttributedString.Key: Any],
        remainingParseOperations: inout Int
    ) {
        guard !input.isEmpty else { return }
        guard remainingParseOperations > 0 else {
            output.append(NSAttributedString(string: String(input), attributes: attributes))
            return
        }

        var remaining = input
        var nextClosingBracket = input.firstIndex(of: "]")
        var nextClosingParenthesis = input.firstIndex(of: ")")
        let hasUnderlineTerminator = input.range(of: "</u>") != nil

        func advance(
            _ candidate: inout Substring.Index?,
            toAtLeast lowerBound: Substring.Index,
            character: Character
        ) {
            while let current = candidate, current < lowerBound {
                let searchStart = input.index(after: current)
                candidate = searchStart < input.endIndex
                    ? input[searchStart...].firstIndex(of: character)
                    : nil
            }
        }

        while !remaining.isEmpty {
            guard remainingParseOperations > 0 else {
                output.append(NSAttributedString(string: String(remaining), attributes: attributes))
                return
            }
            remainingParseOperations -= 1

            if remaining.hasPrefix("\\"), remaining.count > 1 {
                let next = remaining.index(after: remaining.startIndex)
                output.append(NSAttributedString(string: String(remaining[next]), attributes: attributes))
                remaining = remaining[remaining.index(after: next)...]
                continue
            }
            if let match = delimited("***", "***", in: remaining) {
                appendInline(
                    match.content,
                    to: output,
                    attributes: applying(attributes, bold: true, italic: true),
                    remainingParseOperations: &remainingParseOperations
                )
                remaining = match.remainder
                continue
            }
            if let match = delimited("**", "**", in: remaining) {
                appendInline(
                    match.content,
                    to: output,
                    attributes: applying(attributes, bold: true),
                    remainingParseOperations: &remainingParseOperations
                )
                remaining = match.remainder
                continue
            }
            if let match = delimited("~~", "~~", in: remaining) {
                var changed = attributes
                changed[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                appendInline(
                    match.content,
                    to: output,
                    attributes: changed,
                    remainingParseOperations: &remainingParseOperations
                )
                remaining = match.remainder
                continue
            }
            if hasUnderlineTerminator,
               let match = delimited("<u>", "</u>", in: remaining) {
                var changed = attributes
                changed[.underlineStyle] = NSUnderlineStyle.single.rawValue
                appendInline(
                    match.content,
                    to: output,
                    attributes: changed,
                    remainingParseOperations: &remainingParseOperations
                )
                remaining = match.remainder
                continue
            }
            if let match = delimited("`", "`", in: remaining) {
                var changed = attributes
                let size = (attributes[.font] as? NSFont)?.pointSize ?? bodyFont.pointSize
                changed[.font] = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
                output.append(NSAttributedString(string: String(match.content), attributes: changed))
                remaining = match.remainder
                continue
            }
            advance(&nextClosingBracket, toAtLeast: remaining.startIndex, character: "]")
            if remaining.hasPrefix("["),
               let closeBracket = nextClosingBracket {
                let openParenthesis = input.index(after: closeBracket)
                guard openParenthesis < input.endIndex,
                      input[openParenthesis] == "(" else {
                    output.append(NSAttributedString(string: String(remaining.first!), attributes: attributes))
                    remaining = remaining.dropFirst()
                    continue
                }
                let urlStart = input.index(after: openParenthesis)
                advance(&nextClosingParenthesis, toAtLeast: urlStart, character: ")")
                guard let closeParen = nextClosingParenthesis else {
                    output.append(NSAttributedString(string: String(remaining.first!), attributes: attributes))
                    remaining = remaining.dropFirst()
                    continue
                }
                let label = remaining[remaining.index(after: remaining.startIndex)..<closeBracket]
                let destination = String(input[urlStart..<closeParen])
                var changed = attributes
                if isSafeLink(destination), let url = URL(string: destination) {
                    changed[.link] = url
                    changed[.foregroundColor] = NSColor.linkColor
                    changed[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                appendInline(
                    label,
                    to: output,
                    attributes: changed,
                    remainingParseOperations: &remainingParseOperations
                )
                remaining = input[input.index(after: closeParen)...]
                continue
            }
            if remaining.hasPrefix("*") || remaining.hasPrefix("_") {
                let marker = String(remaining.first!)
                if let match = delimited(marker, marker, in: remaining) {
                    appendInline(
                        match.content,
                        to: output,
                        attributes: applying(attributes, italic: true),
                        remainingParseOperations: &remainingParseOperations
                    )
                    remaining = match.remainder
                    continue
                }
            }
            output.append(NSAttributedString(string: String(remaining.first!), attributes: attributes))
            remaining = remaining.dropFirst()
        }
    }

    private static func delimited(
        _ opening: String,
        _ closing: String,
        in input: Substring
    ) -> (content: Substring, remainder: Substring)? {
        guard input.hasPrefix(opening) else { return nil }
        let contentStart = input.index(input.startIndex, offsetBy: opening.count)
        guard let closingRange = input[contentStart...].range(of: closing), !closingRange.isEmpty else { return nil }
        return (
            input[contentStart..<closingRange.lowerBound],
            input[closingRange.upperBound...]
        )
    }

    private static func applying(
        _ attributes: [NSAttributedString.Key: Any],
        bold: Bool = false,
        italic: Bool = false
    ) -> [NSAttributedString.Key: Any] {
        var changed = attributes
        let current = attributes[.font] as? NSFont ?? bodyFont
        var font = current
        if bold { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
        if italic {
            let italicFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            if italicFont.fontDescriptor.symbolicTraits.contains(.italic) {
                font = italicFont
            } else {
                changed[.obliqueness] = italicObliqueness
            }
        }
        changed[.font] = font
        return changed
    }

    private static func escapeMarkdown(_ text: String, forCode: Bool) -> String {
        if forCode { return text.replacingOccurrences(of: "`", with: "\\`") }
        return text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    nonisolated static func isSafeLink(_ destination: String) -> Bool {
        ExternalLinkPolicy.allows(destination)
    }
}
