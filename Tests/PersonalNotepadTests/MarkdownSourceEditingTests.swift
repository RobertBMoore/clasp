import AppKit
import SwiftUI
import XCTest
@testable import PersonalNotepad

@MainActor
final class MarkdownSourceEditingTests: XCTestCase {
    func testPresentationAttributesNeverChangeCanonicalMarkdownBytes() {
        let source = """
        ---
        title: untouched
        ---
        # Héllo 👋\r
        A [safe](https://example.com?q=1) and <custom data-x=\"1\">node</custom>.
        Footnote[^1], ~~strike~~, $math$, and :::unknown
        [^1]: exact bytes
        """
        let originalBytes = Data(source.utf8)
        let storage = NSTextStorage(string: source)

        MarkdownSourcePresentation.apply(
            to: storage,
            style: MarkdownEditorPresentationStyle(.balanced),
            showsSource: false
        )

        XCTAssertEqual(storage.string, source)
        XCTAssertEqual(Data(storage.string.utf8), originalBytes)
    }

    func testAnalyzerReportsUTF16MarkerAndSemanticRanges() throws {
        let source = "# Title\nText **bold** and *italic* and ~~gone~~ and `code`.\n- [x] shipped\n[Web](https://example.com) [Bad](file:///tmp/x)\n```swift\nlet x = 1\n```"
        let string = source as NSString
        let tokens = MarkdownSourceAnalyzer.tokens(in: source)

        let heading = try XCTUnwrap(tokens.first { if case .heading(level: 1) = $0.kind { true } else { false } })
        XCTAssertEqual(string.substring(with: heading.contentRange), "Title")
        XCTAssertEqual(heading.markerRanges.map(string.substring(with:)), ["# "])

        let strong = try XCTUnwrap(tokens.first { $0.kind == .strong })
        XCTAssertEqual(string.substring(with: strong.contentRange), "bold")
        XCTAssertEqual(strong.markerRanges.map(string.substring(with:)), ["**", "**"])

        let checklist = try XCTUnwrap(tokens.first { $0.kind == .list(.checklist(checked: true)) })
        XCTAssertEqual(string.substring(with: checklist.contentRange), "shipped")
        XCTAssertEqual(checklist.markerRanges.map(string.substring(with:)), ["- [x] "])
        XCTAssertEqual(checklist.checklistStateRange.map(string.substring(with:)), "x")

        XCTAssertTrue(tokens.contains { $0.kind == .link(destination: "https://example.com", isAllowed: true) })
        XCTAssertTrue(tokens.contains { $0.kind == .link(destination: "file:///tmp/x", isAllowed: false) })

        let fence = try XCTUnwrap(tokens.first { if case .fencedCode(language: "swift") = $0.kind { true } else { false } })
        XCTAssertEqual(string.substring(with: fence.contentRange), "let x = 1\n")
        XCTAssertEqual(fence.markerRanges.map(string.substring(with:)), ["```swift", "```"])
    }

    func testAnalyzerRecognizesGFMTableOutsideFencesWithoutChangingSource() throws {
        let source = """
        Before

        | Name | Status |
        | :--- | ---: |
        | Alpha | Ready |
        | Beta | **Review** |

        ```md
        | Not | A table |
        | --- | --- |
        ```
        After
        """
        let originalBytes = Data(source.utf8)
        let string = source as NSString
        let tokens = MarkdownSourceAnalyzer.tokens(in: source)
        let table = try XCTUnwrap(tokens.first { $0.kind == .table })

        XCTAssertEqual(
            string.substring(with: table.range),
            "| Name | Status |\n| :--- | ---: |\n| Alpha | Ready |\n| Beta | **Review** |\n"
        )
        XCTAssertEqual(string.substring(with: table.contentRange), string.substring(with: table.range))
        XCTAssertEqual(table.markerRanges.map(string.substring(with:)), [
            "|", "|", "|",
            "| :--- | ---: |",
            "|", "|", "|",
            "|", "|", "|",
        ])

        let storage = NSTextStorage(string: source)
        let presentation = MarkdownSourcePresentation.applyDocument(
            to: storage,
            style: MarkdownEditorPresentationStyle(.balanced),
            showsSource: false
        )
        XCTAssertEqual(storage.string, source)
        XCTAssertEqual(Data(storage.string.utf8), originalBytes)
        let tableDecorations = presentation.blockDecorations.filter { $0.kind == .table }
        XCTAssertEqual(tableDecorations.map(\.kind), [.table])
        XCTAssertEqual(tableDecorations.map(\.range), [table.range])
        let tableDecoration = try XCTUnwrap(tableDecorations.first)
        XCTAssertEqual(tableDecoration.headerRange.map(string.substring(with:)), "| Name | Status |")
        for markerRange in table.markerRanges {
            let font = try XCTUnwrap(storage.attribute(.font, at: markerRange.location, effectiveRange: nil) as? NSFont)
            let color = try XCTUnwrap(storage.attribute(.foregroundColor, at: markerRange.location, effectiveRange: nil) as? NSColor)
            XCTAssertLessThan(font.pointSize, 5)
            XCTAssertTrue(color.isEqual(NSColor.clear))
        }
        let headerTextRange = string.range(of: "Name")
        let headerFont = try XCTUnwrap(storage.attribute(.font, at: headerTextRange.location, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: headerFont).contains(.boldFontMask))
    }

    func testChecklistStateToggleIsFenceAwareSourceExactAndSelectionStable() throws {
        let source = "👋 pre\r\n\t*  [ ] task cafe\u{301}\r\n  + [X]\tDone 😀\r\n```md\r\n- [ ] code only\r\n```\r\nordinary [ ]\r\npost"
        let string = source as NSString
        let items = MarkdownSourceAnalyzer.checklistItems(in: source)

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map { string.substring(with: $0.markerRange) }, ["*  [ ] ", "+ [X]\t"])
        XCTAssertEqual(items.map { string.substring(with: $0.stateRange) }, [" ", "X"])
        XCTAssertEqual(items.map(\.isChecked), [false, true])

        let selection = string.range(of: "post")
        let completed = MarkdownSourceCommandTransformer.togglingChecklist(
            in: source,
            atStateRange: items[0].stateRange,
            selection: selection
        )
        XCTAssertEqual(
            Data(completed.source.utf8),
            Data("👋 pre\r\n\t*  [x] task cafe\u{301}\r\n  + [X]\tDone 😀\r\n```md\r\n- [ ] code only\r\n```\r\nordinary [ ]\r\npost".utf8)
        )
        XCTAssertEqual(completed.selection, selection)

        let reopened = MarkdownSourceCommandTransformer.togglingChecklist(
            in: completed.source,
            atStateRange: items[1].stateRange,
            selection: NSRange(location: 0, length: 2)
        )
        XCTAssertEqual((reopened.source as NSString).substring(with: items[1].stateRange), " ")
        XCTAssertEqual(reopened.selection, NSRange(location: 0, length: 2))

