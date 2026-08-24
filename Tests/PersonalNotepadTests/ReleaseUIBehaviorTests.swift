import XCTest
@testable import PersonalNotepad

final class ReleaseUIBehaviorTests: XCTestCase {
    func testVaultBackupOperationStatePreventsOverlapAndProtectsInFlightDismissal() {
        let ready = VaultBackupOperationState(
            isExporting: false,
            isImporting: false,
            hasUnstoredRecoveryKey: false
        )
        XCTAssertTrue(ready.canStartOperation)
        XCTAssertFalse(ready.blocksDismissal)

        for busy in [
            VaultBackupOperationState(isExporting: true, isImporting: false, hasUnstoredRecoveryKey: false),
            VaultBackupOperationState(isExporting: false, isImporting: true, hasUnstoredRecoveryKey: false)
        ] {
            XCTAssertFalse(busy.canStartOperation)
            XCTAssertTrue(busy.blocksDismissal)
        }

        let awaitingKeyCustody = VaultBackupOperationState(
            isExporting: false,
            isImporting: false,
            hasUnstoredRecoveryKey: true
        )
        XCTAssertFalse(awaitingKeyCustody.canStartOperation)
        XCTAssertTrue(awaitingKeyCustody.blocksDismissal)
    }

    func testSelectionLifecycleTracksListMembershipWithoutDependingOnSearchOrTags() {
        let regular = Note(title: "Regular")
        let regularLifecycle = lifecycle(regular, source: .regular)
        XCTAssertTrue(regularLifecycle.remainsVisible(in: .inbox))
        XCTAssertTrue(regularLifecycle.remainsVisible(in: .allNotes))
        XCTAssertTrue(regularLifecycle.remainsVisible(in: .tag("edited-away")))
        XCTAssertFalse(regularLifecycle.remainsVisible(in: .pinned))
        XCTAssertFalse(regularLifecycle.remainsVisible(in: .vault))
        XCTAssertFalse(regularLifecycle.remainsVisible(in: .trash))

        var pinned = regular
        pinned.isPinned = true
        XCTAssertTrue(lifecycle(pinned, source: .regular).remainsVisible(in: .pinned))
        XCTAssertFalse(lifecycle(pinned, source: .vault).remainsVisible(in: .pinned))

        var archived = regular
        archived.isArchived = true
        archived.isInInbox = false
        XCTAssertFalse(lifecycle(archived, source: .regular).remainsVisible(in: .inbox))
        XCTAssertTrue(lifecycle(archived, source: .regular).remainsVisible(in: .allNotes))

        let vault = Note(title: "Vault")
        XCTAssertTrue(lifecycle(vault, source: .vault).remainsVisible(in: .vault))
        XCTAssertTrue(lifecycle(vault, source: .vault).remainsVisible(in: .allNotes))
        XCTAssertFalse(lifecycle(vault, source: .vault).remainsVisible(in: .tag("private")))

        var trashed = regular
        trashed.trashedAt = Date()
        let trashedLifecycle = lifecycle(trashed, source: .regular)
        XCTAssertTrue(trashedLifecycle.remainsVisible(in: .trash))
        XCTAssertFalse(trashedLifecycle.remainsVisible(in: .inbox))
        XCTAssertFalse(trashedLifecycle.remainsVisible(in: .allNotes))
        XCTAssertFalse(trashedLifecycle.remainsVisible(in: .tag("still-tagged")))
    }

    private func lifecycle(_ note: Note, source: SearchResult.Source) -> NoteSelectionLifecycle {
        NoteSelectionLifecycle(result: SearchResult(note: note, source: source))
    }
}
