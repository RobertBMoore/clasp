import AppKit
import XCTest
@testable import PersonalNotepad

@MainActor
final class RichTextEditingTests: XCTestCase {
    func testMarkdownRendersAndReturnsBasicFormatting() {
        let markdown = "# Heading\n\n**Bold** and *italic* and <u>underlined</u> and [OpenAI](https://openai.com)\n- First item"
        let rendered = MarkdownRichTextCodec.attributedString(from: markdown)
        let roundTrip = MarkdownRichTextCodec.markdown(from: rendered)

        XCTAssertTrue(roundTrip.contains("# Heading"))
        XCTAssertTrue(roundTrip.contains("**Bold**"))
        XCTAssertTrue(roundTrip.contains("*italic*"), roundTrip)
        XCTAssertTrue(roundTrip.contains("<u>underlined</u>"))
        XCTAssertTrue(roundTrip.contains("[OpenAI](https://openai.com)"))
        XCTAssertTrue(roundTrip.contains("- First item"))
    }

    func testRenderedTextUsesAdaptiveColorAndComfortableReadingTypography() {
        let rendered = MarkdownRichTextCodec.attributedString(from: "A comfortable reading line")
        let attributes = rendered.attributes(at: 0, effectiveRange: nil)

        XCTAssertEqual(attributes[.foregroundColor] as? NSColor, .labelColor)
        XCTAssertEqual((attributes[.font] as? NSFont)?.pointSize, 17)
        XCTAssertEqual((attributes[.paragraphStyle] as? NSParagraphStyle)?.lineSpacing, 5)
        XCTAssertEqual((attributes[.paragraphStyle] as? NSParagraphStyle)?.paragraphSpacing, 10)
    }

    func testRTFCapturePreservesBoldAndSafeLinkAsMarkdown() throws {
        let rich = NSMutableAttributedString(string: "Styled link")
        rich.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 14), range: NSRange(location: 0, length: 6))
        rich.addAttribute(.link, value: URL(string: "https://example.com")!, range: NSRange(location: 7, length: 4))
        let data = try rich.data(
            from: NSRange(location: 0, length: rich.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )

        guard case .styledText(let markdown, let plainText) = RichTextCaptureDecoder.rtf(data) else {
            return XCTFail("Expected styled capture")
        }
        XCTAssertEqual(plainText, "Styled link")
        XCTAssertTrue(markdown.contains("**Styled**"))
        XCTAssertTrue(markdown.contains("[link](https://example.com)"))
    }

    func testHTMLCaptureKeepsBasicStyleWithoutRemoteOrExecutableContent() {
        let html = """
        <html><head><style>body{background:url(https://tracker.example/x)}</style></head>
        <body><h2>Project</h2><p><strong>Important</strong> <a href="https://example.com">reference</a></p>
        <img src="https://tracker.example/pixel"><script>alert('x')</script></body></html>
        """
        guard case .styledText(let markdown, _) = RichTextCaptureDecoder.html(Data(html.utf8)) else {
            return XCTFail("Expected styled HTML capture")
        }

        XCTAssertTrue(markdown.contains("## Project"))
        XCTAssertTrue(markdown.contains("**Important**"))
        XCTAssertTrue(markdown.contains("[reference](https://example.com)"))
        XCTAssertFalse(markdown.contains("tracker.example"))
        XCTAssertFalse(markdown.contains("alert"))
    }

    func testStyledCaptureClassificationUsesPlainTextButStoresMarkdown() async {
        let markdown = "## Example\n\n[Reference](https://example.com)"
        let result = await ContentClassifier().classify(
            .styledText(markdown: markdown, plainText: "Example\nReference")
        )

        XCTAssertEqual(result.body, markdown)
        XCTAssertEqual(result.title, "Example")
    }

    func testUnterminatedLinkMarkersUseABoundedLinearParseAndPreserveText() {
        let markdown = String(repeating: "[", count: 100_000).appending("](")

        let rendered = MarkdownRichTextCodec.attributedString(
            from: markdown,
            inlineParseBudget: 64
        )

        XCTAssertEqual(rendered.string, markdown)
    }

    func testInlineParseBudgetPreservesUnparsedRemainderAsLiteralText() {
        let markdown = String(repeating: "plain ", count: 100)

        let rendered = MarkdownRichTextCodec.attributedString(
            from: markdown,
            inlineParseBudget: 8
        )

        XCTAssertEqual(rendered.string, markdown)
    }

    func testExternalLinkPolicyAllowsOnlyHTTPHTTPSAndMailtoSchemes() {
        let allowed = [
            URL(string: "http://example.com")!,
            URL(string: "https://example.com/path")!,
            URL(string: "mailto:person@example.com")!
        ]
        let rejected = [
            URL(fileURLWithPath: "/tmp/untrusted.txt"),
            URL(string: "ftp://example.com/archive")!,
            URL(string: "smb://example.com/share")!,
            URL(string: "javascript:alert(1)")!,
            URL(string: "shortcuts://run-shortcut?name=Untrusted")!
        ]

        XCTAssertEqual(ExternalLinkPolicy.filterAllowed(allowed + rejected), allowed)
        XCTAssertTrue(allowed.allSatisfy(ExternalLinkPolicy.allows))
        XCTAssertTrue(rejected.allSatisfy { !ExternalLinkPolicy.allows($0) })
    }

    func testMarkdownRenderingDoesNotActivateUnsafeLinkSchemes() {
        let rendered = MarkdownRichTextCodec.attributedString(
            from: "[Web](https://example.com) [File](file:///tmp/private) [FTP](ftp://example.com/file)"
        )
        var destinations: [String] = []
        rendered.enumerateAttribute(.link, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
            if let url = value as? URL { destinations.append(url.absoluteString) }
        }

        XCTAssertEqual(destinations, ["https://example.com"])
    }
}
