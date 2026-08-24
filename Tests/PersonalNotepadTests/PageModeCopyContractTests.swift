import Foundation
import XCTest

final class PageModeCopyContractTests: XCTestCase {
    func testReadmeDocumentsTheCanonicalSourceAndPresentationContract() throws {
        let readme = try source(at: "README.md")

        XCTAssertTrue(readme.contains("## Page editing and Markdown"))
        XCTAssertTrue(readme.contains("Page / Markdown"))
        XCTAssertTrue(readme.contains("same canonical Markdown source"))
        XCTAssertTrue(readme.contains("Unknown Markdown syntax is preserved conservatively"))
        XCTAssertTrue(readme.contains("Exceptionally large notes remain fully editable and source-exact"))
        XCTAssertTrue(readme.contains("stored outside note files"))
        XCTAssertTrue(readme.contains("does not execute embedded HTML or load remote content"))
        for preset in ["Balanced", "Compact", "Spacious", "Technical"] {
            XCTAssertTrue(readme.contains(preset), preset)
        }

        XCTAssertFalse(readme.contains("## Formatted editing and Markdown"))
        XCTAssertFalse(readme.contains("**Formatted** mode"))
    }

    func testHelpAndOnboardingUsePageMarkdownVocabulary() throws {
        let help = try source(at: "Sources/PersonalNotepad/Views/Help/HelpView.swift")
        let onboarding = try source(at: "Sources/PersonalNotepad/Views/Onboarding/OnboardingStep.swift")

        XCTAssertTrue(help.contains("Page / Markdown Editing"))
        XCTAssertTrue(help.contains("same canonical Markdown source"))
        XCTAssertTrue(help.contains("Unknown syntax remains intact as source text"))
        XCTAssertTrue(help.contains("Exceptionally large notes stay fully editable and source-exact"))
        XCTAssertTrue(help.contains("These presentation settings stay outside the Markdown file"))
        XCTAssertTrue(help.contains("never executes embedded HTML or fetches remote content"))
        for preset in ["Balanced", "Compact", "Spacious", "Technical"] {
            XCTAssertTrue(help.contains(preset), preset)
        }

        XCTAssertTrue(onboarding.contains("Page / Markdown switch"))
        XCTAssertTrue(onboarding.contains("portable Markdown remains the canonical source"))
        XCTAssertTrue(onboarding.contains("without adding style data to the file"))

        XCTAssertFalse(help.contains("Formatted / Markdown"))
        XCTAssertFalse(onboarding.contains("Formatted / Markdown"))
    }

    private func source(at relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
