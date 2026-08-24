import Foundation
import XCTest
@testable import PersonalNotepad

@MainActor
final class AppStateTests: XCTestCase {
    func testRegularNoteLifecycleAndQuickCaptureRouting() async {
        let regular = MemoryRegularStore()
        let vault = MemoryVaultStore()
        let state = AppState(regularStore: regular, vaultStore: vault, clipboard: ClipboardService(client: FakeStateClipboard()))
        await state.start()

        let id = state.createRegular(body: "First line\nBody")
        guard var note = state.regularNotes.first(where: { $0.id == id }) else { return XCTFail("Missing note") }
        XCTAssertEqual(note.title, "First line")
        note.body = "Edited body"
        note.tags = ["Work", "work", "Ideas"]
        state.updateRegular(note, immediate: true)
        state.togglePin(id, isVault: false)
        state.moveOutOfInbox(id)
        XCTAssertEqual(state.regularNotes[0].tags, ["ideas", "work"])
        XCTAssertTrue(state.regularNotes[0].isPinned)
        XCTAssertFalse(state.regularNotes[0].isInInbox)

        state.trash(id, isVault: false)
        XCTAssertNotNil(state.regularNotes[0].trashedAt)
        state.restore(id, isVault: false)
        XCTAssertNil(state.regularNotes[0].trashedAt)
        await state.permanentlyDelete(id, isVault: false)
        XCTAssertTrue(state.regularNotes.isEmpty)

        let inboxSaved = await state.saveQuickCapture(body: "Inbox capture", destination: .inbox)
        let vaultSaved = await state.saveQuickCapture(body: "Vault capture", destination: .vault)
        XCTAssertTrue(inboxSaved)
        XCTAssertTrue(vaultSaved)
        XCTAssertEqual(state.regularNotes.first?.body, "Inbox capture")
        XCTAssertEqual(state.vaultNotes?.first?.body, "Vault capture")
    }

    func testLockingRemovesDecryptedVaultModelsAndSearchResults() async {
        let secret = Note(title: "Hidden Falcon", body: "classified")
        let vault = MemoryVaultStore(notes: [secret])
        let state = AppState(regularStore: MemoryRegularStore(), vaultStore: vault, clipboard: ClipboardService(client: FakeStateClipboard()))
        await state.start()
        let unlocked = await state.unlockVault()
        XCTAssertTrue(unlocked)
        XCTAssertEqual(state.search("Falcon", in: .vault).count, 1)
        XCTAssertEqual(state.search("Falcon", in: .allNotes).map(\.source), [.vault])
        state.lockVault()
        await vault.waitUntilLocked()
        XCTAssertNil(state.vaultNotes)
        XCTAssertEqual(state.search("Falcon", in: .vault), [])
        XCTAssertEqual(state.search("Falcon", in: .allNotes), [])
        XCTAssertTrue(vault.isLocked())
    }

    func testAllNotesAndTrashIncludeUnlockedVaultWhileOtherRegularOrganizationStaysIsolated() async {
        let regularNote = Note(title: "Regular", tags: ["shared"], isPinned: true)
        let vaultPinned = Note(title: "Vault pinned", tags: ["vault-tag"], isPinned: true)
        var vaultTrashed = Note(title: "Vault trashed")
        vaultTrashed.trashedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let state = AppState(
            regularStore: MemoryRegularStore(notes: [regularNote]),
            vaultStore: MemoryVaultStore(notes: [vaultPinned, vaultTrashed]),
            clipboard: ClipboardService(client: FakeStateClipboard())
        )
        await state.start()
        _ = await state.unlockVault()

        state.toggleArchive(regularNote.id, isVault: false)
        XCTAssertTrue(state.notes(for: .allNotes).contains { $0.id == regularNote.id })
        XCTAssertTrue(state.notes(for: .vault).contains { $0.id == vaultPinned.id })
        XCTAssertTrue(state.notes(for: .pinned).contains { $0.id == regularNote.id })
        XCTAssertTrue(state.notes(for: .allNotes).contains { $0.id == vaultPinned.id })
        XCTAssertEqual(
            state.noteResults(for: .allNotes).first(where: { $0.note.id == vaultPinned.id })?.source,
            .vault
        )
        XCTAssertFalse(state.notes(for: .pinned).contains { $0.id == vaultPinned.id })
        XCTAssertTrue(state.notes(for: .trash).contains { $0.id == vaultTrashed.id })
        XCTAssertEqual(
            state.noteResults(for: .trash).first(where: { $0.note.id == vaultTrashed.id })?.source,
            .vault
        )
        XCTAssertFalse(state.notes(for: .tag("vault-tag")).contains { $0.id == vaultPinned.id })
        XCTAssertFalse(state.allTags.contains("vault-tag"))
        XCTAssertEqual(state.search("Vault pinned", in: .allNotes).map(\.note.id), [vaultPinned.id])
        XCTAssertEqual(state.search("Vault pinned", in: .vault).map(\.note.id), [vaultPinned.id])

        state.lockVault()
        XCTAssertTrue(state.notes(for: .pinned).contains { $0.id == regularNote.id })
        XCTAssertFalse(state.notes(for: .allNotes).contains { $0.id == vaultPinned.id })
        XCTAssertFalse(state.notes(for: .trash).contains { $0.id == vaultTrashed.id })
        XCTAssertEqual(state.search("Vault pinned", in: .allNotes), [])
    }

