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
    case table
}

/// A semantic Markdown span. All ranges use NSString/UTF-16 coordinates, matching TextKit.
/// `markerRanges` identifies syntax which can be visually de-emphasized without changing bytes.
struct MarkdownSourceToken: Equatable, Sendable {
    let kind: MarkdownSourceTokenKind
    let range: NSRange
    let contentRange: NSRange
    let markerRanges: [NSRange]
    /// Exact UTF-16 range of the single task-state source character (` `,
    /// `x`, or `X`). Non-checklist tokens leave this unset.
    let checklistStateRange: NSRange?

    init(
        kind: MarkdownSourceTokenKind,
        range: NSRange,
        contentRange: NSRange,
        markerRanges: [NSRange],
        checklistStateRange: NSRange? = nil
    ) {
        self.kind = kind
        self.range = range
        self.contentRange = contentRange
        self.markerRanges = markerRanges
        self.checklistStateRange = checklistStateRange
    }
}

/// Source-exact task metadata used by both the transformer and Page-mode
/// controls. Every range is UTF-16 and points into the same source revision.
struct MarkdownChecklistItem: Equatable, Sendable {
    let lineRange: NSRange
    let markerRange: NSRange
    let stateRange: NSRange
    let contentRange: NSRange
    let isChecked: Bool
}

enum MarkdownPageBlockDecorationKind: Equatable, Sendable {
    case fencedCode
    case thematicBreak
    case table
}

/// Presentation-only block geometry consumed by the AppKit text view. The
/// source range remains canonical Markdown; the view draws the page treatment
/// behind those glyphs without inserting attachments or replacement text.
struct MarkdownPageBlockDecoration: Equatable, Sendable {
    let kind: MarkdownPageBlockDecorationKind
    let range: NSRange
    let headerRange: NSRange?

    init(
        kind: MarkdownPageBlockDecorationKind,
        range: NSRange,
        headerRange: NSRange? = nil
    ) {
        self.kind = kind
        self.range = range
        self.headerRange = headerRange
    }
}

/// Presentation-only metadata for a native checkbox layered over unchanged
/// Markdown glyphs. It never enters the text storage or persisted source.
struct MarkdownPageChecklistDecoration: Equatable, Sendable {
    let lineRange: NSRange
    let markerRange: NSRange
    let stateRange: NSRange
    let contentRange: NSRange
    let isChecked: Bool

    init(
        lineRange: NSRange,
        markerRange: NSRange,
        stateRange: NSRange,
        contentRange: NSRange,
        isChecked: Bool
    ) {
        self.lineRange = lineRange
        self.markerRange = markerRange
        self.stateRange = stateRange
        self.contentRange = contentRange
        self.isChecked = isChecked
    }

    init(item: MarkdownChecklistItem) {
        self.init(
            lineRange: item.lineRange,
            markerRange: item.markerRange,
            stateRange: item.stateRange,
            contentRange: item.contentRange,
            isChecked: item.isChecked
        )
    }
}

struct MarkdownPagePresentationResult: Equatable, Sendable {
    let blockDecorations: [MarkdownPageBlockDecoration]
    let checklistDecorations: [MarkdownPageChecklistDecoration]

    static let empty = MarkdownPagePresentationResult(blockDecorations: [], checklistDecorations: [])
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

    /// A lightweight, fence-aware pass used to keep Page-mode task controls
    /// synchronized immediately while full semantic styling is debounced.
    static func checklistItems(in source: String) -> [MarkdownChecklistItem] {
        let string = source as NSString
        let sourceLines = lines(in: string)
        var items: [MarkdownChecklistItem] = []
        var openFence: (character: Character, length: Int)?

        for line in sourceLines {
            if let match = firstMatch(fenceExpression, in: line.text),
               let markerRange = capture(match, 1, offset: line.range.location) {
                let marker = string.substring(with: markerRange)
                if let fence = openFence {
                    let suffix = capture(match, 2, in: line.text as NSString) ?? ""
                    if marker.first == fence.character,
                       marker.utf16.count >= fence.length,
                       suffix.allSatisfy({ $0 == " " || $0 == "\t" }) {
                        openFence = nil
                    }
                } else if let character = marker.first {
                    openFence = (character, marker.utf16.count)
                }
                continue
            }

            guard openFence == nil,
                  let match = firstMatch(taskExpression, in: line.text),
                  let markerRange = capture(match, 2, offset: line.range.location),
                  let stateRange = capture(match, 3, offset: line.range.location),
                  let state = capture(match, 3, in: line.text as NSString),
                  let contentRange = capture(match, 4, offset: line.range.location) else { continue }
            items.append(.init(
                lineRange: line.range,
                markerRange: markerRange,
                stateRange: stateRange,
                contentRange: contentRange,
                isChecked: state.lowercased() == "x"
            ))
        }
        return items
    }

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
                          let markerRange = capture(match, 1, offset: candidate.range.location),
                          let suffix = capture(match, 2, in: candidate.text as NSString),
                          suffix.allSatisfy({ $0 == " " || $0 == "\t" }) else { continue }
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

