import Foundation
import XCTest
@testable import PersonalNotepad

/// Release-level source contracts for every control exposed by the Page toolbar.
///
/// The AppKit interaction suite separately covers focus, selection, viewport,
/// layout, undo/redo, checkboxes, and Page/Markdown switching. This table makes
/// the Markdown result of every visible command auditable in one place.
final class EditorProductionQAMatrixTests: XCTestCase {
    private struct Fixture {
        let name: String
        let command: RichEditorCommand
        let originalBlock: String
        let expectedBlock: String
        let selectionText: String
        var preservesVisibleSelection = true
    }

    func testEveryVisibleEditorCommandProducesExactPortableMarkdown() throws {
        let names = fixtures.map(\.name)
        XCTAssertEqual(names.count, 18)
        XCTAssertEqual(Set(names).count, names.count, "Every toolbar command needs one unique QA row")

        for fixture in fixtures {
            let prefix = "KEEP BEFORE — 😀\r\n"
            let suffix = "\r\nKEEP AFTER — cafe\u{301}"
            let source = prefix + fixture.originalBlock + suffix
            let selection = try range(of: fixture.selectionText, in: source)
            let result = MarkdownSourceCommandTransformer.applying(
                fixture.command,
                to: source,
                selection: selection
            )
            let expected = prefix + fixture.expectedBlock + suffix

            XCTAssertEqual(
                Data(result.source.utf8),
                Data(expected.utf8),
                "\(fixture.name) must change only the intended Markdown"
            )
            XCTAssertTrue(
                result.source.hasPrefix(prefix) && result.source.hasSuffix(suffix),
                "\(fixture.name) must preserve surrounding Unicode and CRLF bytes"
            )
            XCTAssertLessThanOrEqual(
                NSMaxRange(result.selection),
                (result.source as NSString).length,
                "\(fixture.name) must return an in-bounds selection"
            )

            if fixture.preservesVisibleSelection {
                XCTAssertEqual(
                    (result.source as NSString).substring(with: result.selection),
                    fixture.selectionText,
                    "\(fixture.name) must keep the edited copy selected"
                )
            } else {
                XCTAssertEqual(result.selection.length, 0, "\(fixture.name) returns a stable caret")
            }
        }
    }

    private var fixtures: [Fixture] {
        let value = "Selected cafe\u{301} 👩🏽‍💻"
        return [
            .init(name: "body", command: .body, originalBlock: "### \(value)", expectedBlock: value, selectionText: value),
            .init(name: "heading 1", command: .heading1, originalBlock: value, expectedBlock: "# \(value)", selectionText: value),
            .init(name: "heading 2", command: .heading2, originalBlock: value, expectedBlock: "## \(value)", selectionText: value),
            .init(name: "heading 3", command: .heading3, originalBlock: value, expectedBlock: "### \(value)", selectionText: value),
            .init(name: "heading 4", command: .heading4, originalBlock: value, expectedBlock: "#### \(value)", selectionText: value),
            .init(name: "heading 5", command: .heading5, originalBlock: value, expectedBlock: "##### \(value)", selectionText: value),
            .init(name: "heading 6", command: .heading6, originalBlock: value, expectedBlock: "###### \(value)", selectionText: value),
            .init(name: "bold", command: .bold, originalBlock: value, expectedBlock: "**\(value)**", selectionText: value),
            .init(name: "italic", command: .italic, originalBlock: value, expectedBlock: "*\(value)*", selectionText: value),
            .init(name: "strikethrough", command: .strikethrough, originalBlock: value, expectedBlock: "~~\(value)~~", selectionText: value),
            .init(name: "inline code", command: .inlineCode, originalBlock: value, expectedBlock: "`\(value)`", selectionText: value),
            .init(
                name: "link",
                command: .link("https://example.com/a(test)"),
                originalBlock: value,
                expectedBlock: "[\(value)](<https://example.com/a(test)>)",
                selectionText: value
            ),
            .init(name: "bullet list", command: .bulletList, originalBlock: value, expectedBlock: "- \(value)", selectionText: value),
            .init(name: "numbered list", command: .numberedList, originalBlock: value, expectedBlock: "1. \(value)", selectionText: value),
            .init(name: "checklist", command: .checklist, originalBlock: value, expectedBlock: "- [ ] \(value)", selectionText: value),
            .init(name: "block quote", command: .blockquote, originalBlock: value, expectedBlock: "> \(value)", selectionText: value),
            .init(name: "code block", command: .fencedCode, originalBlock: value, expectedBlock: "```\r\n\(value)\r\n```", selectionText: value),
            .init(
                name: "horizontal rule",
                command: .horizontalRule,
                originalBlock: value,
                expectedBlock: "\(value)\r\n\r\n---",
                selectionText: value,
                preservesVisibleSelection: false
            ),
        ]
    }

    private func range(of substring: String, in source: String) throws -> NSRange {
        let range = (source as NSString).range(of: substring)
        return try XCTUnwrap(range.location == NSNotFound ? nil : range)
    }
}