    func testUnlockedVaultTrashCanBeLocatedRestoredAndPermanentlyDeleted() async {
        var vaultNote = Note(title: "Recoverable Vault note", body: "encrypted")
        vaultNote.trashedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let vault = MemoryVaultStore(notes: [vaultNote])
        let state = AppState(
            regularStore: MemoryRegularStore(),
            vaultStore: vault,
            clipboard: ClipboardService(client: FakeStateClipboard())
        )
        await state.start()
        let unlocked = await state.unlockVault()
        XCTAssertTrue(unlocked)

        let trashedResult = state.noteResults(for: .trash).first { $0.note.id == vaultNote.id }
        XCTAssertEqual(trashedResult?.source, .vault)

        state.restore(vaultNote.id, isVault: true)
        XCTAssertFalse(state.notes(for: .trash).contains { $0.id == vaultNote.id })
        XCTAssertTrue(state.notes(for: .vault).contains { $0.id == vaultNote.id })

        state.trash(vaultNote.id, isVault: true)
        XCTAssertTrue(state.notes(for: .trash).contains { $0.id == vaultNote.id })
        await state.permanentlyDelete(vaultNote.id, isVault: true)
        XCTAssertFalse(state.notes(for: .trash).contains { $0.id == vaultNote.id })
        XCTAssertFalse(state.vaultNotes?.contains { $0.id == vaultNote.id } ?? true)
    }

    func testEditorContentUpdatePreservesConcurrentOrganizationState() async {
        let original = Note(title: "Original", body: "Before", tags: ["draft"])
        let state = AppState(
            regularStore: MemoryRegularStore(notes: [original]),
            vaultStore: MemoryVaultStore(),
            clipboard: ClipboardService(client: FakeStateClipboard())
        )
        await state.start()

        state.togglePin(original.id, isVault: false)
        state.toggleArchive(original.id, isVault: false)
        state.updateEditorContent(
            id: original.id,
            isVault: false,
            title: "Edited",
            body: "After",
            tags: ["Review", "review"],
            immediate: true
        )

        let updated = state.regularNotes.first { $0.id == original.id }
        XCTAssertEqual(updated?.title, "Edited")
        XCTAssertEqual(updated?.body, "After")
        XCTAssertEqual(updated?.tags, ["review"])
        XCTAssertTrue(updated?.isPinned == true)
        XCTAssertTrue(updated?.isArchived == true)
        XCTAssertFalse(updated?.isInInbox == true)
    }

    func testEarlyCaptureIsMergedWithDiskLoadInsteadOfOverwritten() async {
        let persisted = Note(title: "Persisted", body: "From disk")
        let state = AppState(
            regularStore: MemoryRegularStore(notes: [persisted]),
            vaultStore: MemoryVaultStore(),
            clipboard: ClipboardService(client: FakeStateClipboard())
        )
        let earlyID = state.createRegular(body: "Cold launch service capture")
        await state.start()

        XCTAssertTrue(state.regularNotes.contains { $0.id == persisted.id })
        XCTAssertTrue(state.regularNotes.contains { $0.id == earlyID })
    }

    func testLockRejectsUnlockCompletionFromBeforeLockGeneration() async {
        let secret = Note(title: "Post-lock secret", body: "must remain locked")
        let vault = DelayedUnlockVaultStore(result: [secret])
        let state = AppState(
            regularStore: MemoryRegularStore(),
            vaultStore: vault,
            clipboard: ClipboardService(client: FakeStateClipboard())
        )

        let unlock = Task { @MainActor in await state.unlockVault() }
        await vault.waitUntilUnlockIsSuspended()
        state.lockVault()
        await vault.waitUntilLocked()
        await vault.resumeUnlock()

        let unlockResult = await unlock.value
        XCTAssertFalse(unlockResult)
        XCTAssertNil(state.vaultNotes)
        XCTAssertFalse(state.isVaultUnlocked)
    }

    func testLockAndTerminationFlushLatestSnapshotsBeforeKeyClear() async {
        let regular = MemoryRegularStore()
        let vaultNote = Note(title: "Vault", body: "original")
        let vault = MemoryVaultStore(notes: [vaultNote])
        let state = AppState(
            regularStore: regular,
            vaultStore: vault,
            clipboard: ClipboardService(client: FakeStateClipboard())
        )
        await state.start()
        _ = await state.unlockVault()

        var changedVault = vaultNote
        changedVault.body = "latest vault text"
        state.updateVault(changedVault)
        let regularID = state.createRegular(body: "latest regular text")
        guard var changedRegular = state.regularNotes.first(where: { $0.id == regularID }) else {
            return XCTFail("Missing regular note")
        }
        changedRegular.body = "latest regular edit"
        state.updateRegular(changedRegular)

        await state.flushAndLockForTermination()
        let persistedRegular = try? await regular.load()

        XCTAssertNil(state.vaultNotes)
        XCTAssertTrue(vault.isLocked())
        XCTAssertEqual(vault.snapshot().first?.body, "latest vault text")
        XCTAssertEqual(persistedRegular?.first?.body, "latest regular edit")
    }

