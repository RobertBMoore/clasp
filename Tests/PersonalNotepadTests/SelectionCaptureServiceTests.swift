import AppKit
import XCTest
@testable import PersonalNotepad

#if !CLASP_APP_STORE
@MainActor
final class SelectionCaptureServiceTests: XCTestCase {
    func testSelectionCaptureRestoresThePreviousClipboard() async throws {
        let pasteboard = NSPasteboard(name: .init("ClaspSelectionTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("original clipboard", forType: .string)
        var copyEvents = 0

        let service = SelectionCaptureService(
            pasteboard: pasteboard,
            canPostEvents: { true },
            requestPostEventAccess: { true },
            postCopy: {
                copyEvents += 1
                pasteboard.clearContents()
                pasteboard.setString("selected content", forType: .string)
            },
            waitAttempts: 0,
            waitInterval: .zero
        )

        let captured = try await service.readSelection()

        XCTAssertEqual(captured, .text("selected content"))
        XCTAssertEqual(copyEvents, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "original clipboard")
    }

    func testSelectionCaptureRequestsPostEventPermissionOnce() async {
        let pasteboard = NSPasteboard(name: .init("ClaspSelectionTests.\(UUID().uuidString)"))
        var permissionRequests = 0
        let service = SelectionCaptureService(
            pasteboard: pasteboard,
            canPostEvents: { false },
            requestPostEventAccess: {
                permissionRequests += 1
                return false
            },
            postCopy: {},
            waitAttempts: 0,
            waitInterval: .zero
        )

        for _ in 0..<2 {
            do {
                _ = try await service.readSelection()
                XCTFail("Expected permission failure")
            } catch {
                XCTAssertEqual(error as? SelectionCaptureError, .postEventPermissionRequired)
            }
        }

        XCTAssertEqual(permissionRequests, 1)
    }

    func testMissingSelectionLeavesTheClipboardUntouched() async {
        let pasteboard = NSPasteboard(name: .init("ClaspSelectionTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("original clipboard", forType: .string)
        let service = SelectionCaptureService(
            pasteboard: pasteboard,
            canPostEvents: { true },
            requestPostEventAccess: { true },
            postCopy: {},
            waitAttempts: 0,
            waitInterval: .zero
        )

        do {
            _ = try await service.readSelection()
            XCTFail("Expected missing-selection failure")
        } catch {
            XCTAssertEqual(error as? SelectionCaptureError, .noSelection)
        }
        XCTAssertEqual(pasteboard.string(forType: .string), "original clipboard")
    }

    func testClipboardRestoreDoesNotOverwriteANewerCopy() {
        let pasteboard = NSPasteboard(name: .init("ClaspSelectionTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("original clipboard", forType: .string)
        let backup = PasteboardBackup(pasteboard: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("shortcut selection", forType: .string)
        let shortcutChangeCount = pasteboard.changeCount
        pasteboard.clearContents()
        pasteboard.setString("newer user copy", forType: .string)

        backup.restore(to: pasteboard, ifChangeCountIs: shortcutChangeCount)

        XCTAssertEqual(pasteboard.string(forType: .string), "newer user copy")
    }

    func testOversizedBackupFailsBeforePostingCopyEvent() async {
        let pasteboard = NSPasteboard(name: .init("ClaspSelectionTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setData(Data(repeating: 0x41, count: 5), forType: .init("dev.clasp.test"))
        var copyEvents = 0
        let budget = PasteboardBackupBudget(
            maximumItems: 2,
            maximumTypesPerItem: 2,
            maximumBytesPerType: 10,
            maximumBytesPerItem: 10,
            maximumAggregateBytes: 4
        )
        let service = SelectionCaptureService(
            pasteboard: pasteboard,
            canPostEvents: { true },
            requestPostEventAccess: { true },
            postCopy: { copyEvents += 1 },
            waitAttempts: 0,
            waitInterval: .zero,
            backupBudget: budget
        )

        do {
            _ = try await service.readSelection()
            XCTFail("Expected backup budget failure")
        } catch {
            XCTAssertEqual(error as? SelectionCaptureError, .clipboardCouldNotBePreserved)
        }
        XCTAssertEqual(copyEvents, 0)
    }

    func testPasteboardBackupEnforcesItemTypeAndByteBudgets() {
        let first = NSPasteboardItem()
        first.setData(Data(repeating: 0x41, count: 3), forType: .init("dev.clasp.first"))
        let second = NSPasteboardItem()
        second.setData(Data(repeating: 0x42, count: 3), forType: .init("dev.clasp.second"))
        let pasteboard = NSPasteboard(name: .init("ClaspSelectionTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects([first, second])

        XCTAssertFalse(PasteboardBackup(
            pasteboard: pasteboard,
            budget: .init(maximumItems: 1, maximumTypesPerItem: 2, maximumBytesPerType: 4, maximumBytesPerItem: 4, maximumAggregateBytes: 8)
        ).isComplete)
        XCTAssertFalse(PasteboardBackup(
            pasteboard: pasteboard,
            budget: .init(maximumItems: 2, maximumTypesPerItem: 2, maximumBytesPerType: 2, maximumBytesPerItem: 4, maximumAggregateBytes: 8)
        ).isComplete)
        XCTAssertFalse(PasteboardBackup(
            pasteboard: pasteboard,
            budget: .init(maximumItems: 2, maximumTypesPerItem: 2, maximumBytesPerType: 4, maximumBytesPerItem: 4, maximumAggregateBytes: 5)
        ).isComplete)

        let multiTypeItem = NSPasteboardItem()
        multiTypeItem.setData(Data([1]), forType: .init("dev.clasp.one"))
        multiTypeItem.setData(Data([2]), forType: .init("dev.clasp.two"))
        pasteboard.clearContents()
        pasteboard.writeObjects([multiTypeItem])
        XCTAssertFalse(PasteboardBackup(
            pasteboard: pasteboard,
            budget: .init(maximumItems: 2, maximumTypesPerItem: 1, maximumBytesPerType: 4, maximumBytesPerItem: 4, maximumAggregateBytes: 8)
        ).isComplete)
        XCTAssertFalse(PasteboardBackup(
            pasteboard: pasteboard,
            budget: .init(maximumItems: 2, maximumTypesPerItem: 2, maximumBytesPerType: 4, maximumBytesPerItem: 1, maximumAggregateBytes: 8)
        ).isComplete)
    }
}
#endif