        let fencedLine = string.range(of: "- [ ] code only")
        let fencedBrackets = string.range(of: "[ ]", options: [], range: fencedLine)
        let fencedState = NSRange(location: fencedBrackets.location + 1, length: 1)
        let rejected = MarkdownSourceCommandTransformer.togglingChecklist(
            in: source,
            atStateRange: fencedState,
            selection: selection
        )
        XCTAssertEqual(Data(rejected.source.utf8), Data(source.utf8))
        XCTAssertEqual(rejected.selection, selection)
    }

    func testChecklistToggleAcceptsEveryMarkdownBulletAndCheckedSpelling() throws {
        let fixtures: [(source: String, toggled: String)] = [
            ("- [ ] dash", "- [x] dash"),
            ("*\t[x] star", "*\t[ ] star"),
            ("  +  [X]\tplus", "  +  [ ]\tplus"),
        ]

        for fixture in fixtures {
            let item = try XCTUnwrap(MarkdownSourceAnalyzer.checklistItems(in: fixture.source).first)
            let result = MarkdownSourceCommandTransformer.togglingChecklist(
                in: fixture.source,
                atStateRange: item.stateRange,
                selection: item.contentRange
            )
            XCTAssertEqual(Data(result.source.utf8), Data(fixture.toggled.utf8), fixture.source)
            XCTAssertEqual(result.selection, item.contentRange, fixture.source)
        }
    }

    func testAnalyzerComposesInlineSemanticsInsideLinkLabels() {
        let source = "[**Important** and `literal`](https://example.com/a)"
        let tokens = MarkdownSourceAnalyzer.tokens(in: source)

        XCTAssertTrue(tokens.contains { $0.kind == .link(destination: "https://example.com/a", isAllowed: true) })
        XCTAssertTrue(tokens.contains { $0.kind == .strong })
        XCTAssertTrue(tokens.contains { $0.kind == .inlineCode })
    }

    func testHeadingCommandsH1ThroughH6AndBodyMakeMinimalSourceEdits() {
        let levels: [(RichEditorCommand, String)] = [
            (.heading1, "# "), (.heading2, "## "), (.heading3, "### "),
            (.heading4, "#### "), (.heading5, "##### "), (.heading6, "###### "),
        ]
        for (command, prefix) in levels {
            let result = apply(command, to: "  ## Keep *inline*", selecting: "Keep *inline*")
            XCTAssertEqual(result.source, "  \(prefix)Keep *inline*")
        }
        let body = apply(.body, to: "  #### Keep *inline*", selecting: "Keep *inline*")
        XCTAssertEqual(body.source, "  Keep *inline*")

        let afterTerminalNewline = MarkdownSourceCommandTransformer.applying(
            .heading3,
            to: "Existing\n",
            selection: NSRange(location: 9, length: 0)
        )
        XCTAssertEqual(afterTerminalNewline.source, "Existing\n### ")
    }

    func testMidLineHeadingSplitsOnlySelectedCopyAndMapsSelection() {
        let mid = apply(.heading2, to: "Alpha target omega", selecting: "target")
        XCTAssertEqual(mid.source, "Alpha\n## target\nomega")
        XCTAssertEqual((mid.source as NSString).substring(with: mid.selection), "target")

        let padded = apply(.heading2, to: "Alpha \t target  \t omega", selecting: "target")
        XCTAssertEqual(padded.source, "Alpha\n## target\nomega")
        XCTAssertEqual((padded.source as NSString).substring(with: padded.selection), "target")

        let start = apply(.heading2, to: "target omega", selecting: "target")
        XCTAssertEqual(start.source, "## target\nomega")
        XCTAssertEqual((start.source as NSString).substring(with: start.selection), "target")

        let end = apply(.heading2, to: "Alpha target", selecting: "target")
        XCTAssertEqual(end.source, "Alpha\n## target")
        XCTAssertEqual((end.source as NSString).substring(with: end.selection), "target")
    }

    func testPartialHeadingAndBodyPreserveSurroundingBlockSiblings() {
        let paragraphBody = apply(.body, to: "Alpha target omega", selecting: "target")
        XCTAssertEqual(paragraphBody.source, "Alpha\ntarget\nomega")
        XCTAssertEqual((paragraphBody.source as NSString).substring(with: paragraphBody.selection), "target")

        let sameLevel = apply(.heading1, to: "# Alpha target omega", selecting: "target")
        XCTAssertEqual(sameLevel.source, "# Alpha\n# target\n# omega")
        XCTAssertEqual((sameLevel.source as NSString).substring(with: sameLevel.selection), "target")

        let headingToBody = apply(.body, to: "### Alpha target omega", selecting: "target")
        XCTAssertEqual(headingToBody.source, "### Alpha\ntarget\n### omega")
        XCTAssertEqual((headingToBody.source as NSString).substring(with: headingToBody.selection), "target")

        let listToHeading = apply(.heading2, to: "- Alpha target omega", selecting: "target")
        XCTAssertEqual(listToHeading.source, "- Alpha\n## target\n- omega")
        XCTAssertEqual((listToHeading.source as NSString).substring(with: listToHeading.selection), "target")

        let quoteToBody = apply(.body, to: "> Alpha target omega", selecting: "target")
        XCTAssertEqual(quoteToBody.source, "> Alpha\ntarget\n> omega")
        XCTAssertEqual((quoteToBody.source as NSString).substring(with: quoteToBody.selection), "target")
    }

    func testPartialBlockStyleCarriesBalancedInlineMarkdownAndSelectsOnlyVisibleContent() {
        let wrappers = [
            "**target**",
            "__target__",
            "*target*",
            "_target_",
            "~~target~~",
            "`target`",
            "[target](https://example.com/docs)",
        ]

        for wrapped in wrappers {
            let source = "Before \(wrapped) after"
            let heading = apply(.heading2, to: source, selecting: "target")
            XCTAssertEqual(heading.source, "Before\n## \(wrapped)\nafter", wrapped)
            XCTAssertEqual((heading.source as NSString).substring(with: heading.selection), "target", wrapped)

            let body = apply(.body, to: source, selecting: "target")
            XCTAssertEqual(body.source, "Before\n\(wrapped)\nafter", wrapped)
            XCTAssertEqual((body.source as NSString).substring(with: body.selection), "target", wrapped)
        }

        let fullTokenSource = "Before **target** after"
        let fullTokenRange = (fullTokenSource as NSString).range(of: "**target**")
        let fullToken = MarkdownSourceCommandTransformer.applying(
            .heading3,
            to: fullTokenSource,
            selection: fullTokenRange
        )
        XCTAssertEqual(fullToken.source, "Before\n### **target**\nafter")
        XCTAssertEqual((fullToken.source as NSString).substring(with: fullToken.selection), "target")
    }

    func testPartialBlockStyleFailsClosedForAmbiguousCrossingOrNestedInlineMarkdown() {
        let fixtures: [(source: String, selected: String)] = [
            ("Before **target words** after", "target"),
            ("Before **target** after", "target** after"),
            ("Before [**target**](https://example.com) after", "target"),
            ("Before [target words](https://example.com) after", "target"),
            ("Before `target words` after", "target"),
        ]

        for fixture in fixtures {
            let range = (fixture.source as NSString).range(of: fixture.selected)
            XCTAssertNotEqual(range.location, NSNotFound)
            for command in [RichEditorCommand.heading1, .heading6, .body] {
                XCTAssertEqual(
                    MarkdownSourceCommandTransformer.applying(command, to: fixture.source, selection: range),
                    .init(source: fixture.source, selection: range),
                    "\(command) should fail closed for \(fixture.source)"
                )
            }
        }
    }

    func testPartialBlockStylePreservesCompoundQuoteAndListPrefixesForSiblings() {
        let fixtures: [(source: String, expected: String)] = [
            ("> > Alpha target omega", "> > Alpha\n## target\n> > omega"),
            ("> - Alpha target omega", "> - Alpha\n## target\n> - omega"),
            ("  > - [x] Alpha target omega", "  > - [x] Alpha\n  ## target\n  > - [x] omega"),
        ]

        for fixture in fixtures {
            let result = apply(.heading2, to: fixture.source, selecting: "target")
            XCTAssertEqual(result.source, fixture.expected)
            XCTAssertEqual((result.source as NSString).substring(with: result.selection), "target")
        }
    }

    func testMultilinePartialHeadingAppliesStyleToEverySelectedLine() {
        let source = "Alpha one omega\nBeta two gamma"
        let string = source as NSString
        let start = string.range(of: "one").location
        let end = NSMaxRange(string.range(of: "two"))
        let result = MarkdownSourceCommandTransformer.applying(
            .heading3,
            to: source,
            selection: NSRange(location: start, length: end - start)
        )

        XCTAssertEqual(result.source, "Alpha\n### one omega\n### Beta two\ngamma")
        XCTAssertEqual(result.selection, NSRange(
            location: NSMaxRange((result.source as NSString).range(of: "two")),
            length: 0
        ))

        let followOnBold = MarkdownSourceCommandTransformer.applying(
            .bold,
            to: result.source,
            selection: result.selection
        )
        let followOnItalic = MarkdownSourceCommandTransformer.applying(
            .italic,
            to: result.source,
            selection: result.selection
        )
        XCTAssertEqual(followOnBold.source, "Alpha\n### one omega\n### Beta two****\ngamma")
        XCTAssertEqual(followOnItalic.source, "Alpha\n### one omega\n### Beta two**\ngamma")
        for followOn in [followOnBold, followOnItalic] {
            XCTAssertEqual(
                MarkdownSourceAnalyzer.tokens(in: followOn.source).filter {
                    if case .heading(level: 3) = $0.kind { true } else { false }
                }.count,
                2
            )
        }
    }

    func testPartialHeadingUsesCRLFWithoutChangingUnselectedSourceBytes() throws {
        let source = "Alpha target omega\r\nTail ✓"
        let result = apply(.heading4, to: source, selecting: "target")

        XCTAssertEqual(result.source, "Alpha\r\n#### target\r\nomega\r\nTail ✓")
        XCTAssertEqual((result.source as NSString).substring(with: result.selection), "target")
        XCTAssertFalse(result.source.replacingOccurrences(of: "\r\n", with: "").contains("\n"))

        let inverse = try XCTUnwrap(MarkdownTextDelta.between(result.source, and: source))
        let restored = NSMutableString(string: result.source)
        restored.replaceCharacters(in: inverse.range, with: inverse.replacement)
        XCTAssertEqual(Data((restored as String).utf8), Data(source.utf8))
    }

    func testHeadingAndBodyFailClosedForWhitespaceOrFencedCodeSelections() {
        let whitespaceSource = "Alpha   omega"
        let whitespace = (whitespaceSource as NSString).range(of: "   ")
        for command in [RichEditorCommand.heading1, .heading6, .body] {
            let result = MarkdownSourceCommandTransformer.applying(command, to: whitespaceSource, selection: whitespace)
            XCTAssertEqual(result, .init(source: whitespaceSource, selection: whitespace))
        }

        let fencedSource = "Before\r\n```swift\r\nlet target = 1\r\n```\r\nAfter"
        for selected in ["target", "```swift"] {
            let range = (fencedSource as NSString).range(of: selected)
            for command in [RichEditorCommand.heading1, .heading6, .body] {
                let result = MarkdownSourceCommandTransformer.applying(command, to: fencedSource, selection: range)
                XCTAssertEqual(result, .init(source: fencedSource, selection: range))
            }
        }
    }

    func testFenceProtectionRequiresWhitespaceOnlyClosingSuffixAndIncludesUnclosedEOF() throws {
        for marker in ["```", "~~~"] {
            let source = "Before\n\(marker)swift\ninside\n\(marker) trailing\nstill fenced\n\(marker)\nAfter"
            let token = try XCTUnwrap(MarkdownSourceAnalyzer.tokens(in: source).first {
                if case .fencedCode = $0.kind { true } else { false }
            })
            XCTAssertTrue((source as NSString).substring(with: token.contentRange).contains("still fenced"))
            XCTAssertEqual(token.markerRanges.map((source as NSString).substring(with:)), ["\(marker)swift", marker])

            for selected in ["inside", "still fenced", "\(marker) trailing"] {
                let range = (source as NSString).range(of: selected)
                for command in [RichEditorCommand.heading1, .heading6, .body] {
                    XCTAssertEqual(
                        MarkdownSourceCommandTransformer.applying(command, to: source, selection: range),
                        .init(source: source, selection: range)
                    )
                }
            }
        }

        let unclosed = "Before\n```swift\ntarget"
        let targetRange = (unclosed as NSString).range(of: "target")
        let eofCaret = NSRange(location: (unclosed as NSString).length, length: 0)
        for selection in [targetRange, eofCaret] {
            for command in [RichEditorCommand.heading1, .body] {
                XCTAssertEqual(
                    MarkdownSourceCommandTransformer.applying(command, to: unclosed, selection: selection),
                    .init(source: unclosed, selection: selection)
                )
            }
        }

        let closedWithHorizontalWhitespace = "```swift\ninside\n``` \t\ntarget"
        let afterFence = apply(.heading1, to: closedWithHorizontalWhitespace, selecting: "target")
        XCTAssertEqual(afterFence.source, "```swift\ninside\n``` \t\n# target")
    }

    func testInlineCommandsWrapAndToggleOnlyTheSelectedSource() {
        assertToggle(.bold, source: "pre target post", selected: "target", wrapped: "pre **target** post")
        assertToggle(.italic, source: "pre target post", selected: "target", wrapped: "pre *target* post")
        assertToggle(.strikethrough, source: "pre target post", selected: "target", wrapped: "pre ~~target~~ post")
        assertToggle(.inlineCode, source: "pre target post", selected: "target", wrapped: "pre `target` post")

        let backticks = apply(.inlineCode, to: "use a`b here", selecting: "a`b")
        XCTAssertEqual(backticks.source, "use ``a`b`` here")

        let empty = MarkdownSourceCommandTransformer.applying(.bold, to: "ab", selection: NSRange(location: 1, length: 0))
        XCTAssertEqual(empty.source, "a****b")
        XCTAssertEqual(empty.selection, NSRange(location: 3, length: 0))
    }

    func testLinkCommandUsesOnlyAllowlistedDestinations() {
        let safe = apply(.link("https://example.com/docs"), to: "Read this now", selecting: "this")
        XCTAssertEqual(safe.source, "Read [this](https://example.com/docs) now")
        XCTAssertEqual((safe.source as NSString).substring(with: safe.selection), "this")

        let source = "Do not change"
        let unsafe = apply(.link("file:///tmp/private"), to: source, selecting: "change")
        XCTAssertEqual(unsafe.source, source)

        let parentheses = apply(.link("https://example.com/a(b)"), to: "See target", selecting: "target")
        XCTAssertEqual(parentheses.source, "See [target](<https://example.com/a(b)>)")
        XCTAssertTrue(MarkdownSourceAnalyzer.tokens(in: parentheses.source).contains {
            $0.kind == .link(destination: "https://example.com/a(b)", isAllowed: true)
        })
    }

    func testBlockCommandsAreDeterministicAndToggleWhereAppropriate() {
        let all = NSRange(location: 0, length: ("one\ntwo" as NSString).length)
        XCTAssertEqual(
            MarkdownSourceCommandTransformer.applying(.bulletList, to: "one\ntwo", selection: all).source,
            "- one\n- two"
        )
        XCTAssertEqual(
            MarkdownSourceCommandTransformer.applying(.numberedList, to: "- one\n- two", selection: all).source,
            "1. one\n1. two"
        )
        XCTAssertEqual(
            MarkdownSourceCommandTransformer.applying(.checklist, to: "one\ntwo", selection: all).source,
            "- [ ] one\n- [ ] two"
        )
        XCTAssertEqual(
            MarkdownSourceCommandTransformer.applying(.blockquote, to: "one\ntwo", selection: all).source,
            "> one\n> two"
        )
        XCTAssertEqual(
            MarkdownSourceCommandTransformer.applying(.blockquote, to: "> one\n> two", selection: NSRange(location: 0, length: 11)).source,
            "one\ntwo"
        )

        let code = apply(.fencedCode, to: "before\nprint(1)\nafter", selecting: "print(1)")
        XCTAssertEqual(code.source, "before\n```\nprint(1)\n```\nafter")
        let unwrappedCode = MarkdownSourceCommandTransformer.applying(.fencedCode, to: code.source, selection: code.selection)
        XCTAssertEqual(unwrappedCode.source, "before\nprint(1)\nafter")

        XCTAssertEqual(
            MarkdownSourceCommandTransformer.applying(.horizontalRule, to: "", selection: .init(location: 0, length: 0)).source,
            "---"
        )
    }

    func testUnknownMarkdownAroundAnEditRemainsByteForByteIdentical() {
        let prefix = "---\r\nkey: value\r\n---\r\n<div data-custom='✓'>\r\n:::extension arg\r\n"
        let suffix = "\r\n::: \r\n</div>\r\n[^custom]: untouched\r\n"
        let source = prefix + "target" + suffix
        let result = apply(.bold, to: source, selecting: "target")

        XCTAssertEqual(result.source, prefix + "**target**" + suffix)
        let resultBytes = Data(result.source.utf8)
        let prefixBytes = Data(prefix.utf8)
        XCTAssertEqual(Data(resultBytes.prefix(prefixBytes.count)), prefixBytes)
        XCTAssertTrue(result.source.hasSuffix(suffix))
    }

    func testMinimalDeltaPreservesUnchangedUTF16PrefixAndSuffix() throws {
        let old = "👋 prefix\r\noriginal\r\nsuffix ✓"
        let new = "👋 prefix\r\nupdated text\r\nsuffix ✓"
        let delta = try XCTUnwrap(MarkdownTextDelta.between(old, and: new))
        let rebuilt = NSMutableString(string: old)
        rebuilt.replaceCharacters(in: delta.range, with: delta.replacement)

        XCTAssertEqual(rebuilt as String, new)
        XCTAssertEqual(delta.replacement, "updated text")
    }

    func testMinimalDeltaRebuildsLargeRepeatedSourceForNearEndEdit() throws {
        let source = (0..<600).map { index in
            String(
                format: "Paragraph %04d: Stable viewport text with **Markdown** and enough words to wrap predictably.",
                index
            )
        }.joined(separator: "\n")
        let selected = "Paragraph 0599"
        let selection = (source as NSString).range(of: selected)
        let expected = MarkdownSourceCommandTransformer.applying(
            .strikethrough,
            to: source,
            selection: selection
        ).source
        let delta = try XCTUnwrap(MarkdownTextDelta.between(source, and: expected))
        let rebuilt = NSMutableString(string: source)
        rebuilt.replaceCharacters(in: delta.range, with: delta.replacement)

        XCTAssertEqual(Data((rebuilt as String).utf8), Data(expected.utf8))
        XCTAssertEqual(delta.range, selection)
        XCTAssertEqual(delta.replacement, "~~\(selected)~~")
    }

    func testExternalDeltaMapsCaretAndSelectionWithoutExpandingAtInsertionBoundary() throws {
        let insertion = try XCTUnwrap(MarkdownTextDelta.between("abcd", and: "abXYcd"))
        XCTAssertEqual(insertion.mapping(NSRange(location: 2, length: 0)), NSRange(location: 4, length: 0))
        XCTAssertEqual(insertion.mapping(NSRange(location: 3, length: 1)), NSRange(location: 5, length: 1))

        let replacement = try XCTUnwrap(MarkdownTextDelta.between("before OLD after", and: "before NEW TEXT after"))
        XCTAssertEqual(replacement.mapping(NSRange(location: 11, length: 5)), NSRange(location: 16, length: 5))
    }

    func testMinimalDeltaNeverSplitsEmojiOrCombiningSequences() throws {
        let emoji = try XCTUnwrap(MarkdownTextDelta.between("A😀Z", and: "A😁Z"))
        XCTAssertEqual(emoji.range, NSRange(location: 1, length: 2))
        XCTAssertEqual(emoji.replacement, "😁")

        let combining = try XCTUnwrap(MarkdownTextDelta.between("A e\u{301} Z", and: "A é Z"))
        let rebuilt = NSMutableString(string: "A e\u{301} Z")
        rebuilt.replaceCharacters(in: combining.range, with: combining.replacement)
        XCTAssertEqual(rebuilt as String, "A é Z")
    }

    func testFencedCodeUsesExistingCRLFConvention() {
        let source = "before\r\ncode\r\nafter"
        let result = apply(.fencedCode, to: source, selecting: "code")
        XCTAssertEqual(result.source, "before\r\n```\r\ncode\r\n```\r\nafter")
    }

    func testSourceModeDoesNotCreateActivatedLinksOrAlterText() {
        let source = "[Web](https://example.com) [File](file:///tmp/private) ![remote](https://tracker.invalid/pixel)"
        let storage = NSTextStorage(string: source)
        MarkdownSourcePresentation.apply(
            to: storage,
            style: MarkdownEditorPresentationStyle(.balanced),
            showsSource: true
        )
        var links: [Any] = []
        storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if let value { links.append(value) }
        }

        XCTAssertEqual(storage.string, source)
        XCTAssertTrue(links.isEmpty)
        XCTAssertFalse(storage.containsAttachments(in: NSRange(location: 0, length: storage.length)))
    }

    func testPageModeActivatesOnlyAllowlistedLinksAndNeverCreatesAttachments() {
        let source = "[Web](https://example.com) [Mail](mailto:person@example.com) [File](file:///tmp/private) ![remote](https://tracker.invalid/pixel)"
        let storage = NSTextStorage(string: source)
        MarkdownSourcePresentation.apply(
            to: storage,
            style: MarkdownEditorPresentationStyle(.balanced),
            showsSource: false
        )
        var destinations: [String] = []
        storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if let url = value as? URL { destinations.append(url.absoluteString) }
        }

        XCTAssertEqual(destinations, ["https://example.com", "mailto:person@example.com"])
        XCTAssertEqual(storage.string, source)
        XCTAssertFalse(storage.containsAttachments(in: NSRange(location: 0, length: storage.length)))
    }

    func testPageModeKeepsSemanticMarkersLegibleWhileNativeChecklistSourceRecedes() throws {
        let source = "- [x] Task\n> Quote\n---\n```swift\nlet value = 1\n```\nA **bold** finish."
        let storage = NSTextStorage(string: source)
        let style = MarkdownEditorPresentationStyle(.balanced)

        MarkdownSourcePresentation.apply(
            to: storage,
            style: style,
            showsSource: false
        )

        let tokens = MarkdownSourceAnalyzer.tokens(in: source)
        for token in tokens {
            switch token.kind {
            case .list(.checklist):
                for range in token.markerRanges {
                    let font = try XCTUnwrap(storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
                    let color = try XCTUnwrap(storage.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor)
                    XCTAssertGreaterThanOrEqual(font.pointSize, 11, "Checklist marker must retain fixed layout metrics")
                    XCTAssertTrue(color.isEqual(NSColor.clear), "Native Page checkbox replaces visible source punctuation")
                }
                continue
            case .list, .blockquote:
                for range in token.markerRanges {
                    let font = try XCTUnwrap(storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
                    let color = try XCTUnwrap(storage.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor)
                    XCTAssertGreaterThanOrEqual(font.pointSize, 11, "\(token.kind) marker should remain visible")
                    XCTAssertFalse(color.isEqual(NSColor.clear))
                }
                continue
            case .thematicBreak, .fencedCode:
                break
            default:
                continue
            }
            for range in token.markerRanges {
                let font = try XCTUnwrap(storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
                let color = try XCTUnwrap(storage.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor)
                XCTAssertLessThan(font.pointSize, 5, "\(token.kind) source punctuation should recede")
                XCTAssertTrue(color.isEqual(NSColor.clear))
            }
        }

        let strong = try XCTUnwrap(tokens.first { $0.kind == .strong })
        let inlineMarkerRange = strong.markerRanges[0]
        let inlineMarkerFont = try XCTUnwrap(
            storage.attribute(.font, at: inlineMarkerRange.location, effectiveRange: nil) as? NSFont
        )
        let inlineMarkerColor = try XCTUnwrap(
            storage.attribute(.foregroundColor, at: inlineMarkerRange.location, effectiveRange: nil) as? NSColor
        )
        XCTAssertLessThan(inlineMarkerFont.pointSize, 5)
        XCTAssertTrue(inlineMarkerColor.isEqual(NSColor.clear))
        XCTAssertEqual(storage.string, source)
        XCTAssertEqual(Data(storage.string.utf8), Data(source.utf8))
    }

    func testPageChecklistPresentationCarriesExactControlRangesAndMarkdownModeStaysRaw() throws {
        let source = "  *  [X]\tShip **release**"
        let storage = NSTextStorage(string: source)
        let style = MarkdownEditorPresentationStyle(.balanced)
        let page = MarkdownSourcePresentation.applyDocument(
            to: storage,
            style: style,
            showsSource: false
        )
        let decoration = try XCTUnwrap(page.checklistDecorations.first)
        let string = source as NSString

        XCTAssertEqual(string.substring(with: decoration.markerRange), "*  [X]\t")
        XCTAssertEqual(string.substring(with: decoration.stateRange), "X")
        XCTAssertEqual(string.substring(with: decoration.contentRange), "Ship **release**")
        XCTAssertTrue(decoration.isChecked)
        let markerColor = try XCTUnwrap(
            storage.attribute(.foregroundColor, at: decoration.markerRange.location, effectiveRange: nil) as? NSColor
        )
        let markerFont = try XCTUnwrap(
            storage.attribute(.font, at: decoration.markerRange.location, effectiveRange: nil) as? NSFont
        )
        XCTAssertTrue(markerColor.isEqual(NSColor.clear))
        XCTAssertEqual(markerFont.pointSize, style.bodyFont.pointSize, accuracy: 0.01)
        XCTAssertEqual(Data(storage.string.utf8), Data(source.utf8))

        let markdown = MarkdownSourcePresentation.applyDocument(
            to: storage,
            style: style,
            showsSource: true
        )
        XCTAssertTrue(markdown.checklistDecorations.isEmpty)
        let sourceColor = try XCTUnwrap(
            storage.attribute(.foregroundColor, at: decoration.markerRange.location, effectiveRange: nil) as? NSColor
        )
        XCTAssertFalse(sourceColor.isEqual(NSColor.clear))
        XCTAssertEqual(Data(storage.string.utf8), Data(source.utf8))
    }

    func testPageModeUsesSourceExactBlockDecorationsForRulesAndFencedCode() throws {
        let source = "---\n```swift\nlet launch = true\n```"
        let storage = NSTextStorage(string: source)
        let decorations = MarkdownSourcePresentation.apply(
            to: storage,
            style: MarkdownEditorPresentationStyle(.balanced),
            showsSource: false
        )

        XCTAssertEqual(storage.string, source)
        XCTAssertEqual(Data(storage.string.utf8), Data(source.utf8))
        XCTAssertEqual(decorations.map(\.kind), [.thematicBreak, .fencedCode])

        let ruleRange = try XCTUnwrap(decorations.first { $0.kind == .thematicBreak }).range
        let ruleColor = try XCTUnwrap(storage.attribute(.foregroundColor, at: ruleRange.location, effectiveRange: nil) as? NSColor)
        XCTAssertTrue(ruleColor.isEqual(NSColor.clear))

        let code = try XCTUnwrap(MarkdownSourceAnalyzer.tokens(in: source).first {
            if case .fencedCode = $0.kind { true } else { false }
        })
        XCTAssertNil(storage.attribute(.backgroundColor, at: code.contentRange.location, effectiveRange: nil))
        for markerRange in code.markerRanges {
            XCTAssertNil(storage.attribute(.backgroundColor, at: markerRange.location, effectiveRange: nil))
            let font = try XCTUnwrap(storage.attribute(.font, at: markerRange.location, effectiveRange: nil) as? NSFont)
            let color = try XCTUnwrap(storage.attribute(.foregroundColor, at: markerRange.location, effectiveRange: nil) as? NSColor)
            XCTAssertLessThan(font.pointSize, 5)
            XCTAssertTrue(color.isEqual(NSColor.clear))
        }
    }

    func testThematicBreakStaysDecoratedAndSourceExactWhenEditing() throws {
        let source = "Before\n---\nAfter"
        let storage = NSTextStorage(string: source)
        let ruleRange = (source as NSString).range(of: "---")
        let decorations = MarkdownSourcePresentation.apply(
            to: storage,
            style: MarkdownEditorPresentationStyle(.balanced),
            showsSource: false
        )

        XCTAssertNotNil(decorations.first { $0.kind == .thematicBreak })
        let color = try XCTUnwrap(storage.attribute(.foregroundColor, at: ruleRange.location, effectiveRange: nil) as? NSColor)
        XCTAssertTrue(color.isEqual(NSColor.clear))
        XCTAssertEqual(storage.string, source)
    }

    func testCaretMovementDoesNotChangePageAttributesOrLayoutMetrics() throws {
        let source = "# A **smooth** document with *stable* wrapping and enough words to span several lines without moving when the caret enters it."
        var markdown = source
        let binding = Binding(
            get: { markdown },
            set: { markdown = $0 }
        )
        let coordinator = RichMarkdownEditor.Coordinator(
            markdown: binding,
            style: .balanced,
            showsSource: false
        )
        let textView = MarkdownPageTextView(frame: NSRect(x: 0, y: 0, width: 280, height: 320))
        textView.configurePage(style: .balanced, showsSource: false)
        textView.string = source
        textView.delegate = coordinator
        let scrollView = NSScrollView(frame: textView.frame)
        scrollView.documentView = textView
        coordinator.textView = textView
        coordinator.scrollView = scrollView
        coordinator.applyPresentation(to: textView, preservingViewport: true)

        let markers = MarkdownSourceAnalyzer.tokens(in: source).flatMap(\.markerRanges)
        XCTAssertFalse(markers.isEmpty)
        let fontsBeforeClick = markers.map {
            textView.textStorage?.attribute(.font, at: $0.location, effectiveRange: nil) as? NSFont
        }
        let colorsBeforeClick = markers.map {
            textView.textStorage?.attribute(.foregroundColor, at: $0.location, effectiveRange: nil) as? NSColor
        }
        let paragraphsBeforeClick = markers.map {
            textView.textStorage?.attribute(.paragraphStyle, at: $0.location, effectiveRange: nil) as? NSParagraphStyle
        }
        let layoutBeforeClick = measuredLayout(for: textView.textStorage!, width: 280)

        textView.setSelectedRange((source as NSString).range(of: "smooth"))

        let layoutAfterClick = measuredLayout(for: textView.textStorage!, width: 280)
        XCTAssertEqual(layoutBeforeClick.width, layoutAfterClick.width, accuracy: 0.01)
        XCTAssertEqual(layoutBeforeClick.height, layoutAfterClick.height, accuracy: 0.01)
        for (index, range) in markers.enumerated() {
            let font = try XCTUnwrap(textView.textStorage?.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
            let color = try XCTUnwrap(textView.textStorage?.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor)
            let paragraph = try XCTUnwrap(textView.textStorage?.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)
            XCTAssertEqual(font, fontsBeforeClick[index])
            XCTAssertEqual(color, colorsBeforeClick[index])
            XCTAssertEqual(paragraph, paragraphsBeforeClick[index])
            XCTAssertLessThan(font.pointSize, 5)
            XCTAssertTrue(color.isEqual(NSColor.clear))
        }
        XCTAssertEqual(textView.string, source)
        XCTAssertEqual(markdown, source)
    }

    func testSelectingVisibleTextThenApplyingPresentationPreservesSelectionAndViewport() throws {
        let source = longMarkdownSource(paragraphCount: 600)
        XCTAssertGreaterThan(source.utf16.count, 32_000)
        let (scrollView, textView) = try scrollableMarkdownPage(source: source)
        let maximumY = textView.bounds.height - scrollView.contentView.bounds.height
        XCTAssertGreaterThan(maximumY, scrollView.contentView.bounds.height * 10)

        scrollView.contentView.scroll(to: NSPoint(x: 0, y: maximumY * 0.45))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        let viewportBeforeSelection = scrollView.contentView.bounds
        let selection = try visibleLineSelection(in: textView, viewport: viewportBeforeSelection)
        let selectionRect = try documentRect(for: selection, in: textView)
        XCTAssertTrue(
            viewportBeforeSelection.insetBy(dx: 0, dy: 8).contains(selectionRect),
            "The visible-range fixture must start fully inside the viewport"
        )

        let selectionRecorder = SelectionChangeRecorder()
        textView.delegate = selectionRecorder
        textView.setSelectedRange(selection)
        textView.scrollRangeToVisible(selection)
        selectionRecorder.reset()
        textView.setSelectedRange(selection)
        XCTAssertGreaterThan(
            selectionRecorder.changeCount,
            0,
            "The fixture must detect a redundant selection assignment"
        )

        scrollView.contentView.scroll(to: viewportBeforeSelection.origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        selectionRecorder.reset()
        var markdown = source
        let coordinator = RichMarkdownEditor.Coordinator(
            markdown: Binding(get: { markdown }, set: { markdown = $0 }),
            style: .balanced,
            showsSource: false
        )
        coordinator.textView = textView
        coordinator.scrollView = scrollView

        coordinator.applyPresentation(to: textView, preservingViewport: true)

        XCTAssertEqual(selectionRecorder.changeCount, 0, "Attribute-only presentation must not reassign selection")
        XCTAssertEqual(scrollView.contentView.bounds.origin.x, viewportBeforeSelection.origin.x, accuracy: 0.01)
        XCTAssertEqual(scrollView.contentView.bounds.origin.y, viewportBeforeSelection.origin.y, accuracy: 0.01)
        XCTAssertEqual(textView.selectedRange(), selection)
        XCTAssertEqual(textView.string, source)
        XCTAssertEqual(markdown, source)
    }

    func testSelectingOffscreenTextInLongMarkdownPageStillScrollsIntoView() throws {
        let source = longMarkdownSource(paragraphCount: 600)
        XCTAssertGreaterThan(source.utf16.count, 32_000)
        let (scrollView, textView) = try scrollableMarkdownPage(source: source)
        let maximumY = textView.bounds.height - scrollView.contentView.bounds.height
        XCTAssertGreaterThan(maximumY, scrollView.contentView.bounds.height * 10)

        scrollView.contentView.scroll(to: NSPoint(x: 0, y: maximumY * 0.2))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        let viewportBeforeSelection = scrollView.contentView.bounds
        let selection = (source as NSString).range(of: "Paragraph 0599")
        XCTAssertNotEqual(selection.location, NSNotFound)
        let selectionRect = try documentRect(for: selection, in: textView)
        XCTAssertGreaterThan(selectionRect.minY, viewportBeforeSelection.maxY)

        textView.setSelectedRange(selection)
        textView.scrollRangeToVisible(selection)

        let viewportAfterSelection = scrollView.contentView.bounds
        XCTAssertGreaterThan(viewportAfterSelection.origin.y, viewportBeforeSelection.origin.y)
        XCTAssertTrue(
            viewportAfterSelection.intersects(selectionRect),
            "An offscreen selection must retain AppKit's normal reveal behavior"
        )
        XCTAssertEqual(textView.selectedRange(), selection)
        XCTAssertEqual(textView.string, source)
    }

    func testBlockDecorationDrawingFiltersToVisibleSortedSourceRanges() {
        let decorations = [
            MarkdownPageBlockDecoration(kind: .thematicBreak, range: NSRange(location: 4, length: 3)),
            MarkdownPageBlockDecoration(kind: .fencedCode, range: NSRange(location: 20, length: 18)),
            MarkdownPageBlockDecoration(kind: .thematicBreak, range: NSRange(location: 52, length: 3)),
        ]

        XCTAssertEqual(
            MarkdownPageTextView.blockDecorations(
                decorations,
                intersecting: NSRange(location: 18, length: 24)
            ),
            [decorations[1]]
        )
        XCTAssertTrue(
            MarkdownPageTextView.blockDecorations(
                decorations,
                intersecting: NSRange(location: 55, length: 8)
            ).isEmpty
        )
    }

    func testPageBlockDecorationsExposeSynchronizedAccessibilitySemantics() {
        let source = "Before\n---\n```swift\nlet launch = true\n```\nAfter\n| Item | State |\n| --- | --- |\n| Editor | Ready |"
        let textView = MarkdownPageTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        textView.configurePage(style: .balanced, showsSource: false)
        textView.string = source
        let decorations = MarkdownSourcePresentation.apply(
            to: textView.textStorage!,
            style: MarkdownEditorPresentationStyle(.balanced),
            showsSource: false
        )
        textView.updateBlockDecorations(decorations)

        let fullRange = NSRange(location: 0, length: (source as NSString).length)
        let annotations = textView.accessibilityBlockAnnotations(for: fullRange)
        XCTAssertEqual(annotations.map(\.label), ["Separator", "Code block", "Table"])
        XCTAssertEqual(annotations.map(\.range), decorations.map(\.range))

        textView.configurePage(style: .balanced, showsSource: true)
        textView.updateBlockDecorations(decorations)
        XCTAssertTrue(textView.accessibilityBlockAnnotations(for: fullRange).isEmpty)
        XCTAssertEqual(textView.string, source)
    }

    func testLongDocumentEditsClearStaleBlockGeometryBeforeDebouncedRestyling() {
        let source = String(repeating: "Readable paragraph\n---\n", count: 1_600)
        XCTAssertGreaterThan(source.utf16.count, 32_000)
        XCTAssertLessThan(source.utf16.count, MarkdownSourcePresentation.maximumParsedUTF16Length)
        var markdown = source
        let binding = Binding(
            get: { markdown },
            set: { markdown = $0 }
        )
        let coordinator = RichMarkdownEditor.Coordinator(
            markdown: binding,
            style: .balanced,
            showsSource: false
        )
        let textView = MarkdownPageTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        textView.configurePage(style: .balanced, showsSource: false)
        textView.string = source
        let scrollView = NSScrollView(frame: textView.frame)
        scrollView.documentView = textView
        coordinator.textView = textView
        coordinator.scrollView = scrollView
        coordinator.applyPresentation(to: textView, preservingViewport: true)

        let fullRange = NSRange(location: 0, length: (source as NSString).length)
        XCTAssertFalse(textView.accessibilityBlockAnnotations(for: fullRange).isEmpty)

        coordinator.requestPresentation(
            to: textView,
            preservingViewport: true,
            configurationChanged: false
        )
        XCTAssertTrue(textView.accessibilityBlockAnnotations(for: fullRange).isEmpty)
        coordinator.cancelPendingPresentation()
        XCTAssertEqual(textView.string, source)
    }

    private func measuredLayout(for storage: NSTextStorage, width: CGFloat) -> NSSize {
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)
        return layoutManager.usedRect(for: container).size
    }

    private func longMarkdownSource(paragraphCount: Int) -> String {
        (0..<paragraphCount).map { index in
            String(
                format: "Paragraph %04d: Stable viewport text with **Markdown** and enough words to wrap predictably.",
                index
            )
        }.joined(separator: "\n")
    }

    private func scrollableMarkdownPage(
        source: String,
        viewportSize: NSSize = NSSize(width: 420, height: 220)
    ) throws -> (scrollView: NSScrollView, textView: MarkdownPageTextView) {
        let scrollView = NSScrollView(frame: NSRect(origin: .zero, size: viewportSize))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false

        let textView = MarkdownPageTextView(
            frame: NSRect(origin: .zero, size: scrollView.contentSize)
        )
        textView.configurePage(style: .balanced, showsSource: false)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 0
        scrollView.documentView = textView
        textView.string = source

        let storage = try XCTUnwrap(textView.textStorage)
        let decorations = MarkdownSourcePresentation.apply(
            to: storage,
            style: MarkdownEditorPresentationStyle(.balanced),
            showsSource: false
        )
        textView.updateBlockDecorations(decorations)

        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let documentHeight = ceil(usedRect.maxY + textView.textContainerOrigin.y + textView.textContainerInset.height)
        textView.setFrameSize(
            NSSize(width: scrollView.contentSize.width, height: max(scrollView.contentSize.height, documentHeight))
        )
        layoutManager.ensureLayout(for: textContainer)
        scrollView.layoutSubtreeIfNeeded()
        return (scrollView, textView)
    }

    private func visibleLineSelection(in textView: NSTextView, viewport: NSRect) throws -> NSRange {
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        let containerPoint = NSPoint(
            x: 12,
            y: viewport.midY - textView.textContainerOrigin.y
        )
        let glyphIndex = layoutManager.glyphIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceThroughGlyph: nil
        )
        let characterIndex = min(layoutManager.characterIndexForGlyph(at: glyphIndex), max(0, textView.string.utf16.count - 1))
        let lineRange = (textView.string as NSString).lineRange(
            for: NSRange(location: characterIndex, length: 0)
        )
        return NSRange(location: lineRange.location, length: min(14, lineRange.length))
    }

    private func documentRect(for characterRange: NSRange, in textView: NSTextView) throws -> NSRect {
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: characterRange,
            actualCharacterRange: nil
        )
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textView.textContainerOrigin.x
        rect.origin.y += textView.textContainerOrigin.y
        return rect
    }

    func testDismantlingEditorPurgesPlaintextAndUndoState() {
        let textView = NSTextView()
        textView.allowsUndo = true
        textView.string = "decrypted Vault plaintext"
        textView.undoManager?.registerUndo(withTarget: textView) { target in
            target.string = "decrypted Vault plaintext"
        }

        MarkdownEditorStatePurger.purge(textView)

        XCTAssertTrue(textView.string.isEmpty)
        XCTAssertFalse(textView.undoManager?.canUndo ?? false)
        XCTAssertTrue(textView.typingAttributes.isEmpty)
    }

    func testToolbarFormattingParticipatesInNativeUndoAndRedo() {
        var markdown = "A calm document"
        let binding = Binding(
            get: { markdown },
            set: { markdown = $0 }
        )
        let coordinator = RichMarkdownEditor.Coordinator(
            markdown: binding,
            style: .balanced,
            showsSource: false
        )
        let textView = UndoEnabledTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        textView.allowsUndo = true
        textView.string = markdown
        textView.delegate = coordinator
        let scrollView = NSScrollView(frame: textView.frame)
        scrollView.documentView = textView
        coordinator.textView = textView
        coordinator.scrollView = scrollView
        textView.setSelectedRange((markdown as NSString).range(of: "calm"))

        coordinator.apply(.bold, to: textView)

        XCTAssertEqual(textView.string, "A **calm** document")
        XCTAssertEqual(markdown, "A **calm** document")
        XCTAssertTrue(textView.undoManager?.canUndo ?? false)

        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "A calm document")
        XCTAssertEqual(markdown, "A calm document")

        textView.undoManager?.redo()
        XCTAssertEqual(textView.string, "A **calm** document")
        XCTAssertEqual(markdown, "A **calm** document")
    }

    func testPartialHeadingSplitParticipatesInNativeUndoAndRedoSourceExactly() {
        let original = "Alpha target omega\r\nTail ✓"
        var markdown = original
        let coordinator = RichMarkdownEditor.Coordinator(
            markdown: Binding(get: { markdown }, set: { markdown = $0 }),
            style: .balanced,
            showsSource: false
        )
        let textView = UndoEnabledTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        textView.allowsUndo = true
        textView.string = original
        textView.delegate = coordinator
        let scrollView = NSScrollView(frame: textView.frame)
        scrollView.documentView = textView
        coordinator.textView = textView
        coordinator.scrollView = scrollView
        textView.setSelectedRange((original as NSString).range(of: "target"))

        coordinator.apply(.heading2, to: textView)

        let transformed = "Alpha\r\n## target\r\nomega\r\nTail ✓"
        XCTAssertEqual(Data(textView.string.utf8), Data(transformed.utf8))
        XCTAssertEqual(Data(markdown.utf8), Data(transformed.utf8))
        XCTAssertEqual((textView.string as NSString).substring(with: textView.selectedRange()), "target")

        textView.undoManager?.undo()
        XCTAssertEqual(Data(textView.string.utf8), Data(original.utf8))
        XCTAssertEqual(Data(markdown.utf8), Data(original.utf8))

        textView.undoManager?.redo()
        XCTAssertEqual(Data(textView.string.utf8), Data(transformed.utf8))
        XCTAssertEqual(Data(markdown.utf8), Data(transformed.utf8))
    }

    func testPageAndMarkdownModesShareOneBufferAndPreserveTheSelection() {
        var markdown = "# Original\n\nA **portable** note."
        let binding = Binding(
            get: { markdown },
            set: { markdown = $0 }
        )
        let coordinator = RichMarkdownEditor.Coordinator(
            markdown: binding,
            style: .balanced,
            showsSource: false
        )
        let textView = UndoEnabledTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        textView.allowsUndo = true
        textView.string = markdown
        textView.delegate = coordinator
        let scrollView = NSScrollView(frame: textView.frame)
        scrollView.documentView = textView
        coordinator.textView = textView
        coordinator.scrollView = scrollView
        let originalSelection = (markdown as NSString).range(of: "portable")
        textView.setSelectedRange(originalSelection)

        coordinator.applyPresentation(to: textView, preservingViewport: true)
        XCTAssertEqual(textView.string, markdown)
        XCTAssertEqual(textView.selectedRange(), originalSelection)

        coordinator.showsSource = true
        coordinator.applyPresentation(to: textView, preservingViewport: true)
        XCTAssertEqual(textView.string, markdown)
        XCTAssertEqual(textView.selectedRange(), originalSelection)

        let replacementRange = (textView.string as NSString).range(of: "portable")
        XCTAssertTrue(textView.shouldChangeText(in: replacementRange, replacementString: "instant"))
        textView.textStorage?.replaceCharacters(in: replacementRange, with: "instant")
        textView.didChangeText()
        XCTAssertEqual(markdown, "# Original\n\nA **instant** note.")

        let updatedSelection = (textView.string as NSString).range(of: "instant")
        textView.setSelectedRange(updatedSelection)
        coordinator.showsSource = false
        coordinator.applyPresentation(to: textView, preservingViewport: true)
        XCTAssertEqual(textView.string, markdown)
        XCTAssertEqual(textView.selectedRange(), updatedSelection)
        XCTAssertEqual(Data(textView.string.utf8), Data(markdown.utf8))
    }

    func testLongDocumentPresentationDebouncesAndCancelsAcrossModeSwitches() async throws {
        let source = String(repeating: "# Heading\n\n", count: 4_000)
        var markdown = source
        let binding = Binding(
            get: { markdown },
            set: { markdown = $0 }
        )
        let coordinator = RichMarkdownEditor.Coordinator(
            markdown: binding,
            style: .balanced,
            showsSource: false
        )
        let textView = UndoEnabledTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        textView.string = source
        let scrollView = NSScrollView(frame: textView.frame)
        scrollView.documentView = textView
        coordinator.textView = textView
        coordinator.scrollView = scrollView

        coordinator.requestPresentation(
            to: textView,
            preservingViewport: true,
            configurationChanged: true
        )
        let immediatePageFont = try XCTUnwrap(
            textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        )
        XCTAssertEqual(immediatePageFont.pointSize, CGFloat(DocumentStyle.balanced.bodyPointSize))

        coordinator.showsSource = true
        coordinator.requestPresentation(
            to: textView,
            preservingViewport: true,
            configurationChanged: true
        )
        try await Task.sleep(nanoseconds: 250_000_000)
        let sourceFont = try XCTUnwrap(
            textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        )
        XCTAssertEqual(sourceFont.pointSize, MarkdownEditorPresentationStyle(.balanced).sourceFont.pointSize)
        XCTAssertEqual(textView.string, source)
        XCTAssertEqual(markdown, source)

        coordinator.showsSource = false
        coordinator.requestPresentation(
            to: textView,
            preservingViewport: true,
            configurationChanged: true
        )
        try await Task.sleep(nanoseconds: 400_000_000)
        let hiddenHeadingMarker = try XCTUnwrap(
            textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        )
        let hiddenHeadingMarkerColor = try XCTUnwrap(
            textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        )
        let headingContentFont = try XCTUnwrap(
            textView.textStorage?.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        )
        XCTAssertLessThan(hiddenHeadingMarker.pointSize, 5)
        XCTAssertTrue(hiddenHeadingMarkerColor.isEqual(NSColor.clear))
        XCTAssertGreaterThan(headingContentFont.pointSize, CGFloat(DocumentStyle.balanced.bodyPointSize))
        XCTAssertEqual(Data(textView.string.utf8), Data(source.utf8))
    }

    func testAnalyzerScalesAcrossALargeAIGeneratedDocument() {
        let unit = "## Heading\n\nA **bold** [link](https://example.com) with `code`.\n- [ ] Task\n> Quote\n\n"
        let repetitions = 1_200
        let source = String(repeating: unit, count: repetitions)

        let tokens = MarkdownSourceAnalyzer.tokens(in: source)

        XCTAssertGreaterThan(source.utf16.count, 100_000)
        XCTAssertEqual(tokens.count, repetitions * 6)
        XCTAssertTrue(tokens.contains { $0.range.location > 90_000 })
    }

    func testOversizedDocumentsFallBackToBaseTypographyWithoutChangingSource() throws {
        let source = String(repeating: "# Exact heading\n\n", count: 6_000)
        XCTAssertGreaterThan(source.utf16.count, MarkdownSourcePresentation.maximumParsedUTF16Length)
        let storage = NSTextStorage(string: source)
        let style = MarkdownEditorPresentationStyle(.balanced)

        MarkdownSourcePresentation.apply(
            to: storage,
            style: style,
            showsSource: false
        )

        let markerFont = try XCTUnwrap(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let contentFont = try XCTUnwrap(storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(markerFont.pointSize, style.bodyFont.pointSize)
        XCTAssertEqual(contentFont.pointSize, style.bodyFont.pointSize)
        XCTAssertEqual(Data(storage.string.utf8), Data(source.utf8))
    }

    private func apply(_ command: RichEditorCommand, to source: String, selecting selected: String) -> MarkdownSourceEditResult {
        let range = (source as NSString).range(of: selected)
        XCTAssertNotEqual(range.location, NSNotFound, "Test fixture must contain its selected text")
        return MarkdownSourceCommandTransformer.applying(command, to: source, selection: range)
    }

    private func assertToggle(
        _ command: RichEditorCommand,
        source: String,
        selected: String,
        wrapped: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let first = apply(command, to: source, selecting: selected)
        XCTAssertEqual(first.source, wrapped, file: file, line: line)
        let second = MarkdownSourceCommandTransformer.applying(command, to: first.source, selection: first.selection)
        XCTAssertEqual(second.source, source, file: file, line: line)
        XCTAssertEqual((second.source as NSString).substring(with: second.selection), selected, file: file, line: line)
    }
}

@MainActor
private final class UndoEnabledTextView: NSTextView {
    private let ownedUndoManager = UndoManager()

    override var undoManager: UndoManager? { ownedUndoManager }
}

@MainActor
private final class SelectionChangeRecorder: NSObject, NSTextViewDelegate {
    private(set) var changeCount = 0

    func textViewDidChangeSelection(_ notification: Notification) {
        changeCount += 1
    }

    func reset() {
        changeCount = 0
    }
}