    func testTerminationWaitsForInFlightRegularDeleteBeforeLocking() async {
        let note = Note(title: "Delete before quit", body: "Do not resurrect")
        let regular = BlockingDeleteRegularStore(notes: [note])
        let vault = MemoryVaultStore()
        let state = AppState(
            regularStore: regular,
            vaultStore: vault,
            clipboard: ClipboardService(client: FakeStateClipboard())
        )
        await state.start()

        let deleteTask = Task { @MainActor in
            await state.permanentlyDelete(note.id, isVault: false)
        }
        await regular.waitUntilDeleteStarted()
        XCTAssertTrue(state.regularNotes.isEmpty)

        let flushProbe = FlushStartProbe()
        let flushTask = Task { @MainActor in
            flushProbe.didStart = true
            await state.flushAndLockForTermination()
        }
        while !flushProbe.didStart { await Task.yield() }
        for _ in 0..<10 { await Task.yield() }

        XCTAssertFalse(
            vault.isLocked(),
            "Termination must not finish while the only note's permanent deletion is suspended"
        )

        await regular.resumeDelete()
        await deleteTask.value
        await flushTask.value

        let persistedNotes = try? await regular.load()
        XCTAssertTrue(vault.isLocked())
        XCTAssertEqual(persistedNotes, [])
    }

    func testTerminationWaitsForInFlightInboxClassificationBeforeSnapshot() async {
        let classifier = BlockingContentClassifier(
            result: ClassifiedCapture(
                title: "Captured before quit",
                body: "Persist this capture",
                tags: ["note"],
                contentType: .note,
                attachments: [],
                extractedText: ""
            )
        )
        let regular = MemoryRegularStore()
        let vault = MemoryVaultStore()
        let state = AppState(
            regularStore: regular,
            vaultStore: vault,
            clipboard: ClipboardService(client: FakeStateClipboard()),
            classifier: classifier
        )
        await state.start()

        let captureTask = Task { @MainActor in
            await state.capture(.text("incoming"), to: .inbox)
        }
        await classifier.waitUntilClassificationStarted()
        XCTAssertTrue(state.regularNotes.isEmpty)

        let flushProbe = FlushStartProbe()
        let flushTask = Task { @MainActor in
            flushProbe.didStart = true
            await state.flushAndLockForTermination()
        }
        while !flushProbe.didStart { await Task.yield() }
        for _ in 0..<10 { await Task.yield() }

        XCTAssertFalse(
            vault.isLocked(),
            "Termination must not snapshot before an accepted Inbox capture finishes classification"
        )

        await classifier.resumeClassification()
        let didCapture = await captureTask.value
        await flushTask.value

        let persistedBodies = (try? await regular.load())?.map(\.body)
        XCTAssertTrue(didCapture)
        XCTAssertTrue(vault.isLocked())
        XCTAssertEqual(persistedBodies, ["Persist this capture"])
    }

    func testTerminationWaitsForInFlightVaultDeleteAndRejectsNewMutations() async {
        let note = Note(title: "Private delete before quit", body: "Do not race the Vault snapshot")
        let vault = FirstSaveBlockingVaultDeleteStore(notes: [note])
        let state = AppState(
            regularStore: MemoryRegularStore(),
            vaultStore: vault,
            clipboard: ClipboardService(client: FakeStateClipboard())
        )
        await state.start()
        let unlocked = await state.unlockVault()
        XCTAssertTrue(unlocked)

        let deleteTask = Task { @MainActor in
            await state.permanentlyDelete(note.id, isVault: true)
        }
        await vault.waitUntilFirstSaveStarted()
        XCTAssertTrue(state.vaultNotes?.isEmpty == true)

        let flushProbe = FlushStartProbe()
        let flushTask = Task { @MainActor in
            flushProbe.didStart = true
            await state.flushAndLockForTermination()
        }
        while !flushProbe.didStart { await Task.yield() }
        for _ in 0..<10 { await Task.yield() }

        let lockedBeforeDeleteFinished = await vault.isLocked()
        XCTAssertFalse(
            lockedBeforeDeleteFinished,
            "Termination must not snapshot and lock while a Vault deletion is suspended"
        )

        let lateVaultNote = await state.createVault(body: "Must be rejected after termination starts")
        XCTAssertNil(lateVaultNote)

        await vault.resumeFirstSave()
        await deleteTask.value
        await flushTask.value

        let persisted = await vault.persistedNotes()
        let isLocked = await vault.isLocked()
        XCTAssertTrue(isLocked)
        XCTAssertTrue(persisted.isEmpty)
    }

    func testUnlockWaitsForPendingLockToFinishBeforeReadingKeyAgain() async {
        let secret = Note(title: "Serialized Vault", body: "safe transition")
        let vault = BlockingLockVaultStore(notes: [secret])
        let state = AppState(
            regularStore: MemoryRegularStore(),
            vaultStore: vault,
            clipboard: ClipboardService(client: FakeStateClipboard())
        )
        await state.start()
        let initiallyUnlocked = await state.unlockVault()
        XCTAssertTrue(initiallyUnlocked)

        state.lockVault()
        await vault.waitUntilLockIsSuspended()
        XCTAssertTrue(state.isVaultLocking)
        XCTAssertNil(state.vaultNotes)

        let reunlock = Task { @MainActor in await state.unlockVault() }
        await Task.yield()
        let unlocksBeforeLockFinished = await vault.unlockCallCount()
        XCTAssertEqual(unlocksBeforeLockFinished, 1)

        await vault.resumeLock()
        let reunlocked = await reunlock.value
        let totalUnlocks = await vault.unlockCallCount()
        let storeIsLocked = await vault.isLocked()
        XCTAssertTrue(reunlocked)
        XCTAssertFalse(state.isVaultLocking)
        XCTAssertEqual(state.vaultNotes, [secret])
        XCTAssertEqual(totalUnlocks, 2)
        XCTAssertFalse(storeIsLocked)
    }

