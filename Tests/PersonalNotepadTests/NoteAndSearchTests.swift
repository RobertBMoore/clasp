import XCTest
@testable import PersonalNotepad

final class NoteAndSearchTests: XCTestCase {
    func testTitleDerivationAndTagNormalization() {
        XCTAssertEqual(Note.deriveTitle(from: "\n# A useful title\nBody"), "A useful title")
        XCTAssertEqual(Note.deriveTitle(from: "  \n"), "Untitled Note")
        XCTAssertEqual(Note.deriveTitle(from: "---\nBody"), "Untitled Note")
        XCTAssertEqual(Note.normalizedTags([" Work ", "work", "Ideas"]), ["ideas", "work"])

        var emptyNote = Note(title: "Untitled Note", body: "First typed line\nMore")
        emptyNote.deriveInitialTitleIfNeeded()
        XCTAssertEqual(emptyNote.title, "First typed line")
        emptyNote.body = "Changed first line"
        emptyNote.deriveInitialTitleIfNeeded()
        XCTAssertEqual(emptyNote.title, "First typed line", "A derived initial title should not keep changing")
    }

    func testSearchIncludesUnlockedVaultAndExcludesLockedVault() {
        let regular = Note(title: "Groceries", body: "Milk and tea")
        let secret = Note(title: "Launch code", body: "ORANGE-RIVER")
        let service = SearchService()

        XCTAssertEqual(service.search(query: "ORANGE", regular: [regular], vault: nil), [])
        let unlocked = service.search(query: "ORANGE", regular: [regular], vault: [secret])
        XCTAssertEqual(unlocked.map(\.note.id), [secret.id])
        XCTAssertEqual(unlocked.first?.source, .vault)
    }
}
