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
            showsSource: false,
            activeParagraphRange: nil
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

        XCTAssertTrue(tokens.contains { $0.kind == .link(destination: "https://example.com", isAllowed: true) })
        XCTAssertTrue(tokens.contains { $0.kind == .link(destination: "file:///tmp/x", isAllowed: false) })

        let fence = try XCTUnwrap(tokens.first { if case .fencedCode(language: "swift") = $0.kind { true } else { false } })
        XCTAssertEqual(string.substring(with: fence.contentRange), "let x = 1\n")
        XCTAssertEqual(fence.markerRanges.map(string.substring(with:)), ["```swift", "```"])
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
            let result = apply(command, to: "  ## Keep *inline*", selecting: "Keep")
            XCTAssertEqual(result.source, "  \(prefix)Keep *inline*")
        }
        let body = apply(.body, to: "  #### Keep *inline*", selecting: "Keep")
        XCTAssertEqual(body.source, "  Keep *inline*")

        let afterTerminalNewline = MarkdownSourceCommandTransformer.applying(
            .heading3,
            to: "Existing\n",
            selection: NSRange(location: 9, length: 0)
        )
        XCTAssertEqual(afterTerminalNewline.source, "Existing\n### ")
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
            showsSource: true,
            activeParagraphRange: nil
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
            showsSource: false,
            activeParagraphRange: nil
        )
        var destinations: [String] = []
        storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if let url = value as? URL { destinations.append(url.absoluteString) }
        }

        XCTAssertEqual(destinations, ["https://example.com", "mailto:person@example.com"])
        XCTAssertEqual(storage.string, source)
        XCTAssertFalse(storage.containsAttachments(in: NSRange(location: 0, length: storage.length)))
    }

    func testPageModeKeepsBlockMarkersVisibleWhileInlinePunctuationRecedes() throws {
        let source = "- [x] Task\n> Quote\n---\n```swift\nlet value = 1\n```\nA **bold** finish."
        let storage = NSTextStorage(string: source)
        let style = MarkdownEditorPresentationStyle(.balanced)

        MarkdownSourcePresentation.apply(
            to: storage,
            style: style,
            showsSource: false,
            activeParagraphRange: nil
        )

        let tokens = MarkdownSourceAnalyzer.tokens(in: source)
        for token in tokens {
            let keepsSemanticMarker: Bool
            switch token.kind {
            case .list, .blockquote, .thematicBreak, .fencedCode:
                keepsSemanticMarker = true
            default:
                keepsSemanticMarker = false
            }
            guard keepsSemanticMarker else { continue }
            for range in token.markerRanges {
                let font = try XCTUnwrap(storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
                XCTAssertGreaterThanOrEqual(font.pointSize, 11, "\(token.kind) marker should remain visible")
            }
        }

        let strong = try XCTUnwrap(tokens.first { $0.kind == .strong })
        let inlineMarkerFont = try XCTUnwrap(
            storage.attribute(.font, at: strong.markerRanges[0].location, effectiveRange: nil) as? NSFont
        )
        XCTAssertLessThan(inlineMarkerFont.pointSize, 5)
        XCTAssertEqual(storage.string, source)
        XCTAssertEqual(Data(storage.string.utf8), Data(source.utf8))
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
        let collapsedHeadingMarker = try XCTUnwrap(
            textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        )
        let headingContentFont = try XCTUnwrap(
            textView.textStorage?.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        )
        XCTAssertLessThan(collapsedHeadingMarker.pointSize, 5)
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
            showsSource: false,
            activeParagraphRange: nil
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