    func testIncomingContentIsClassifiedAndCanRouteDirectlyToVault() async {
        let state = AppState(
            regularStore: MemoryRegularStore(),
            vaultStore: MemoryVaultStore(),
            clipboard: ClipboardService(client: FakeStateClipboard())
        )
        await state.start()

        let regularSaved = await state.capture(.text("https://www.example.com/reference"), to: .inbox)
        XCTAssertTrue(regularSaved)
        XCTAssertEqual(state.regularNotes.first?.contentType, .link)
        XCTAssertTrue(state.regularNotes.first?.tags.contains("example.com") == true)
        XCTAssertEqual(state.statusMessage, "Normal note added to Inbox")

        let image = CapturedImage(pngData: Data("TEST-IMAGE-BYTES".utf8), pixelWidth: 1_200, pixelHeight: 800)
        let vaultSaved = await state.capture(.image(image), to: .vault)
        XCTAssertTrue(vaultSaved)
        XCTAssertEqual(state.vaultNotes?.first?.contentType, .image)
        XCTAssertEqual(state.vaultNotes?.first?.attachments.first?.data, image.pngData)
        XCTAssertTrue(state.vaultNotes?.first?.tags.contains("landscape") == true)
        XCTAssertEqual(state.statusMessage, "Secure note added to Vault")
    }

    func testPermanentDeleteRestoresNotesWhenPersistenceFails() async {
        let regularNote = Note(title: "Regular", body: "Keep on failure")
        let regularStore = FailingDeleteRegularStore(notes: [regularNote])
        let regularState = AppState(
            regularStore: regularStore,
            vaultStore: MemoryVaultStore(),
            clipboard: ClipboardService(client: FakeStateClipboard())
        )
        await regularState.start()
        await regularState.permanentlyDelete(regularNote.id, isVault: false)
        XCTAssertEqual(regularState.regularNotes, [regularNote])
        XCTAssertNotNil(regularState.presentedError)

        let vaultNote = Note(title: "Vault", body: "Keep encrypted")
        let vaultStore = FailingSaveVaultStore(notes: [vaultNote])
        let vaultState = AppState(
            regularStore: MemoryRegularStore(),
            vaultStore: vaultStore,
            clipboard: ClipboardService(client: FakeStateClipboard())
        )
        await vaultState.start()
        let unlocked = await vaultState.unlockVault()
        XCTAssertTrue(unlocked)
        await vaultState.permanentlyDelete(vaultNote.id, isVault: true)
        XCTAssertEqual(vaultState.vaultNotes, [vaultNote])
        XCTAssertNotNil(vaultState.presentedError)
    }

    func testFailedVaultClipboardSaveDoesNotClearClipboardOrLeaveAPhantomNote() async {
        let defaults = UserDefaults.standard
        let previousDelay = defaults.string(forKey: PreferenceKeys.clipboardClearDelay)
        defaults.set(ClipboardClearDelay.immediately.rawValue, forKey: PreferenceKeys.clipboardClearDelay)
        defer {
            if let previousDelay { defaults.set(previousDelay, forKey: PreferenceKeys.clipboardClearDelay) }
            else { defaults.removeObject(forKey: PreferenceKeys.clipboardClearDelay) }
        }

        let clipboard = FakeStateClipboard(snapshot: ClipboardSnapshot(value: "Do not lose me", changeCount: 7))
        let state = AppState(
            regularStore: MemoryRegularStore(),
            vaultStore: FailingSaveVaultStore(),
            clipboard: ClipboardService(client: clipboard)
        )
        await state.start()

        await state.saveClipboardToVaultAndClear()
        try? await Task.sleep(for: .milliseconds(40))

        XCTAssertEqual(clipboard.clearCount, 0)
        XCTAssertEqual(state.vaultNotes, [])
        XCTAssertNotNil(state.presentedError)
    }

    func testManualVaultLockCancelsClipboardCaptureStillBeingClassified() async {
        let defaults = UserDefaults.standard
        let previousDelay = defaults.string(forKey: PreferenceKeys.clipboardClearDelay)
        defaults.set(ClipboardClearDelay.immediately.rawValue, forKey: PreferenceKeys.clipboardClearDelay)
        defer {
            if let previousDelay { defaults.set(previousDelay, forKey: PreferenceKeys.clipboardClearDelay) }
            else { defaults.removeObject(forKey: PreferenceKeys.clipboardClearDelay) }
        }

        let classifier = BlockingContentClassifier(
            result: ClassifiedCapture(
                title: "Must remain cancelled",
                body: "Do not reopen the Vault",
                tags: ["secure"],
                contentType: .note,
                attachments: [],
                extractedText: ""
            )
        )
        let clipboard = FakeStateClipboard(
            snapshot: ClipboardSnapshot(value: "Do not clear me", changeCount: 13)
        )
        let vault = MemoryVaultStore()
        let state = AppState(
            regularStore: MemoryRegularStore(),
            vaultStore: vault,
            clipboard: ClipboardService(client: clipboard),
            classifier: classifier
        )
        await state.start()

        let captureTask = Task { @MainActor in
            await state.saveClipboardToVaultAndClear()
        }
        await classifier.waitUntilClassificationStarted()

        state.lockVault()
        await vault.waitUntilLocked()
        await classifier.resumeClassification()
        await captureTask.value
        try? await Task.sleep(for: .milliseconds(40))

        XCTAssertNil(state.vaultNotes)
        XCTAssertTrue(vault.snapshot().isEmpty)
        XCTAssertEqual(clipboard.clearCount, 0)
        XCTAssertEqual(clipboard.snapshot?.content, .text("Do not clear me"))
    }

