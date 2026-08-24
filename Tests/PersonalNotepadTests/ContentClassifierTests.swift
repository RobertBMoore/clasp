import XCTest
@testable import PersonalNotepad

final class ContentClassifierTests: XCTestCase {
    func testLinkClassificationAddsStableTypeAndDomainTags() async {
        let result = await ContentClassifier().classify(.text("https://www.example.com/articles/clasp"))

        XCTAssertEqual(result.contentType, .link)
        XCTAssertEqual(result.title, "example.com")
        XCTAssertTrue(result.tags.contains("link"))
        XCTAssertTrue(result.tags.contains("example.com"))
    }

    func testChecklistAndCodeClassificationStayConservative() async {
        let checklist = await ContentClassifier().classify(.text("- [ ] Call Robert\n- [x] Send notes"))
        XCTAssertEqual(checklist.contentType, .checklist)
        XCTAssertTrue(checklist.tags.contains("task"))

        let prose = await ContentClassifier().classify(.text("A short sentence with no strong content signal."))
        XCTAssertEqual(prose.contentType, .note)
        XCTAssertEqual(prose.tags, ["note"])

        let code = await ContentClassifier().classify(.text("import SwiftUI\nstruct Card: View { var body: some View { Text(\"Hi\") } }"))
        XCTAssertEqual(code.contentType, .code)
        XCTAssertTrue(code.tags.contains("swift"))
    }
}