        index = 0
        while index + 1 < lines.count {
            let header = lines[index]
            let delimiter = lines[index + 1]
            guard !intersectsAny(header.range, fencedRanges),
                  !intersectsAny(delimiter.range, fencedRanges),
                  let headerCells = tableCells(in: header.text),
                  headerCells.count >= 2,
                  let delimiterCells = tableCells(in: delimiter.text),
                  delimiterCells.count == headerCells.count,
                  delimiterCells.allSatisfy(isTableDelimiterCell) else {
                index += 1
                continue
            }

            var finalIndex = index + 1
            while finalIndex + 1 < lines.count {
                let candidate = lines[finalIndex + 1]
                guard !intersectsAny(candidate.range, fencedRanges),
                      let cells = tableCells(in: candidate.text),
                      cells.count == headerCells.count else { break }
                finalIndex += 1
            }

            let end = NSMaxRange(lines[finalIndex].fullRange)
            let tableRange = NSRange(
                location: header.range.location,
                length: max(0, end - header.range.location)
            )
            var markers = tableSeparatorRanges(in: header)
            markers.append(delimiter.range)
            if finalIndex > index + 1 {
                for rowIndex in (index + 2)...finalIndex {
                    markers.append(contentsOf: tableSeparatorRanges(in: lines[rowIndex]))
                }
            }
            tokens.append(.init(
                kind: .table,
                range: tableRange,
                contentRange: tableRange,
                markerRanges: markers
            ))
            index = finalIndex + 1
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
               let stateRange = capture(match, 3, offset: line.range.location),
               let state = capture(match, 3, in: line.text as NSString),
               let content = capture(match, 4, offset: line.range.location) {
                tokens.append(.init(
                    kind: .list(.checklist(checked: state.lowercased() == "x")),
                    range: line.range,
                    contentRange: content,
                    markerRanges: [marker],
                    checklistStateRange: stateRange
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

    private static func tableCells(in line: String) -> [String]? {
        let source = line as NSString
        var cells: [String] = []
        var start = 0
        var sawSeparator = false
        var index = 0
        while index < source.length {
            guard source.character(at: index) == 0x7C else {
                index += 1
                continue
            }
            var backslashCount = 0
            var cursor = index
            while cursor > 0, source.character(at: cursor - 1) == 0x5C {
                backslashCount += 1
                cursor -= 1
            }
            guard backslashCount.isMultiple(of: 2) else {
                index += 1
                continue
            }
            sawSeparator = true
            cells.append(source.substring(with: NSRange(location: start, length: index - start)))
            start = index + 1
            index += 1
        }
        guard sawSeparator else { return nil }
        cells.append(source.substring(from: start))
        if cells.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            cells.removeFirst()
        }
        if cells.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            cells.removeLast()
        }
        return cells.isEmpty ? nil : cells
    }

    private static func isTableDelimiterCell(_ cell: String) -> Bool {
        let trimmed = cell.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
    }

    private static func tableSeparatorRanges(in line: Line) -> [NSRange] {
        let source = line.text as NSString
        var ranges: [NSRange] = []
        var index = 0
        while index < source.length {
            if source.character(at: index) == 0x7C {
                var backslashCount = 0
                var cursor = index
                while cursor > 0, source.character(at: cursor - 1) == 0x5C {
                    backslashCount += 1
                    cursor -= 1
                }
                if backslashCount.isMultiple(of: 2) {
                    ranges.append(NSRange(location: line.range.location + index, length: 1))
                }
            }
            index += 1
        }
        return ranges
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

    /// NSTextStorage can expose a Cocoa-backed String whose bytes still share
    /// mutable storage. Materialize a byte-exact Swift value before retaining
    /// it across a TextKit mutation or an asynchronous boundary.
    static func detachedCopy(_ source: String) -> String {
        String(decoding: Array(source.utf8), as: UTF8.self)
    }
}

enum MarkdownSourceCommandTransformer {
    private struct TextEdit {
        let range: NSRange
        let replacement: String
    }

    private struct BlockLineContext {
        let lineRange: NSRange
        let contentRange: NSRange
        let originalPrefix: String
        let indent: String
    }

    private struct InlineIsolation {
        /// Complete source bytes which must travel together to keep Markdown valid.
        let sourceRange: NSRange
        /// Human-visible content which should remain selected after the edit.
        let visibleRange: NSRange
    }

    private enum InlineIsolationResolution {
        case safe(InlineIsolation)
        case unsafe
    }

    private struct OpenFence {
        let character: unichar
        let markerLength: Int
        let start: Int
    }

    private static let headingPrefixExpression = try! NSRegularExpression(pattern: #"^([\t ]{0,3})#{1,6}[\t ]+"#)
    private static let listPrefixExpression = try! NSRegularExpression(pattern: #"^([\t ]*)(?:(?:[-+*])[\t ]+(?:\[[ xX]\][\t ]+)?|\d+[.)][\t ]+)"#)
    private static let quotePrefixExpression = try! NSRegularExpression(pattern: #"^([\t ]{0,3})>[\t ]?"#)
    private static let styleFenceExpression = try! NSRegularExpression(pattern: #"^ {0,3}(`{3,}|~{3,})(.*)$"#)

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

    /// Toggles one analyzer-validated task state without rewriting any other
    /// source byte. The one-character replacement means every existing UTF-16
    /// selection remains stable, including selections before or after the task.
    static func togglingChecklist(
        in source: String,
        atStateRange requestedStateRange: NSRange,
        selection requestedSelection: NSRange
    ) -> MarkdownSourceEditResult {
        let sourceLength = (source as NSString).length
        let selection = clamped(requestedSelection, to: sourceLength)
        guard requestedStateRange.length == 1,
              NSMaxRange(requestedStateRange) <= sourceLength,
              let item = MarkdownSourceAnalyzer.checklistItems(in: source).first(where: {
                  NSEqualRanges($0.stateRange, requestedStateRange)
              }) else {
            return .init(source: source, selection: selection)
        }

        return replacing(
            source,
            edits: [.init(range: item.stateRange, replacement: item.isChecked ? " " : "x")],
            selection: selection
        )
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
        if selection.length > 0,
           string.substring(with: selection).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .init(source: source, selection: selection)
        }
        guard !intersectsFencedCode(in: source, selection: selection) else {
            return .init(source: source, selection: selection)
        }

        let ranges = selectedLineRanges(in: string, selection: selection)
        let newline = preferredNewline(in: source)
        var edits: [TextEdit] = []
        var singleLineVisibleSelection = selection
        var finalVisibleEndpoint = selection.location
        for lineRange in ranges {
            let context = blockLineContext(in: string, lineRange: lineRange)
            let selectedContent = NSIntersectionRange(selection, context.contentRange)
            if selectedContent.length > 0 {
                finalVisibleEndpoint = NSMaxRange(selectedContent)
            }
            let isPartialContentSelection = selection.length > 0
                && selectedContent.length > 0
                && (selectedContent.location > context.contentRange.location
                    || NSMaxRange(selectedContent) < NSMaxRange(context.contentRange))

            if isPartialContentSelection {
                let isolation: InlineIsolation
                switch inlineIsolation(in: string, context: context, selectedContent: selectedContent) {
                case .safe(let resolved):
                    isolation = resolved
                case .unsafe:
                    return .init(source: source, selection: selection)
                }
                if ranges.count == 1 {
                    singleLineVisibleSelection = isolation.visibleRange
                }
                finalVisibleEndpoint = NSMaxRange(isolation.visibleRange)
                edits.append(contentsOf: partialBlockStyleEdits(
                    in: string,
                    context: context,
                    isolatedSource: isolation.sourceRange,
                    level: level,
                    newline: newline
                ))
                continue
            }

            let line = string.substring(with: lineRange) as NSString
            let match = headingPrefixExpression.firstMatch(in: line as String, range: NSRange(location: 0, length: line.length))
            let indentLength: Int
            if let match { indentLength = match.range(at: 1).length }
            else { indentLength = leadingIndentLength(in: line, maximum: 3) }
            let indent = line.substring(with: NSRange(location: 0, length: indentLength))
            let existingLength = match?.range.length ?? indentLength
            let replacement = indent + (level.map { String(repeating: "#", count: $0) + " " } ?? "")
            guard existingLength != (replacement as NSString).length
                    || line.substring(with: NSRange(location: 0, length: existingLength)) != replacement else {
                continue
            }
            edits.append(.init(
                range: NSRange(location: lineRange.location, length: existingLength),
                replacement: replacement
            ))
        }
        let mappedSelection = mapSelectedContent(singleLineVisibleSelection, through: edits)
        if ranges.count > 1, selection.length > 0 {
            let endpoint = mapSelectedContent(
                NSRange(location: finalVisibleEndpoint, length: 0),
                through: edits
            ).location
            return replacing(source, edits: edits, selection: NSRange(location: endpoint, length: 0))
        }
        return replacing(source, edits: edits, selection: mappedSelection)
    }

    private static func partialBlockStyleEdits(
        in source: NSString,
        context: BlockLineContext,
        isolatedSource: NSRange,
        level: Int?,
        newline: String
    ) -> [TextEdit] {
        var boundaryStart = isolatedSource.location
        while boundaryStart > context.contentRange.location,
              isHorizontalWhitespace(source.character(at: boundaryStart - 1)) {
            boundaryStart -= 1
        }

        var boundaryEnd = NSMaxRange(isolatedSource)
        while boundaryEnd < NSMaxRange(context.contentRange),
              isHorizontalWhitespace(source.character(at: boundaryEnd)) {
            boundaryEnd += 1
        }

        let hasContentBefore = boundaryStart > context.contentRange.location
        let hasContentAfter = boundaryEnd < NSMaxRange(context.contentRange)
        let desiredPrefix = context.indent
            + (level.map { String(repeating: "#", count: $0) + " " } ?? "")
        var edits: [TextEdit] = []

        if hasContentBefore {
            edits.append(.init(
                range: NSRange(location: boundaryStart, length: isolatedSource.location - boundaryStart),
                replacement: newline + desiredPrefix
            ))
        } else {
            edits.append(.init(
                range: NSRange(
                    location: context.lineRange.location,
                    length: isolatedSource.location - context.lineRange.location
                ),
                replacement: desiredPrefix
            ))
        }

        if hasContentAfter {
            edits.append(.init(
                range: NSRange(
                    location: NSMaxRange(isolatedSource),
                    length: boundaryEnd - NSMaxRange(isolatedSource)
                ),
                replacement: newline + context.originalPrefix
            ))
        } else if boundaryEnd > NSMaxRange(isolatedSource) {
            edits.append(.init(
                range: NSRange(
                    location: NSMaxRange(isolatedSource),
                    length: boundaryEnd - NSMaxRange(isolatedSource)
                ),
                replacement: ""
            ))
        }
        return edits
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
        return replacing(
            source,
            edits: edits,
            selection: mapSelectedContent(selection, through: edits)
        )
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
        return replacing(
            source,
            edits: edits,
            selection: mapSelectedContent(selection, through: edits)
        )
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

    private static func blockLineContext(in source: NSString, lineRange: NSRange) -> BlockLineContext {
        let line = source.substring(with: lineRange) as NSString
        let indentLength = leadingIndentLength(in: line, maximum: 3)
        let prefixLength = compoundBlockPrefixLength(in: line) ?? indentLength
        let prefixRange = NSRange(location: lineRange.location, length: prefixLength)
        let contentRange = NSRange(
            location: NSMaxRange(prefixRange),
            length: max(0, NSMaxRange(lineRange) - NSMaxRange(prefixRange))
        )
        return .init(
            lineRange: lineRange,
            contentRange: contentRange,
            originalPrefix: line.substring(with: NSRange(location: 0, length: prefixLength)),
            indent: line.substring(with: NSRange(location: 0, length: indentLength))
        )
    }

    private static func intersectsFencedCode(in source: String, selection: NSRange) -> Bool {
        let string = source as NSString
        guard string.length > 0 else { return false }

        var openFence: OpenFence?
        var location = 0
        while location < string.length {
            let fullRange = string.lineRange(for: NSRange(location: location, length: 0))
            var contentEnd = NSMaxRange(fullRange)
            while contentEnd > fullRange.location {
                let character = string.character(at: contentEnd - 1)
                if character == 0x0A || character == 0x0D { contentEnd -= 1 }
                else { break }
            }
            let lineRange = NSRange(location: fullRange.location, length: contentEnd - fullRange.location)
            let line = string.substring(with: lineRange) as NSString

            if let candidate = fenceCandidate(in: line) {
                if let opening = openFence {
                    if candidate.character == opening.character,
                       candidate.markerLength >= opening.markerLength,
                       candidate.hasWhitespaceOnlySuffix {
                        let protectedRange = NSRange(
                            location: opening.start,
                            length: NSMaxRange(fullRange) - opening.start
                        )
                        if selectionIntersects(selection, protectedRange: protectedRange, includesUpperBound: false) {
                            return true
                        }
                        openFence = nil
                    }
                } else {
                    openFence = .init(
                        character: candidate.character,
                        markerLength: candidate.markerLength,
                        start: lineRange.location
                    )
                }
            }

            if openFence == nil, NSMaxRange(fullRange) > NSMaxRange(selection) {
                return false
            }
            location = NSMaxRange(fullRange)
        }

        guard let opening = openFence else { return false }
        let protectedRange = NSRange(location: opening.start, length: string.length - opening.start)
        return selectionIntersects(selection, protectedRange: protectedRange, includesUpperBound: true)
    }

    private static func inlineIsolation(
        in source: NSString,
        context: BlockLineContext,
        selectedContent: NSRange
    ) -> InlineIsolationResolution {
        let line = source.substring(with: context.lineRange)
        let inlineTokens = MarkdownSourceAnalyzer.tokens(in: line).compactMap { token -> MarkdownSourceToken? in
            guard isInline(token.kind) else { return nil }
            return .init(
                kind: token.kind,
                range: offset(token.range, by: context.lineRange.location),
                contentRange: offset(token.contentRange, by: context.lineRange.location),
                markerRanges: token.markerRanges.map { offset($0, by: context.lineRange.location) }
            )
        }.filter { NSIntersectionRange($0.range, selectedContent).length > 0 }

        guard !inlineTokens.isEmpty else {
            return .safe(.init(sourceRange: selectedContent, visibleRange: selectedContent))
        }

        // Nested or crossing syntax has more than one plausible ownership
        // boundary. A source-preserving block split cannot safely choose one.
        for index in inlineTokens.indices {
            for otherIndex in inlineTokens.indices where otherIndex > index {
                if NSIntersectionRange(inlineTokens[index].range, inlineTokens[otherIndex].range).length > 0 {
                    return .unsafe
                }
            }
        }

        var enclosingToken: MarkdownSourceToken?
        for token in inlineTokens {
            if NSEqualRanges(selectedContent, token.range) {
                guard enclosingToken == nil else { return .unsafe }
                enclosingToken = token
                continue
            }
            if contains(selectedContent, token.range) {
                continue
            }
            if contains(token.range, selectedContent),
               NSEqualRanges(selectedContent, token.contentRange) {
                guard enclosingToken == nil else { return .unsafe }
                enclosingToken = token
                continue
            }
            return .unsafe
        }

        if let enclosingToken {
            return .safe(.init(
                sourceRange: enclosingToken.range,
                visibleRange: enclosingToken.contentRange
            ))
        }
        return .safe(.init(sourceRange: selectedContent, visibleRange: selectedContent))
    }

    private static func compoundBlockPrefixLength(in line: NSString) -> Int? {
        var location = 0
        var foundPrefix = false
        while location < line.length {
            let suffix = line.substring(from: location) as NSString
            let range = NSRange(location: 0, length: suffix.length)
            let candidates: [(NSRegularExpression, Bool)] = [
                (quotePrefixExpression, false),
                (listPrefixExpression, false),
                (headingPrefixExpression, true),
            ]
            guard let candidate = candidates.compactMap({ expression, terminates -> (NSTextCheckingResult, Bool)? in
                guard let match = expression.firstMatch(in: suffix as String, range: range),
                      match.range.location == 0,
                      match.range.length > 0 else { return nil }
                return (match, terminates)
            }).first else { break }
            foundPrefix = true
            location += candidate.0.range.length
            if candidate.1 { break }
        }
        return foundPrefix ? location : nil
    }

    private static func fenceCandidate(in line: NSString) -> (
        character: unichar,
        markerLength: Int,
        hasWhitespaceOnlySuffix: Bool
    )? {
        guard let match = styleFenceExpression.firstMatch(
            in: line as String,
            range: NSRange(location: 0, length: line.length)
        ) else { return nil }
        let markerRange = match.range(at: 1)
        let suffixRange = match.range(at: 2)
        guard markerRange.location != NSNotFound,
              markerRange.length > 0,
              suffixRange.location != NSNotFound else { return nil }
        let suffix = line.substring(with: suffixRange) as NSString
        var index = 0
        while index < suffix.length {
            guard isHorizontalWhitespace(suffix.character(at: index)) else {
                return (line.character(at: markerRange.location), markerRange.length, false)
            }
            index += 1
        }
        return (line.character(at: markerRange.location), markerRange.length, true)
    }

    private static func selectionIntersects(
        _ selection: NSRange,
        protectedRange: NSRange,
        includesUpperBound: Bool
    ) -> Bool {
        if selection.length > 0 {
            return NSIntersectionRange(selection, protectedRange).length > 0
        }
        let upperBound = NSMaxRange(protectedRange)
        return selection.location >= protectedRange.location
            && (selection.location < upperBound || (includesUpperBound && selection.location == upperBound))
    }

    private static func isInline(_ kind: MarkdownSourceTokenKind) -> Bool {
        switch kind {
        case .strong, .emphasis, .strikethrough, .inlineCode, .link:
            true
        default:
            false
        }
    }

    private static func contains(_ outer: NSRange, _ inner: NSRange) -> Bool {
        outer.location <= inner.location && NSMaxRange(inner) <= NSMaxRange(outer)
    }

    private static func offset(_ range: NSRange, by amount: Int) -> NSRange {
        NSRange(location: range.location + amount, length: range.length)
    }

    private static func isHorizontalWhitespace(_ character: unichar) -> Bool {
        character == 0x20 || character == 0x09
    }

    private static func replacing(_ source: String, edits: [TextEdit], mappedSelection selection: NSRange) -> MarkdownSourceEditResult {
        let mapped = map(selection: selection, through: edits)
        return replacing(source, edits: edits, selection: mapped)
    }

    /// Keeps the user's selected source content selected when structural edits
    /// are inserted immediately before or after it. Edits at the leading edge
    /// belong before the content; edits at the trailing edge do not become part
    /// of the selection.
    private static func mapSelectedContent(_ selection: NSRange, through edits: [TextEdit]) -> NSRange {
        let originalEnd = NSMaxRange(selection)
        var mappedStart = selection.location
        var mappedEnd = originalEnd
        for edit in edits {
            let delta = (edit.replacement as NSString).length - edit.range.length
            if NSMaxRange(edit.range) <= selection.location {
                mappedStart += delta
            }
            if edit.range.location < originalEnd {
                mappedEnd += delta
            }
        }
        return NSRange(location: max(0, mappedStart), length: max(0, mappedEnd - mappedStart))
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

    /// Refreshes only task-line presentation and geometry. This bounded pass
    /// avoids stale or blinking Page controls while the full semantic styling
    /// of a long document waits for the typing debounce.
    static func refreshChecklistPresentation(
        in storage: NSTextStorage,
        style: MarkdownEditorPresentationStyle
    ) -> [MarkdownPageChecklistDecoration] {
        guard storage.length <= maximumParsedUTF16Length else { return [] }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = max(1, style.lineHeightMultiplier)
        paragraph.paragraphSpacing = max(0, style.paragraphSpacing)
        paragraph.lineBreakMode = .byWordWrapping
        let items = MarkdownSourceAnalyzer.checklistItems(in: storage.string)
        storage.beginEditing()
        for item in items {
            applyChecklistPresentation(
                to: storage,
                lineRange: item.lineRange,
                markerRange: item.markerRange,
                paragraph: paragraph,
                style: style
            )
        }
        storage.endEditing()
        return items.map(MarkdownPageChecklistDecoration.init(item:))
    }

    @discardableResult
    static func apply(
        to storage: NSTextStorage,
        style: MarkdownEditorPresentationStyle,
        showsSource: Bool,
        includesSemantics: Bool = true
    ) -> [MarkdownPageBlockDecoration] {
        applyDocument(
            to: storage,
            style: style,
            showsSource: showsSource,
            includesSemantics: includesSemantics
        ).blockDecorations
    }

    @discardableResult
    static func applyDocument(
        to storage: NSTextStorage,
        style: MarkdownEditorPresentationStyle,
        showsSource: Bool,
        includesSemantics: Bool = true
    ) -> MarkdownPagePresentationResult {
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
            .foregroundColor: ClaspDesign.Color.documentText,
            .paragraphStyle: paragraph,
        ], range: fullRange)

        guard !showsSource,
              storage.length <= maximumParsedUTF16Length else {
            storage.endEditing()
            return .empty
        }

        // The lightweight task pass keeps native checkboxes synchronized even
        // while a long document's complete semantic pass is debounced.
        if !includesSemantics {
            let checklistDecorations = MarkdownSourceAnalyzer.checklistItems(in: source).map { item in
                applyChecklistPresentation(
                    to: storage,
                    lineRange: item.lineRange,
                    markerRange: item.markerRange,
                    paragraph: paragraph,
                    style: style
                )
                return MarkdownPageChecklistDecoration(item: item)
            }
            storage.endEditing()
            return .init(blockDecorations: [], checklistDecorations: checklistDecorations)
        }

        var blockDecorations: [MarkdownPageBlockDecoration] = []
        var checklistDecorations: [MarkdownPageChecklistDecoration] = []
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
                    .backgroundColor: ClaspDesign.Color.documentCodeBackground,
                ], range: token.contentRange)
            case .link(let destination, let isAllowed):
                if isAllowed, let url = URL(string: destination) {
                    storage.addAttributes([
                        .link: url,
                        .foregroundColor: ClaspDesign.Color.documentLink,
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                    ], range: token.contentRange)
                }
            case .list(let kind):
                let markerRange = token.markerRanges.first
                if case .checklist(let isChecked) = kind,
                   let markerRange,
                   let stateRange = token.checklistStateRange {
                    applyChecklistPresentation(
                        to: storage,
                        lineRange: token.range,
                        markerRange: markerRange,
                        paragraph: paragraph,
                        style: style
                    )
                    checklistDecorations.append(.init(
                        lineRange: token.range,
                        markerRange: markerRange,
                        stateRange: stateRange,
                        contentRange: token.contentRange,
                        isChecked: isChecked
                    ))
                } else {
                    storage.addAttribute(
                        .paragraphStyle,
                        value: listParagraph(from: paragraph, style: style),
                        range: token.range
                    )
                }
            case .blockquote:
                let quoteParagraph = paragraph.mutableCopy() as! NSMutableParagraphStyle
                quoteParagraph.firstLineHeadIndent = style.bodyPointSize * 0.7
                quoteParagraph.headIndent = style.bodyPointSize * 0.7
                storage.addAttributes([
                    .paragraphStyle: quoteParagraph,
                    .foregroundColor: ClaspDesign.Color.documentSecondaryText,
                ], range: token.contentRange)
            case .fencedCode:
                storage.addAttribute(
                    .font,
                    value: NSFont.monospacedSystemFont(ofSize: max(11, style.bodyPointSize - 1), weight: .regular),
                    range: token.contentRange
                )
                blockDecorations.append(.init(kind: .fencedCode, range: token.range))
            case .thematicBreak:
                blockDecorations.append(.init(kind: .thematicBreak, range: token.range))
            case .table:
                let sourceString = source as NSString
                let headerLine = sourceString.lineRange(for: NSRange(location: token.range.location, length: 0))
                let headerEnd = min(NSMaxRange(headerLine), storage.length)
                var visibleHeaderEnd = headerEnd
                while visibleHeaderEnd > headerLine.location {
                    let character = sourceString.character(at: visibleHeaderEnd - 1)
                    if character == 0x0A || character == 0x0D { visibleHeaderEnd -= 1 } else { break }
                }
                let headerRange = NSRange(
                    location: headerLine.location,
                    length: max(0, visibleHeaderEnd - headerLine.location)
                )
                applyFontTrait(.boldFontMask, to: storage, range: headerRange)
                let tableParagraph = paragraph.mutableCopy() as! NSMutableParagraphStyle
                tableParagraph.lineHeightMultiple = max(1.15, min(1.35, style.lineHeightMultiplier))
                tableParagraph.paragraphSpacing = max(3, style.paragraphSpacing * 0.35)
                storage.addAttribute(.paragraphStyle, value: tableParagraph, range: token.range)
                blockDecorations.append(.init(
                    kind: .table,
                    range: token.range,
                    headerRange: headerRange
                ))
            }

            for markerRange in token.markerRanges where NSMaxRange(markerRange) <= storage.length {
                if let attributes = semanticMarkerAttributes(for: token.kind, style: style) {
                    storage.addAttributes(attributes, range: markerRange)
                    continue
                }
                storage.addAttributes([
                    // Recognized inline Markdown remains hidden in Page mode.
                    // The same compact metrics are used whether or not the
                    // editor has focus, so clicking cannot rewrap or move the
                    // page while punctuation occupies negligible space.
                    .font: NSFont.monospacedSystemFont(ofSize: max(2, style.bodyPointSize * 0.13), weight: .regular),
                    .foregroundColor: NSColor.clear,
                ], range: markerRange)
            }
        }
        storage.endEditing()
        return .init(
            blockDecorations: blockDecorations,
            checklistDecorations: checklistDecorations
        )
    }

    /// List and quote markers carry meaning of their own, so Page mode keeps
    /// them legible. Rules and code fences recede because the text view draws
    /// their document treatment without replacing a source character.
    private static func semanticMarkerAttributes(
        for kind: MarkdownSourceTokenKind,
        style: MarkdownEditorPresentationStyle
    ) -> [NSAttributedString.Key: Any]? {
        switch kind {
        case .list(.checklist):
            return [
                // Keep the exact marker's metrics in layout so checked-state
                // changes cannot rewrap the document. A native checkbox is
                // layered over these transparent glyphs by MarkdownPageTextView.
                .font: checklistMarkerFont(style: style),
                .foregroundColor: NSColor.clear,
            ]
        case .list:
            return [
                .font: style.bodyFont,
                .foregroundColor: ClaspDesign.Color.documentSecondaryText,
            ]
        case .blockquote:
            return [
                .font: NSFont.monospacedSystemFont(ofSize: style.bodyPointSize, weight: .semibold),
                .foregroundColor: ClaspDesign.Color.documentSecondaryText,
            ]
        case .thematicBreak:
            return [
                .font: NSFont.monospacedSystemFont(ofSize: max(2, style.bodyPointSize * 0.13), weight: .regular),
                .foregroundColor: NSColor.clear,
            ]
        case .fencedCode:
            return [
                .font: NSFont.monospacedSystemFont(ofSize: max(2, style.bodyPointSize * 0.13), weight: .regular),
                .foregroundColor: NSColor.clear,
            ]
        case .table:
            return [
                .font: NSFont.monospacedSystemFont(ofSize: max(2, style.bodyPointSize * 0.13), weight: .regular),
                .foregroundColor: NSColor.clear,
            ]
        default:
            return nil
        }
    }

    private static func listParagraph(
        from paragraph: NSParagraphStyle,
        style: MarkdownEditorPresentationStyle
    ) -> NSParagraphStyle {
        let listParagraph = paragraph.mutableCopy() as! NSMutableParagraphStyle
        listParagraph.firstLineHeadIndent = 0
        listParagraph.headIndent = style.bodyPointSize * 1.35
        return listParagraph
    }

    private static func applyChecklistPresentation(
        to storage: NSTextStorage,
        lineRange: NSRange,
        markerRange: NSRange,
        paragraph: NSParagraphStyle,
        style: MarkdownEditorPresentationStyle
    ) {
        guard NSMaxRange(lineRange) <= storage.length,
              NSMaxRange(markerRange) <= storage.length else { return }
        storage.addAttribute(
            .paragraphStyle,
            value: listParagraph(from: paragraph, style: style),
            range: lineRange
        )
        storage.addAttributes([
            // A fixed-width marker makes ` `, `x`, and `X` exactly
            // interchangeable in TextKit geometry for every document font.
            .font: checklistMarkerFont(style: style),
            .foregroundColor: NSColor.clear,
        ], range: markerRange)
    }

    private static func checklistMarkerFont(style: MarkdownEditorPresentationStyle) -> NSFont {
        // The six source characters in `- [ ] ` remain present and fixed-width
        // so state toggles never reflow the document. Size the transparent run
        // to one native checkbox plus the intended text gap instead of letting
        // six body-sized monospace glyphs create an oversized blank gutter.
        let referenceSize: CGFloat = 10
        let reference = NSFont.monospacedSystemFont(ofSize: referenceSize, weight: .regular)
        let referenceWidth = ("- [ ] " as NSString).size(withAttributes: [.font: reference]).width
        let targetWidth = ClaspDesign.Metrics.checklistControlSize + ClaspDesign.Metrics.checklistTextGap
        let resolvedSize = referenceWidth > 0
            ? referenceSize * targetWidth / referenceWidth
            : referenceSize
        return .monospacedSystemFont(ofSize: resolvedSize, weight: .regular)
    }

    private static func applyFontTrait(_ trait: NSFontTraitMask, to storage: NSTextStorage, range: NSRange) {
        storage.enumerateAttribute(.font, in: range) { value, runRange, _ in
            let font = value as? NSFont ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: runRange)
        }
    }
}