    func testVaultImportReadsAtMostConfiguredMaximumPlusOne() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let exactURL = root.appendingPathComponent("exact.export")
        let oversizedURL = root.appendingPathComponent("oversized.export")
        let exact = Data(repeating: 0x41, count: 8)
        try exact.write(to: exactURL)
        try Data(repeating: 0x42, count: 9).write(to: oversizedURL)

        let vault = RecordingImportVaultStore()
        let state = AppState(
            regularStore: MemoryRegularStore(),
            vaultStore: vault,
            clipboard: ClipboardService(client: FakeStateClipboard()),
            vaultImportMaximumBytes: 8
        )
        await state.start()

        let exactImported = await state.importVault(from: exactURL, recoveryKey: RecoveryKey())
        let payloadsAfterExactImport = await vault.importedPayloads()
        XCTAssertTrue(exactImported)
        XCTAssertEqual(payloadsAfterExactImport, [exact])
        let oversizedImported = await state.importVault(from: oversizedURL, recoveryKey: RecoveryKey())
        let payloadsAfterOversizedImport = await vault.importedPayloads()
        XCTAssertFalse(oversizedImported)
        XCTAssertEqual(payloadsAfterOversizedImport, [exact], "Oversized data must not reach Vault decoding")
        XCTAssertNotNil(state.presentedError)
    }

    func testVaultImportSerializesPendingSaveAndRejectsEditsDuringReplacement() async throws {
        let original = Note(title: "Original", body: "before import")
        let imported = Note(title: "Imported", body: "replacement")
        let vault = BlockingSaveAndImportVaultStore(notes: [original], importedNotes: [imported])
        let state = AppState(
            regularStore: MemoryRegularStore(),
            vaultStore: vault,
            clipboard: ClipboardService(client: FakeStateClipboard())
        )
        await state.start()
        _ = await state.unlockVault()

        var pendingEdit = original
        pendingEdit.body = "pending before import"
        state.updateVault(pendingEdit, immediate: true)
        await vault.waitUntilFirstSaveStarted()

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("bounded test export".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let importTask = Task { @MainActor in
            await state.importVault(from: url, recoveryKey: RecoveryKey())
        }

        for _ in 0..<100 { await Task.yield() }
        let importStartedBeforePendingSaveFinished = await vault.hasImportStarted()

        if importStartedBeforePendingSaveFinished {
            var concurrentEdit = pendingEdit
            concurrentEdit.body = "edit while importing"
            state.updateVault(concurrentEdit, immediate: true)
            await vault.waitUntilSaveCallCount(2)
            await vault.resumeImport()
            await vault.waitUntilImportFinished()
            await vault.resumeFirstSave()
        } else {
            await vault.resumeFirstSave()
            await vault.waitUntilImportStarted()
            var concurrentEdit = pendingEdit
            concurrentEdit.body = "edit while importing"
            state.updateVault(concurrentEdit, immediate: true)
            await vault.resumeImport()
        }

        let didImport = await importTask.value
        let saveCallCount = await vault.saveCallCount()
        let persisted = await vault.persistedNotes()
        XCTAssertTrue(didImport)
        XCTAssertFalse(importStartedBeforePendingSaveFinished, "Import must drain an in-flight save before replacing the Vault")
        XCTAssertEqual(saveCallCount, 1, "Edits against the pre-import model must not enqueue stale saves")
        XCTAssertEqual(persisted, [imported])
        XCTAssertEqual(state.vaultNotes, [imported])
    }

    func testStaleRegularSaveCompletionCannotHideNewerSaveAndRecreateDeletedNote() async {
        let original = Note(title: "Regular", body: "original")
        let store = FirstSaveBlockingRegularStore(notes: [original])
        let state = AppState(
            regularStore: store,
            vaultStore: MemoryVaultStore(),
            clipboard: ClipboardService(client: FakeStateClipboard())
        )
        await state.start()

        var firstEdit = original
        firstEdit.body = "first edit"
        state.updateRegular(firstEdit, immediate: true)
        await store.waitUntilFirstSaveStarted()

        var newestEdit = firstEdit
        newestEdit.body = "newest edit"
        state.updateRegular(newestEdit)

        await store.resumeFirstSave()
        await store.waitUntilFirstSaveFinished()
        try? await Task.sleep(for: .milliseconds(100))

        await state.permanentlyDelete(original.id, isVault: false)
        try? await Task.sleep(for: .milliseconds(600))

        let persisted = await store.persistedNotes()
        let saveCalls = await store.saveCallCount()
        XCTAssertFalse(state.regularNotes.contains { $0.id == original.id })
        XCTAssertFalse(persisted.contains { $0.id == original.id })
        XCTAssertEqual(saveCalls, 1, "Permanent deletion must cancel the still-current debounced save")
    }

    func testStaleVaultSaveCompletionCannotHideNewerSaveAndOverwriteImport() async throws {
        let original = Note(title: "Vault", body: "original")
        let imported = Note(title: "Imported", body: "replacement")
        let store = FirstSaveBlockingVaultStore(notes: [original], importedNotes: [imported])
        let state = AppState(
            regularStore: MemoryRegularStore(),
            vaultStore: store,
            clipboard: ClipboardService(client: FakeStateClipboard())
        )
        await state.start()
        let unlocked = await state.unlockVault()
        XCTAssertTrue(unlocked)

        var firstEdit = original
        firstEdit.body = "first edit"
        state.updateVault(firstEdit, immediate: true)
        await store.waitUntilFirstSaveStarted()

        var newestEdit = firstEdit
        newestEdit.body = "newest edit"
        state.updateVault(newestEdit)

        await store.resumeFirstSave()
        await store.waitUntilFirstSaveFinished()
        try? await Task.sleep(for: .milliseconds(100))

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("bounded test export".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let didImport = await state.importVault(from: url, recoveryKey: RecoveryKey())
        XCTAssertTrue(didImport)
        try? await Task.sleep(for: .milliseconds(600))

        let persisted = await store.persistedNotes()
        let saveCalls = await store.saveCallCount()
        XCTAssertEqual(state.vaultNotes, [imported])
        XCTAssertEqual(persisted, [imported])
        XCTAssertEqual(saveCalls, 1, "Import must cancel and drain the still-current debounced save")
    }
}

private final class MemoryRegularStore: @unchecked Sendable, RegularNoteStoring {
    private let lock = NSLock()
    private var notes: [Note]
    init(notes: [Note] = []) { self.notes = notes }
    func load() async throws -> [Note] { lock.withLock { notes } }
    func save(_ note: Note) async throws { lock.withLock { notes.removeAll { $0.id == note.id }; notes.append(note) } }
    func permanentlyDelete(id: UUID) async throws { lock.withLock { notes.removeAll { $0.id == id } } }
    func rebuildIndex() async throws -> [Note] { lock.withLock { notes } }
}

private final class FailingDeleteRegularStore: @unchecked Sendable, RegularNoteStoring {
    private let notes: [Note]
    init(notes: [Note]) { self.notes = notes }
    func load() async throws -> [Note] { notes }
    func save(_ note: Note) async throws {}
    func permanentlyDelete(id: UUID) async throws { throw AtomicWriteFailure() }
    func rebuildIndex() async throws -> [Note] { notes }
}

private actor BlockingDeleteRegularStore: RegularNoteStoring {
    private var notes: [Note]
    private var deleteStarted = false
    private var deleteContinuation: CheckedContinuation<Void, Never>?

    init(notes: [Note]) { self.notes = notes }

    func load() async throws -> [Note] { notes }
    func save(_ note: Note) async throws {
        notes.removeAll { $0.id == note.id }
        notes.append(note)
    }
    func permanentlyDelete(id: UUID) async throws {
        deleteStarted = true
        await withCheckedContinuation { deleteContinuation = $0 }
        notes.removeAll { $0.id == id }
    }
    func rebuildIndex() async throws -> [Note] { notes }

    func waitUntilDeleteStarted() async {
        while !deleteStarted || deleteContinuation == nil { await Task.yield() }
    }
    func resumeDelete() {
        let continuation = deleteContinuation
        deleteContinuation = nil
        continuation?.resume()
    }
}

private actor BlockingContentClassifier: ContentClassifying {
    private let result: ClassifiedCapture
    private var classificationStarted = false
    private var classificationContinuation: CheckedContinuation<Void, Never>?

    init(result: ClassifiedCapture) { self.result = result }

    func classify(_ content: CapturedContent) async -> ClassifiedCapture {
        classificationStarted = true
        await withCheckedContinuation { classificationContinuation = $0 }
        return result
    }

    func waitUntilClassificationStarted() async {
        while !classificationStarted || classificationContinuation == nil { await Task.yield() }
    }
    func resumeClassification() {
        let continuation = classificationContinuation
        classificationContinuation = nil
        continuation?.resume()
    }
}

private actor FirstSaveBlockingVaultDeleteStore: VaultStoring {
    private var notes: [Note]
    private var locked = true
    private var saves = 0
    private var firstSaveStarted = false
    private var firstSaveContinuation: CheckedContinuation<Void, Never>?

    init(notes: [Note]) { self.notes = notes }

    func isConfigured() async -> Bool { true }
    func setup() async throws -> [Note] { notes }
    func unlock() async throws -> [Note] {
        locked = false
        return notes
    }
    func save(_ notes: [Note]) async throws {
        saves += 1
        if saves == 1 {
            firstSaveStarted = true
            await withCheckedContinuation { firstSaveContinuation = $0 }
        }
        self.notes = notes
    }
    func lock() async { locked = true }
    func export(notes: [Note]) async throws -> (data: Data, recoveryKey: RecoveryKey) {
        (Data(), RecoveryKey())
    }
    func importVault(_ data: Data, recoveryKey: RecoveryKey) async throws -> [Note] { notes }

    func waitUntilFirstSaveStarted() async {
        while !firstSaveStarted || firstSaveContinuation == nil { await Task.yield() }
    }
    func resumeFirstSave() {
        let continuation = firstSaveContinuation
        firstSaveContinuation = nil
        continuation?.resume()
    }
    func persistedNotes() -> [Note] { notes }
    func isLocked() -> Bool { locked }
}

@MainActor
private final class FlushStartProbe {
    var didStart = false
}

private actor FirstSaveBlockingRegularStore: RegularNoteStoring {
    private var notes: [Note]
    private var saves = 0
    private var firstSaveStarted = false
    private var firstSaveFinished = false
    private var firstSaveContinuation: CheckedContinuation<Void, Never>?

    init(notes: [Note]) { self.notes = notes }

    func load() async throws -> [Note] { notes }
    func save(_ note: Note) async throws {
        saves += 1
        if saves == 1 {
            firstSaveStarted = true
            await withCheckedContinuation { firstSaveContinuation = $0 }
            firstSaveFinished = true
        }
        notes.removeAll { $0.id == note.id }
        notes.append(note)
    }
    func permanentlyDelete(id: UUID) async throws { notes.removeAll { $0.id == id } }
    func rebuildIndex() async throws -> [Note] { notes }

    func waitUntilFirstSaveStarted() async {
        while !firstSaveStarted || firstSaveContinuation == nil { await Task.yield() }
    }
    func resumeFirstSave() {
        let continuation = firstSaveContinuation
        firstSaveContinuation = nil
        continuation?.resume()
    }
    func waitUntilFirstSaveFinished() async {
        while !firstSaveFinished { await Task.yield() }
    }
    func persistedNotes() -> [Note] { notes }
    func saveCallCount() -> Int { saves }
}

private final class FailingSaveVaultStore: @unchecked Sendable, VaultStoring {
    private let lock = NSLock()
    private var notes: [Note]
    init(notes: [Note] = []) { self.notes = notes }
    func isConfigured() async -> Bool { true }
    func setup() async throws -> [Note] { lock.withLock { notes } }
    func unlock() async throws -> [Note] { lock.withLock { notes } }
    func save(_ notes: [Note]) async throws { throw AtomicWriteFailure() }
    func lock() async {}
    func export(notes: [Note]) async throws -> (data: Data, recoveryKey: RecoveryKey) { (Data(), RecoveryKey()) }
    func importVault(_ data: Data, recoveryKey: RecoveryKey) async throws -> [Note] { lock.withLock { notes } }
}

private final class MemoryVaultStore: @unchecked Sendable, VaultStoring {
    private let lock = NSLock()
    private var notes: [Note]
    private(set) var wasLocked = false
    init(notes: [Note] = []) { self.notes = notes }
    func isConfigured() async -> Bool { true }
    func setup() async throws -> [Note] { lock.withLock { notes } }
    func unlock() async throws -> [Note] { lock.withLock { notes } }
    func save(_ notes: [Note]) async throws { lock.withLock { self.notes = notes } }
    func lock() async { lock.withLock { wasLocked = true } }
    func export(notes: [Note]) async throws -> (data: Data, recoveryKey: RecoveryKey) { (Data(), RecoveryKey()) }
    func importVault(_ data: Data, recoveryKey: RecoveryKey) async throws -> [Note] { lock.withLock { notes } }
    func snapshot() -> [Note] { lock.withLock { notes } }
    func isLocked() -> Bool { lock.withLock { wasLocked } }
    func waitUntilLocked() async {
        while !isLocked() { await Task.yield() }
    }
}

private actor RecordingImportVaultStore: VaultStoring {
    private var payloads: [Data] = []
    func isConfigured() async -> Bool { true }
    func setup() async throws -> [Note] { [] }
    func unlock() async throws -> [Note] { [] }
    func save(_ notes: [Note]) async throws {}
    func lock() async {}
    func export(notes: [Note]) async throws -> (data: Data, recoveryKey: RecoveryKey) { (Data(), RecoveryKey()) }
    func importVault(_ data: Data, recoveryKey: RecoveryKey) async throws -> [Note] {
        payloads.append(data)
        return []
    }
    func importedPayloads() -> [Data] { payloads }
}

private actor FirstSaveBlockingVaultStore: VaultStoring {
    private var notes: [Note]
    private let imported: [Note]
    private var saves = 0
    private var firstSaveStarted = false
    private var firstSaveFinished = false
    private var firstSaveContinuation: CheckedContinuation<Void, Never>?

    init(notes: [Note], importedNotes: [Note]) {
        self.notes = notes
        imported = importedNotes
    }

    func isConfigured() async -> Bool { true }
    func setup() async throws -> [Note] { notes }
    func unlock() async throws -> [Note] { notes }
    func save(_ notes: [Note]) async throws {
        saves += 1
        if saves == 1 {
            firstSaveStarted = true
            await withCheckedContinuation { firstSaveContinuation = $0 }
            firstSaveFinished = true
        }
        self.notes = notes
    }
    func lock() async {}
    func export(notes: [Note]) async throws -> (data: Data, recoveryKey: RecoveryKey) {
        (Data(), RecoveryKey())
    }
    func importVault(_ data: Data, recoveryKey: RecoveryKey) async throws -> [Note] {
        notes = imported
        return imported
    }

    func waitUntilFirstSaveStarted() async {
        while !firstSaveStarted || firstSaveContinuation == nil { await Task.yield() }
    }
    func resumeFirstSave() {
        let continuation = firstSaveContinuation
        firstSaveContinuation = nil
        continuation?.resume()
    }
    func waitUntilFirstSaveFinished() async {
        while !firstSaveFinished { await Task.yield() }
    }
    func persistedNotes() -> [Note] { notes }
    func saveCallCount() -> Int { saves }
}

private actor BlockingSaveAndImportVaultStore: VaultStoring {
    private var notes: [Note]
    private let imported: [Note]
    private var saves = 0
    private var firstSaveStarted = false
    private var firstSaveContinuation: CheckedContinuation<Void, Never>?
    private var importStarted = false
    private var importFinished = false
    private var importContinuation: CheckedContinuation<Void, Never>?

    init(notes: [Note], importedNotes: [Note]) {
        self.notes = notes
        imported = importedNotes
    }

    func isConfigured() async -> Bool { true }
    func setup() async throws -> [Note] { notes }
    func unlock() async throws -> [Note] { notes }
    func save(_ notes: [Note]) async throws {
        saves += 1
        if saves == 1 {
            firstSaveStarted = true
            await withCheckedContinuation { firstSaveContinuation = $0 }
        }
        self.notes = notes
    }
    func lock() async {}
    func export(notes: [Note]) async throws -> (data: Data, recoveryKey: RecoveryKey) { (Data(), RecoveryKey()) }
    func importVault(_ data: Data, recoveryKey: RecoveryKey) async throws -> [Note] {
        importStarted = true
        await withCheckedContinuation { importContinuation = $0 }
        notes = imported
        importFinished = true
        return imported
    }

    func waitUntilFirstSaveStarted() async {
        while !firstSaveStarted || firstSaveContinuation == nil { await Task.yield() }
    }
    func resumeFirstSave() {
        let continuation = firstSaveContinuation
        firstSaveContinuation = nil
        continuation?.resume()
    }
    func hasImportStarted() -> Bool { importStarted }
    func waitUntilImportStarted() async {
        while !importStarted || importContinuation == nil { await Task.yield() }
    }
    func resumeImport() {
        let continuation = importContinuation
        importContinuation = nil
        continuation?.resume()
    }
    func waitUntilImportFinished() async {
        while !importFinished { await Task.yield() }
    }
    func waitUntilSaveCallCount(_ count: Int) async {
        while saves < count { await Task.yield() }
    }
    func saveCallCount() -> Int { saves }
    func persistedNotes() -> [Note] { notes }
}

private actor DelayedUnlockVaultStore: VaultStoring {
    private let result: [Note]
    private var unlockContinuation: CheckedContinuation<[Note], Never>?
    private var locked = false

    init(result: [Note]) { self.result = result }

    func isConfigured() async -> Bool { true }
    func setup() async throws -> [Note] { [] }
    func unlock() async throws -> [Note] {
        await withCheckedContinuation { unlockContinuation = $0 }
    }
    func save(_ notes: [Note]) async throws {}
    func lock() async { locked = true }
    func export(notes: [Note]) async throws -> (data: Data, recoveryKey: RecoveryKey) {
        (Data(), RecoveryKey())
    }
    func importVault(_ data: Data, recoveryKey: RecoveryKey) async throws -> [Note] { result }

    func waitUntilUnlockIsSuspended() async {
        while unlockContinuation == nil { await Task.yield() }
    }
    func waitUntilLocked() async {
        while !locked { await Task.yield() }
    }
    func resumeUnlock() {
        let continuation = unlockContinuation
        unlockContinuation = nil
        continuation?.resume(returning: result)
    }
}

private actor BlockingLockVaultStore: VaultStoring {
    private var notes: [Note]
    private var unlockCalls = 0
    private var locked = true
    private var lockStarted = false
    private var lockContinuation: CheckedContinuation<Void, Never>?

    init(notes: [Note]) { self.notes = notes }

    func isConfigured() async -> Bool { true }
    func setup() async throws -> [Note] { notes }
    func unlock() async throws -> [Note] {
        unlockCalls += 1
        locked = false
        return notes
    }
    func save(_ notes: [Note]) async throws { self.notes = notes }
    func lock() async {
        lockStarted = true
        await withCheckedContinuation { lockContinuation = $0 }
        locked = true
    }
    func export(notes: [Note]) async throws -> (data: Data, recoveryKey: RecoveryKey) {
        (Data(), RecoveryKey())
    }
    func importVault(_ data: Data, recoveryKey: RecoveryKey) async throws -> [Note] { notes }

    func waitUntilLockIsSuspended() async {
        while !lockStarted || lockContinuation == nil { await Task.yield() }
    }
    func resumeLock() {
        let continuation = lockContinuation
        lockContinuation = nil
        continuation?.resume()
    }
    func unlockCallCount() -> Int { unlockCalls }
    func isLocked() -> Bool { locked }
}

@MainActor
private final class FakeStateClipboard: ClipboardClient {
    var snapshot: ClipboardSnapshot?
    private(set) var clearCount = 0
    init(snapshot: ClipboardSnapshot? = nil) { self.snapshot = snapshot }
    func readContent() -> ClipboardSnapshot? { snapshot }
    func currentSnapshot() -> ClipboardSnapshot? { snapshot }
    func clear() { clearCount += 1; snapshot = nil }
}
