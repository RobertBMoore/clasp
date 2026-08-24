import AppKit
import Foundation

enum MarkdownListKind: Equatable, Sendable {
    case bullet
    case numbered
    case checklist(checked: Bool)
}

enum MarkdownSourceTokenKind: Equatable, Sendable {
    case heading(level: Int)
    case strong
    case emphasis
    case strikethrough
    case inlineCode
    case link(destination: String, isAllowed: Bool)
    case list(MarkdownListKind)
    case blockquote
    case fencedCode(language: String?)
    case thematicBreak
}

/// A semantic Markdown span. All ranges use NSString/UTF-16 coordinates, matching TextKit.
/// `markerRanges` identifies syntax which can be visually de-emphasized without changing bytes.
struct MarkdownSourceToken: Equatable, Sendable {
    let kind: MarkdownSourceTokenKind
    let range: NSRange
    let contentRange: NSRange
    let markerRanges: [NSRange]
}

enum MarkdownSourceAnalyzer {
    private struct Line {
        let range: NSRange
        let fullRange: NSRange
        let text: String
    }

    private static let headingExpression = expression(#"^( {0,3})(#{1,6})[\t ]+(.*)$"#)
    private static let quoteExpression = expression(#"^([\t ]{0,3})(>[\t ]?)(.*)$"#)
    private static let taskExpression = expression(#"^([\t ]*)([-+*][\t ]+\[([ xX])\][\t ]+)(.*)$"#)
    private static let bulletExpression = expression(#"^([\t ]*)([-+*][\t ]+)(.*)$"#)
    private static let numberedExpression = expression(#"^([\t ]*)(\d+[.)][\t ]+)(.*)$"#)
    private static let thematicBreakExpression = expression(#"^[\t ]{0,3}(?:(?:\*[\t ]*){3,}|(?:-[\t ]*){3,}|(?:_[\t ]*){3,})$"#)
    private static let fenceExpression = expression(#"^ {0,3}(`{3,}|~{3,})(.*)$"#)
    private static let linkExpression = expression(#"(?<!\!)\[([^\]\n]+)\]\((<[^>\n]+>|[^\n()]*)\)"#)
    private static let strongExpression = expression(#"\*\*([^\n]+?)\*\*|__([^\n]+?)__"#)
    private static let strikeExpression = expression(#"~~([^\n]+?)~~"#)
    private static let codeExpression = expression(#"(`+)([^\n]*?)\1"#)
    private static let emphasisExpression = expression(#"(?<!\*)\*([^*\n]+?)\*(?!\*)|(?<!_)_([^_\n]+?)_(?!_)"#)

    static func tokens(in source: String) -> [MarkdownSourceToken] {
        let string = source as NSString
        let lines = lines(in: string)
        var tokens: [MarkdownSourceToken] = []
        var fencedRanges: [NSRange] = []

        var index = 0
        while index < lines.count {
            let line = lines[index]
            guard let opening = firstMatch(fenceExpression, in: line.text),
                  let openingMarker = capture(opening, 1, offset: line.range.location) else {
                index += 1
                continue
            }

            let openingText = string.substring(with: openingMarker)
            let fenceCharacter = openingText.first
            var closingIndex: Int?
            if index + 1 < lines.count {
                for candidateIndex in (index + 1)..<lines.count {
                    let candidate = lines[candidateIndex]
                    guard let match = firstMatch(fenceExpression, in: candidate.text),
                          let markerRange = capture(match, 1, offset: candidate.range.location) else { continue }
                    let marker = string.substring(with: markerRange)
                    if marker.first == fenceCharacter && marker.utf16.count >= openingText.utf16.count {
                        closingIndex = candidateIndex
                        break
                    }
                }
            }

            let info = capture(opening, 2, in: line.text as NSString)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let language = info.flatMap { $0.isEmpty ? nil : $0.components(separatedBy: .whitespaces).first }
            let closingLine = closingIndex.map { lines[$0] }
            let end = closingLine.map { NSMaxRange($0.fullRange) } ?? string.length
            let contentStart = NSMaxRange(line.fullRange)
            let contentEnd = closingLine?.range.location ?? string.length
            let fullRange = NSRange(location: line.range.location, length: max(0, end - line.range.location))
            let contentRange = NSRange(location: min(contentStart, contentEnd), length: max(0, contentEnd - contentStart))
            var markers = [line.range]
            if let closingLine { markers.append(closingLine.range) }
            tokens.append(.init(
                kind: .fencedCode(language: language),
                range: fullRange,
                contentRange: contentRange,
                markerRanges: markers
            ))
            fencedRanges.append(fullRange)
            index = (closingIndex ?? (lines.count - 1)) + 1
        }

        for line in lines where !intersectsAny(line.range, fencedRanges) {
            if let match = firstMatch(headingExpression, in: line.text),
               let marker = capture(match, 2, offset: line.range.location),
               let content = capture(match, 3, offset: line.range.location) {
                tokens.append(.init(
                    kind: .heading(level: marker.length),
                    range: line.range,
                    contentRange: content,
                    markerRanges: [NSRange(location: marker.location, length: content.location - marker.location)]
                ))
            }

            if let match = firstMatch(quoteExpression, in: line.text),
               let marker = capture(match, 2, offset: line.range.location),
               let content = capture(match, 3, offset: line.range.location) {
                tokens.append(.init(kind: .blockquote, range: line.range, contentRange: content, markerRanges: [marker]))
            }

            if let match = firstMatch(taskExpression, in: line.text),
               let marker = capture(match, 2, offset: line.range.location),
               let state = capture(match, 3, in: line.text as NSString),
               let content = capture(match, 4, offset: line.range.location) {
                tokens.append(.init(
                    kind: .list(.checklist(checked: state.lowercased() == "x")),
                    range: line.range,
                    contentRange: content,
                    markerRanges: [marker]
                ))
            } else if let match = firstMatch(numberedExpression, in: line.text),
                      let marker = capture(match, 2, offset: line.range.location),
                      let content = capture(match, 3, offset: line.range.location) {
                tokens.append(.init(kind: .list(.numbered), range: line.range, contentRange: content, markerRanges: [marker]))
            } else if let match = firstMatch(bulletExpression, in: line.text),
                      let marker = capture(match, 2, offset: line.range.location),
                      let content = capture(match, 3, offset: line.range.location) {
                tokens.append(.init(kind: .list(.bullet), range: line.range, contentRange: content, markerRanges: [marker]))
            }

            if thematicBreakExpression.firstMatch(in: line.text, range: NSRange(location: 0, length: (line.text as NSString).length)) != nil {
                tokens.append(.init(kind: .thematicBreak, range: line.range, contentRange: line.range, markerRanges: [line.range]))
            }
        }

        let protectedRanges = fencedRanges
        var inlineClaimed: [NSRange] = []
        appendInlineTokens(
            expression: linkExpression,
            kind: { match, source in
                let rawDestination = capture(match, 2, in: source) ?? ""
                let destination = normalizedLinkDestination(rawDestination)
                let allowed = URL(string: destination).map(ExternalLinkPolicy.allows) ?? false
                return .link(destination: destination, isAllowed: allowed)
            },
            contentCapture: 1,
            source: string,
            protectedRanges: protectedRanges,
            claimedRanges: &inlineClaimed,
            tokens: &tokens,
            claimsMarkersOnly: true
        )
        appendInlineTokens(
            expression: codeExpression,
            kind: { _, _ in .inlineCode },
            contentCapture: 2,
            source: string,
            protectedRanges: protectedRanges,
            claimedRanges: &inlineClaimed,
            tokens: &tokens
        )
        appendInlineTokens(
            expression: strongExpression,
            kind: { _, _ in .strong },
            contentCapture: nil,
            source: string,
            protectedRanges: protectedRanges,
            claimedRanges: &inlineClaimed,
            tokens: &tokens
        )
        appendInlineTokens(
            expression: strikeExpression,
            kind: { _, _ in .strikethrough },
            contentCapture: 1,
            source: string,
            protectedRanges: protectedRanges,
            claimedRanges: &inlineClaimed,
            tokens: &tokens
        )
        appendInlineTokens(
            expression: emphasisExpression,
            kind: { _, _ in .emphasis },
            contentCapture: nil,
            source: string,
            protectedRanges: protectedRanges,
            claimedRanges: &inlineClaimed,
            tokens: &tokens
        )

        return tokens.sorted {
            if $0.range.location == $1.range.location { return $0.range.length > $1.range.length }
            return $0.range.location < $1.range.location
        }
    }

    private static func appendInlineTokens(
        expression: NSRegularExpression,
        kind: (NSTextCheckingResult, NSString) -> MarkdownSourceTokenKind,
        contentCapture: Int?,
        source: NSString,
        protectedRanges: [NSRange],
        claimedRanges: inout [NSRange],
        tokens: inout [MarkdownSourceToken],
        claimsMarkersOnly: Bool = false
    ) {
        let fullRange = NSRange(location: 0, length: source.length)
        // Each regular-expression pass yields matches in source order. Ranges
        // claimed by prior passes are non-overlapping, so sorting them once per
        // pass lets every overlap check use binary search instead of degrading
        // to quadratic work on long AI-generated documents.
        let sortedProtectedRanges = protectedRanges.sorted(by: rangePrecedes)
        let sortedClaimedRanges = claimedRanges.sorted(by: rangePrecedes)
        for match in expression.matches(in: source as String, range: fullRange) {
            guard !intersectsAny(match.range, sortedProtectedRanges),
                  !intersectsAny(match.range, sortedClaimedRanges) else { continue }
            let content: NSRange
            if let contentCapture {
                content = match.range(at: contentCapture)
            } else {
                content = firstPresentCapture(in: match) ?? match.range
            }
            guard content.location != NSNotFound else { continue }
            let prefixLength = max(0, content.location - match.range.location)
            let suffixStart = NSMaxRange(content)
            let suffixLength = max(0, NSMaxRange(match.range) - suffixStart)
            var markers: [NSRange] = []
            if prefixLength > 0 { markers.append(NSRange(location: match.range.location, length: prefixLength)) }
            if suffixLength > 0 { markers.append(NSRange(location: suffixStart, length: suffixLength)) }
            tokens.append(.init(kind: kind(match, source), range: match.range, contentRange: content, markerRanges: markers))
            if claimsMarkersOnly { claimedRanges.append(contentsOf: markers) }
            else { claimedRanges.append(match.range) }
        }
    }

    private static func firstPresentCapture(in match: NSTextCheckingResult) -> NSRange? {
        guard match.numberOfRanges > 1 else { return nil }
        for index in 1..<match.numberOfRanges {
            let range = match.range(at: index)
            if range.location != NSNotFound { return range }
        }
        return nil
    }

    private static func normalizedLinkDestination(_ destination: String) -> String {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<"), trimmed.hasSuffix(">"), trimmed.count >= 2 {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }

    private static func lines(in source: NSString) -> [Line] {
        if source.length == 0 { return [.init(range: .init(location: 0, length: 0), fullRange: .init(location: 0, length: 0), text: "")] }
        var result: [Line] = []
        var location = 0
        while location < source.length {
            let fullRange = source.lineRange(for: NSRange(location: location, length: 0))
            var contentEnd = NSMaxRange(fullRange)
            while contentEnd > fullRange.location {
                let character = source.character(at: contentEnd - 1)
                if character == 0x0A || character == 0x0D { contentEnd -= 1 } else { break }
            }
            let range = NSRange(location: fullRange.location, length: contentEnd - fullRange.location)
            result.append(.init(range: range, fullRange: fullRange, text: source.substring(with: range)))
            location = NSMaxRange(fullRange)
        }
        return result
    }

    private static func expression(_ pattern: String) -> NSRegularExpression {
        // Patterns are compile-time constants and covered by unit tests.
        try! NSRegularExpression(pattern: pattern)
    }

    private static func firstMatch(_ expression: NSRegularExpression, in string: String) -> NSTextCheckingResult? {
        expression.firstMatch(in: string, range: NSRange(location: 0, length: (string as NSString).length))
    }

    private static func capture(_ match: NSTextCheckingResult, _ index: Int, offset: Int) -> NSRange? {
        let range = match.range(at: index)
        guard range.location != NSNotFound else { return nil }
        return NSRange(location: offset + range.location, length: range.length)
    }

    private static func capture(_ match: NSTextCheckingResult, _ index: Int, in source: NSString) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound else { return nil }
        return source.substring(with: range)
    }

    private static func intersectsAny(_ range: NSRange, _ others: [NSRange]) -> Bool {
        guard range.length > 0, !others.isEmpty else { return false }
        var lowerBound = 0
        var upperBound = others.count
        while lowerBound < upperBound {
            let midpoint = lowerBound + (upperBound - lowerBound) / 2
            if NSMaxRange(others[midpoint]) <= range.location {
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint
            }
        }
        guard lowerBound < others.count else { return false }
        return others[lowerBound].location < NSMaxRange(range)
    }

    private static func rangePrecedes(_ lhs: NSRange, _ rhs: NSRange) -> Bool {
        if lhs.location == rhs.location { return lhs.length < rhs.length }
        return lhs.location < rhs.location
    }
}

struct MarkdownSourceEditResult: Equatable, Sendable {
    let source: String
    let selection: NSRange
}

enum MarkdownSourceIdentity {
    /// Swift string equality intentionally treats canonically equivalent Unicode
    /// spellings as equal. Markdown persistence does not: exact UTF-8 source bytes
    /// are the identity so normalization-only changes still synchronize.
    static func exactlyEqual(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.elementsEqual(rhs.utf8)
    }
}

enum MarkdownSourceCommandTransformer {
    private struct TextEdit {
        let range: NSRange
        let replacement: String
    }

    private static let headingPrefixExpression = try! NSRegularExpression(pattern: #"^([\t ]{0,3})#{1,6}[\t ]+"#)
    private static let listPrefixExpression = try! NSRegularExpression(pattern: #"^([\t ]*)(?:(?:[-+*])[\t ]+(?:\[[ xX]\][\t ]+)?|\d+[.)][\t ]+)"#)
    private static let quotePrefixExpression = try! NSRegularExpression(pattern: #"^([\t ]{0,3})>[\t ]?"#)

    static func applying(
        _ command: RichEditorCommand,
        to source: String,
        selection requestedSelection: NSRange
    ) -> MarkdownSourceEditResult {
        let sourceLength = (source as NSString).length
        let selection = clamped(requestedSelection, to: sourceLength)
        switch command {
        case .bold:
            return wrapped(source, selection: selection, opening: "**", closing: "**")
        case .italic:
            return wrapped(source, selection: selection, opening: "*", closing: "*")
        case .strikethrough:
            return wrapped(source, selection: selection, opening: "~~", closing: "~~")
        case .inlineCode:
            return inlineCode(source, selection: selection)
        case .link(let destination):
            return link(source, selection: selection, destination: destination)
        case .body:
            return heading(source, selection: selection, level: nil)
        case .heading1:
            return heading(source, selection: selection, level: 1)
        case .heading2:
            return heading(source, selection: selection, level: 2)
        case .heading3:
            return heading(source, selection: selection, level: 3)
        case .heading4:
            return heading(source, selection: selection, level: 4)
        case .heading5:
            return heading(source, selection: selection, level: 5)
        case .heading6:
            return heading(source, selection: selection, level: 6)
        case .bulletList:
            return list(source, selection: selection, kind: .bullet)
        case .numberedList:
            return list(source, selection: selection, kind: .numbered)
        case .checklist:
            return list(source, selection: selection, kind: .checklist(checked: false))
        case .blockquote:
            return blockquote(source, selection: selection)
        case .fencedCode:
            return fencedCode(source, selection: selection)
        case .horizontalRule:
            return horizontalRule(source, selection: selection)
        }
    }

    private static func wrapped(
        _ source: String,
        selection: NSRange,
        opening: String,
        closing: String
    ) -> MarkdownSourceEditResult {
        let string = source as NSString
        let openingLength = (opening as NSString).length
        let closingLength = (closing as NSString).length

        if selection.length >= openingLength + closingLength {
            let selected = string.substring(with: selection)
            if selected.hasPrefix(opening), selected.hasSuffix(closing) {
                let contentRange = NSRange(
                    location: selection.location + openingLength,
                    length: selection.length - openingLength - closingLength
                )
                let content = string.substring(with: contentRange)
                return replacing(source, edits: [.init(range: selection, replacement: content)], selection: .init(location: selection.location, length: contentRange.length))
            }
        }

        let before = NSRange(location: selection.location - openingLength, length: openingLength)
        let after = NSRange(location: NSMaxRange(selection), length: closingLength)
        if before.location >= 0,
           NSMaxRange(after) <= string.length,
           string.substring(with: before) == opening,
           string.substring(with: after) == closing {
            let combined = NSRange(location: before.location, length: openingLength + selection.length + closingLength)
            let content = string.substring(with: selection)
            return replacing(source, edits: [.init(range: combined, replacement: content)], selection: .init(location: before.location, length: selection.length))
        }

        let content = string.substring(with: selection)
        let replacement = opening + content + closing
        let resultSelection: NSRange
        if selection.length == 0 {
            resultSelection = NSRange(location: selection.location + openingLength, length: 0)
        } else {
            resultSelection = NSRange(location: selection.location + openingLength, length: selection.length)
        }
        return replacing(source, edits: [.init(range: selection, replacement: replacement)], selection: resultSelection)
    }

    private static func inlineCode(_ source: String, selection: NSRange) -> MarkdownSourceEditResult {
        let selected = (source as NSString).substring(with: selection)
        var longestRun = 0
        var currentRun = 0
        for character in selected {
            if character == "`" {
                currentRun += 1
                longestRun = max(longestRun, currentRun)
            } else {
                currentRun = 0
            }
        }
        let marker = String(repeating: "`", count: max(1, longestRun + 1))
        return wrapped(source, selection: selection, opening: marker, closing: marker)
    }

    private static func link(_ source: String, selection: NSRange, destination: String) -> MarkdownSourceEditResult {
        guard let url = URL(string: destination), ExternalLinkPolicy.allows(url) else {
            return .init(source: source, selection: selection)
        }
        let string = source as NSString
        let label = selection.length == 0 ? "Link" : string.substring(with: selection)
        let markdownDestination: String
        if destination.contains(" ") || destination.contains("(") || destination.contains(")") {
            markdownDestination = "<\(destination)>"
        } else {
            markdownDestination = destination
        }
        let replacement = "[\(label)](\(markdownDestination))"
        return replacing(
            source,
            edits: [.init(range: selection, replacement: replacement)],
            selection: NSRange(location: selection.location + 1, length: (label as NSString).length)
        )
    }

    private static func heading(_ source: String, selection: NSRange, level: Int?) -> MarkdownSourceEditResult {
        let string = source as NSString
        let ranges = selectedLineRanges(in: string, selection: selection)
        let edits = ranges.compactMap { lineRange -> TextEdit? in
            let line = string.substring(with: lineRange) as NSString
            let match = headingPrefixExpression.firstMatch(in: line as String, range: NSRange(location: 0, length: line.length))
            let indentLength: Int
            if let match { indentLength = match.range(at: 1).length }
            else { indentLength = leadingIndentLength(in: line, maximum: 3) }
            let indent = line.substring(with: NSRange(location: 0, length: indentLength))
            let existingLength = match?.range.length ?? indentLength
            let replacement = indent + (level.map { String(repeating: "#", count: $0) + " " } ?? "")
            guard existingLength != (replacement as NSString).length || line.substring(with: NSRange(location: 0, length: existingLength)) != replacement else { return nil }
            return .init(range: NSRange(location: lineRange.location, length: existingLength), replacement: replacement)
        }
        return replacing(source, edits: edits, mappedSelection: selection)
    }

    private static func list(_ source: String, selection: NSRange, kind: MarkdownListKind) -> MarkdownSourceEditResult {
        let string = source as NSString
        let ranges = selectedLineRanges(in: string, selection: selection)
        let allAlreadyRequested = !ranges.isEmpty && ranges.allSatisfy { range in
            listKindsMatch(listKind(in: string.substring(with: range) as NSString), kind)
        }

        let edits = ranges.map { lineRange -> TextEdit in
            let line = string.substring(with: lineRange) as NSString
            let match = listPrefixExpression.firstMatch(in: line as String, range: NSRange(location: 0, length: line.length))
            let indentLength = match?.range(at: 1).length ?? leadingIndentLength(in: line, maximum: nil)
            let existingLength = match?.range.length ?? indentLength
            let indent = line.substring(with: NSRange(location: 0, length: indentLength))
            let marker: String
            if allAlreadyRequested {
                marker = ""
            } else {
                switch kind {
                case .bullet: marker = "- "
                case .numbered: marker = "1. "
                case .checklist: marker = "- [ ] "
                }
            }
            return .init(range: NSRange(location: lineRange.location, length: existingLength), replacement: indent + marker)
        }
        return replacing(source, edits: edits, mappedSelection: selection)
    }

    private static func blockquote(_ source: String, selection: NSRange) -> MarkdownSourceEditResult {
        let string = source as NSString
        let ranges = selectedLineRanges(in: string, selection: selection)
        let allQuoted = !ranges.isEmpty && ranges.allSatisfy { range in
            let line = string.substring(with: range) as NSString
            return quotePrefixExpression.firstMatch(in: line as String, range: NSRange(location: 0, length: line.length)) != nil
        }
        let edits = ranges.map { lineRange -> TextEdit in
            let line = string.substring(with: lineRange) as NSString
            if allQuoted, let match = quotePrefixExpression.firstMatch(in: line as String, range: NSRange(location: 0, length: line.length)) {
                let indentRange = match.range(at: 1)
                let markerRange = NSRange(location: indentRange.length, length: match.range.length - indentRange.length)
                return .init(range: NSRange(location: lineRange.location + markerRange.location, length: markerRange.length), replacement: "")
            }
            let indentLength = leadingIndentLength(in: line, maximum: 3)
            return .init(range: NSRange(location: lineRange.location + indentLength, length: 0), replacement: "> ")
        }
        return replacing(source, edits: edits, mappedSelection: selection)
    }

    private static func fencedCode(_ source: String, selection: NSRange) -> MarkdownSourceEditResult {
        let string = source as NSString
        if let existing = MarkdownSourceAnalyzer.tokens(in: source).first(where: { token in
            guard case .fencedCode = token.kind else { return false }
            return NSIntersectionRange(token.range, selection).length > 0 || (selection.length == 0 && NSLocationInRange(selection.location, token.range))
        }), existing.markerRanges.count == 2 {
            var openingRemoval = existing.markerRanges[0]
            if NSMaxRange(openingRemoval) < string.length {
                let next = string.character(at: NSMaxRange(openingRemoval))
                if next == 0x0D {
                    openingRemoval.length += 1
                    if NSMaxRange(openingRemoval) < string.length, string.character(at: NSMaxRange(openingRemoval)) == 0x0A {
                        openingRemoval.length += 1
                    }
                } else if next == 0x0A {
                    openingRemoval.length += 1
                }
            }

            var closingRemoval = existing.markerRanges[1]
            // The separator immediately before the closing fence is structural
            // for a selection that did not already end in a newline.
            if existing.contentRange.length > 0, closingRemoval.location > 0 {
                let previous = string.character(at: closingRemoval.location - 1)
                if previous == 0x0A {
                    closingRemoval.location -= 1
                    closingRemoval.length += 1
                    if closingRemoval.location > 0, string.character(at: closingRemoval.location - 1) == 0x0D {
                        closingRemoval.location -= 1
                        closingRemoval.length += 1
                    }
                } else if previous == 0x0D {
                    closingRemoval.location -= 1
                    closingRemoval.length += 1
                }
            }
            let edits = [TextEdit(range: openingRemoval, replacement: ""), TextEdit(range: closingRemoval, replacement: "")]
            return replacing(source, edits: edits, mappedSelection: selection)
        }

        let selected = string.substring(with: selection)
        let longestRun = longestBacktickRun(in: selected)
        let fence = String(repeating: "`", count: max(3, longestRun + 1))
        let newline = preferredNewline(in: source)
        let replacement = fence + newline + selected + (selected.hasSuffix("\n") || selected.hasSuffix("\r") ? "" : newline) + fence
        return replacing(
            source,
            edits: [.init(range: selection, replacement: replacement)],
            selection: NSRange(location: selection.location + (fence as NSString).length + (newline as NSString).length, length: selection.length)
        )
    }

    private static func horizontalRule(_ source: String, selection: NSRange) -> MarkdownSourceEditResult {
        let string = source as NSString
        let line = selectedLineRanges(in: string, selection: selection).first ?? NSRange(location: selection.location, length: 0)
        let lineText = string.substring(with: line)
        let isRule = MarkdownSourceAnalyzer.tokens(in: lineText).contains { if case .thematicBreak = $0.kind { true } else { false } }
        if isRule {
            return replacing(source, edits: [.init(range: line, replacement: "")], selection: NSRange(location: line.location, length: 0))
        }
        if lineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return replacing(source, edits: [.init(range: line, replacement: "---")], selection: NSRange(location: line.location + 3, length: 0))
        }
        let insertion = NSMaxRange(line)
        let newline = preferredNewline(in: source)
        let prefix = insertion > 0 && (string.character(at: insertion - 1) == 0x0A || string.character(at: insertion - 1) == 0x0D)
            ? newline
            : newline + newline
        let replacement = prefix + "---"
        return replacing(source, edits: [.init(range: NSRange(location: insertion, length: 0), replacement: replacement)], selection: NSRange(location: insertion + (replacement as NSString).length, length: 0))
    }

    private static func listKind(in line: NSString) -> MarkdownListKind? {
        guard let match = listPrefixExpression.firstMatch(in: line as String, range: NSRange(location: 0, length: line.length)) else { return nil }
        let marker = line.substring(with: match.range)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if marker.range(of: #"^[-+*]\s+\[[xX]\]"#, options: .regularExpression) != nil { return .checklist(checked: true) }
        if marker.range(of: #"^[-+*]\s+\[ \]"#, options: .regularExpression) != nil { return .checklist(checked: false) }
        if marker.range(of: #"^\d+[.)]"#, options: .regularExpression) != nil { return .numbered }
        return .bullet
    }

    private static func listKindsMatch(_ lhs: MarkdownListKind?, _ rhs: MarkdownListKind) -> Bool {
        switch (lhs, rhs) {
        case (.bullet?, .bullet), (.numbered?, .numbered), (.checklist?, .checklist): true
        default: false
        }
    }

    private static func selectedLineRanges(in source: NSString, selection: NSRange) -> [NSRange] {
        if source.length == 0 { return [NSRange(location: 0, length: 0)] }
        if selection.length == 0,
           selection.location == source.length,
           [0x0A, 0x0D].contains(source.character(at: source.length - 1)) {
            return [NSRange(location: source.length, length: 0)]
        }
        let start = min(selection.location, source.length - 1)
        var end = min(NSMaxRange(selection), source.length)
        if selection.length > 0, end > selection.location, end < source.length {
            let previous = source.character(at: end - 1)
            if previous == 0x0A || previous == 0x0D { end -= 1 }
        }
        let lineSpan = source.lineRange(for: NSRange(location: start, length: max(0, end - start)))
        var ranges: [NSRange] = []
        var location = lineSpan.location
        while location < NSMaxRange(lineSpan) && location < source.length {
            let full = source.lineRange(for: NSRange(location: location, length: 0))
            var contentEnd = NSMaxRange(full)
            while contentEnd > full.location {
                let character = source.character(at: contentEnd - 1)
                if character == 0x0A || character == 0x0D { contentEnd -= 1 } else { break }
            }
            ranges.append(NSRange(location: full.location, length: contentEnd - full.location))
            location = NSMaxRange(full)
        }
        if ranges.isEmpty { ranges.append(NSRange(location: min(selection.location, source.length), length: 0)) }
        return ranges
    }

    private static func replacing(_ source: String, edits: [TextEdit], mappedSelection selection: NSRange) -> MarkdownSourceEditResult {
        let mapped = map(selection: selection, through: edits)
        return replacing(source, edits: edits, selection: mapped)
    }

    private static func replacing(_ source: String, edits: [TextEdit], selection: NSRange) -> MarkdownSourceEditResult {
        guard !edits.isEmpty else { return .init(source: source, selection: selection) }
        let mutable = NSMutableString(string: source)
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
            mutable.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        return .init(source: mutable as String, selection: clamped(selection, to: mutable.length))
    }

    private static func map(selection: NSRange, through edits: [TextEdit]) -> NSRange {
        let sorted = edits.sorted { $0.range.location < $1.range.location }
        let start = map(position: selection.location, affinityAfterEdit: false, through: sorted)
        let end = map(position: NSMaxRange(selection), affinityAfterEdit: true, through: sorted)
        return NSRange(location: start, length: max(0, end - start))
    }

    private static func map(position: Int, affinityAfterEdit: Bool, through edits: [TextEdit]) -> Int {
        var mapped = position
        var accumulatedDelta = 0
        for edit in edits {
            let replacementLength = (edit.replacement as NSString).length
            let start = edit.range.location
            let end = NSMaxRange(edit.range)
            if position < start || (position == start && !affinityAfterEdit) { break }
            if position > end || (position == end && affinityAfterEdit) {
                accumulatedDelta += replacementLength - edit.range.length
                mapped = position + accumulatedDelta
                continue
            }
            mapped = start + accumulatedDelta + (affinityAfterEdit ? replacementLength : 0)
            break
        }
        return max(0, mapped)
    }

    private static func leadingIndentLength(in line: NSString, maximum: Int?) -> Int {
        var length = 0
        while length < line.length, maximum.map({ length < $0 }) ?? true {
            let character = line.character(at: length)
            guard character == 0x20 || character == 0x09 else { break }
            length += 1
        }
        return length
    }

    private static func longestBacktickRun(in string: String) -> Int {
        var maximum = 0
        var current = 0
        for character in string {
            if character == "`" { current += 1; maximum = max(maximum, current) }
            else { current = 0 }
        }
        return maximum
    }

    private static func preferredNewline(in source: String) -> String {
        source.contains("\r\n") ? "\r\n" : "\n"
    }

    private static func clamped(_ range: NSRange, to length: Int) -> NSRange {
        let location = max(0, min(range.location, length))
        return NSRange(location: location, length: max(0, min(range.length, length - location)))
    }
}

struct MarkdownTextDelta: Equatable, Sendable {
    let range: NSRange
    let replacement: String

    static func between(_ old: String, and new: String) -> MarkdownTextDelta? {
        guard !MarkdownSourceIdentity.exactlyEqual(old, new) else { return nil }
        // Compare extended grapheme clusters so the replacement never splits a
        // surrogate pair, combining sequence, or CRLF character boundary.
        let oldCharacters = Array(old)
        let newCharacters = Array(new)
        var prefix = 0
        let sharedLength = min(oldCharacters.count, newCharacters.count)
        while prefix < sharedLength, charactersExactlyEqual(oldCharacters[prefix], newCharacters[prefix]) { prefix += 1 }

        var suffix = 0
        while suffix < oldCharacters.count - prefix,
              suffix < newCharacters.count - prefix,
              charactersExactlyEqual(
                oldCharacters[oldCharacters.count - suffix - 1],
                newCharacters[newCharacters.count - suffix - 1]
              ) {
            suffix += 1
        }
        let oldPrefixLength = String(oldCharacters[..<prefix]).utf16.count
        let oldMiddleEnd = oldCharacters.count - suffix
        let newMiddleEnd = newCharacters.count - suffix
        let oldMiddleLength = String(oldCharacters[prefix..<oldMiddleEnd]).utf16.count
        let replacement = String(newCharacters[prefix..<newMiddleEnd])
        return .init(range: NSRange(location: oldPrefixLength, length: oldMiddleLength), replacement: replacement)
    }

    private static func charactersExactlyEqual(_ lhs: Character, _ rhs: Character) -> Bool {
        String(lhs).utf8.elementsEqual(String(rhs).utf8)
    }

    func mapping(_ selection: NSRange) -> NSRange {
        let replacementLength = (replacement as NSString).length
        let delta = replacementLength - range.length
        let editEnd = NSMaxRange(range)
        if selection.length == 0 {
            let caret: Int
            if selection.location < range.location {
                caret = selection.location
            } else if selection.location >= editEnd {
                caret = selection.location + delta
            } else {
                caret = range.location + replacementLength
            }
            return NSRange(location: max(0, caret), length: 0)
        }

        let selectionEnd = NSMaxRange(selection)
        if selectionEnd <= range.location { return selection }
        if selection.location >= editEnd {
            return NSRange(location: max(0, selection.location + delta), length: selection.length)
        }
        let start = selection.location < range.location ? selection.location : range.location
        let end = selectionEnd > editEnd ? selectionEnd + delta : range.location + replacementLength
        return NSRange(location: max(0, start), length: max(0, end - start))
    }
}

@MainActor
struct MarkdownEditorPresentationStyle: Equatable {
    let fontFamily: DocumentFontFamily
    let bodyPointSize: CGFloat
    let lineHeightMultiplier: CGFloat
    let paragraphSpacing: CGFloat

    init(_ style: DocumentStyle) {
        fontFamily = style.fontFamily
        bodyPointSize = CGFloat(style.bodyPointSize)
        lineHeightMultiplier = CGFloat(style.lineHeightMultiplier)
        paragraphSpacing = CGFloat(style.paragraphSpacing)
    }

    var bodyFont: NSFont {
        switch fontFamily {
        case .system:
            return .systemFont(ofSize: bodyPointSize)
        case .serif:
            let base = NSFontDescriptor.preferredFontDescriptor(forTextStyle: .body)
            guard let descriptor = base.withDesign(.serif) else { return .systemFont(ofSize: bodyPointSize) }
            return NSFont(descriptor: descriptor, size: bodyPointSize) ?? .systemFont(ofSize: bodyPointSize)
        case .rounded:
            let base = NSFontDescriptor.preferredFontDescriptor(forTextStyle: .body)
            guard let descriptor = base.withDesign(.rounded) else { return .systemFont(ofSize: bodyPointSize) }
            return NSFont(descriptor: descriptor, size: bodyPointSize) ?? .systemFont(ofSize: bodyPointSize)
        case .monospaced:
            return .monospacedSystemFont(ofSize: bodyPointSize, weight: .regular)
        }
    }

    var sourceFont: NSFont { .monospacedSystemFont(ofSize: max(12, bodyPointSize - 2), weight: .regular) }

    func headingFont(level: Int) -> NSFont {
        let scale: CGFloat
        switch level {
        case 1: scale = 1.78
        case 2: scale = 1.48
        case 3: scale = 1.27
        case 4: scale = 1.13
        case 5: scale = 1.04
        default: scale = 1
        }
        let size = bodyPointSize * scale
        let descriptor = bodyFont.fontDescriptor.addingAttributes([
            .traits: [NSFontDescriptor.TraitKey.weight: level <= 2 ? NSFont.Weight.bold.rawValue : NSFont.Weight.semibold.rawValue]
        ])
        return NSFont(descriptor: descriptor, size: size) ?? .boldSystemFont(ofSize: size)
    }
}

@MainActor
enum MarkdownSourcePresentation {
    /// Semantic styling above this size would monopolize TextKit long enough
    /// to feel like a mode-switch stall. Oversized documents still receive the
    /// selected readable base typography and remain fully editable/source exact.
    static let maximumParsedUTF16Length = 100_000

    static func apply(
        to storage: NSTextStorage,
        style: MarkdownEditorPresentationStyle,
        showsSource: Bool,
        activeParagraphRange: NSRange?,
        includesSemantics: Bool = true
    ) {
        let source = storage.string
        let fullRange = NSRange(location: 0, length: storage.length)
        let font = showsSource ? style.sourceFont : style.bodyFont
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = max(1, style.lineHeightMultiplier)
        paragraph.paragraphSpacing = showsSource ? 0 : max(0, style.paragraphSpacing)
        paragraph.lineBreakMode = .byWordWrapping

        storage.beginEditing()
        storage.setAttributes([
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ], range: fullRange)

        guard !showsSource,
              includesSemantics,
              storage.length <= maximumParsedUTF16Length else {
            storage.endEditing()
            return
        }

        for token in MarkdownSourceAnalyzer.tokens(in: source) {
            guard NSMaxRange(token.range) <= storage.length else { continue }
            switch token.kind {
            case .heading(let level):
                storage.addAttribute(.font, value: style.headingFont(level: level), range: token.contentRange)
            case .strong:
                applyFontTrait(.boldFontMask, to: storage, range: token.contentRange)
            case .emphasis:
                applyFontTrait(.italicFontMask, to: storage, range: token.contentRange)
            case .strikethrough:
                storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue], range: token.contentRange)
            case .inlineCode:
                storage.addAttributes([
                    .font: NSFont.monospacedSystemFont(ofSize: max(11, style.bodyPointSize - 1), weight: .regular),
                    .backgroundColor: NSColor.quaternaryLabelColor,
                ], range: token.contentRange)
            case .link(let destination, let isAllowed):
                if isAllowed, let url = URL(string: destination) {
                    storage.addAttributes([
                        .link: url,
                        .foregroundColor: NSColor.linkColor,
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                    ], range: token.contentRange)
                }
            case .list:
                let listParagraph = paragraph.mutableCopy() as! NSMutableParagraphStyle
                listParagraph.firstLineHeadIndent = 0
                listParagraph.headIndent = style.bodyPointSize * 1.35
                storage.addAttribute(.paragraphStyle, value: listParagraph, range: token.range)
            case .blockquote:
                let quoteParagraph = paragraph.mutableCopy() as! NSMutableParagraphStyle
                quoteParagraph.firstLineHeadIndent = style.bodyPointSize * 0.7
                quoteParagraph.headIndent = style.bodyPointSize * 0.7
                storage.addAttributes([
                    .paragraphStyle: quoteParagraph,
                    .foregroundColor: NSColor.secondaryLabelColor,
                ], range: token.contentRange)
            case .fencedCode:
                storage.addAttributes([
                    .font: NSFont.monospacedSystemFont(ofSize: max(11, style.bodyPointSize - 1), weight: .regular),
                    .backgroundColor: NSColor.quaternaryLabelColor,
                ], range: token.contentRange)
            case .thematicBreak:
                storage.addAttribute(.foregroundColor, value: NSColor.separatorColor, range: token.range)
            }

            for markerRange in token.markerRanges where NSMaxRange(markerRange) <= storage.length {
                if let attributes = semanticMarkerAttributes(for: token.kind, style: style) {
                    storage.addAttributes(attributes, range: markerRange)
                    continue
                }
                let isActive = activeParagraphRange.map { NSIntersectionRange($0, markerRange).length > 0 } ?? false
                storage.addAttributes([
                    // Inactive syntax is visually collapsed but remains real,
                    // selectable source. Moving the caret into its paragraph
                    // restores a normal editing size immediately.
                    .font: NSFont.monospacedSystemFont(ofSize: isActive ? max(11, style.bodyPointSize - 2) : max(2, style.bodyPointSize * 0.13), weight: .regular),
                    .foregroundColor: isActive
                        ? NSColor.tertiaryLabelColor
                        : NSColor.quaternaryLabelColor.withAlphaComponent(0.24),
                ], range: markerRange)
            }
        }
        storage.endEditing()
    }

    /// Inline punctuation can recede in Page mode, but block markers carry
    /// meaning of their own. Keep checkboxes, list bullets, quote cues, rules,
    /// and code fences visible without replacing a single source character.
    private static func semanticMarkerAttributes(
        for kind: MarkdownSourceTokenKind,
        style: MarkdownEditorPresentationStyle
    ) -> [NSAttributedString.Key: Any]? {
        switch kind {
        case .list:
            return [
                .font: style.bodyFont,
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        case .blockquote:
            return [
                .font: NSFont.monospacedSystemFont(ofSize: style.bodyPointSize, weight: .semibold),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
        case .thematicBreak:
            return [
                .font: NSFont.monospacedSystemFont(ofSize: max(11, style.bodyPointSize - 2), weight: .regular),
                .foregroundColor: NSColor.separatorColor,
            ]
        case .fencedCode:
            return [
                .font: NSFont.monospacedSystemFont(ofSize: max(11, style.bodyPointSize - 2), weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
                .backgroundColor: NSColor.quaternaryLabelColor,
            ]
        default:
            return nil
        }
    }

    private static func applyFontTrait(_ trait: NSFontTraitMask, to storage: NSTextStorage, range: NSRange) {
        storage.enumerateAttribute(.font, in: range) { value, runRange, _ in
            let font = value as? NSFont ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: runRange)
        }
    }
}
