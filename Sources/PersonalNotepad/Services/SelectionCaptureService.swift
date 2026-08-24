import AppKit
import Carbon
import CoreGraphics
import Foundation

#if !CLASP_APP_STORE
enum SelectionCaptureError: LocalizedError, Equatable {
    case postEventPermissionRequired
    case clipboardCouldNotBePreserved
    case noSelection

    var errorDescription: String? {
        switch self {
        case .postEventPermissionRequired:
            "Allow Clasp in System Settings › Privacy & Security › Accessibility, then try the shortcut again."
        case .clipboardCouldNotBePreserved:
            "Clasp could not safely preserve the current clipboard. Use the right-click Service instead."
        case .noSelection:
            "No selected text, link, or image was found."
        }
    }
}

struct PasteboardBackupBudget: Equatable, Sendable {
    /// The selection shortcut preserves a useful clipboard (including one
    /// maximum-size captured image) while bounding every retained dimension.
    static let standard = Self(
        maximumItems: 32,
        maximumTypesPerItem: 64,
        maximumBytesPerType: 25 * 1_024 * 1_024,
        maximumBytesPerItem: 32 * 1_024 * 1_024,
        maximumAggregateBytes: 64 * 1_024 * 1_024
    )

    var maximumItems: Int
    var maximumTypesPerItem: Int
    var maximumBytesPerType: Int
    var maximumBytesPerItem: Int
    var maximumAggregateBytes: Int
}

@MainActor
final class SelectionCaptureService {
    typealias PermissionCheck = @MainActor () -> Bool
    typealias PermissionRequest = @MainActor () -> Bool
    typealias CopyEvent = @MainActor () -> Void

    private let pasteboard: NSPasteboard
    private let canPostEvents: PermissionCheck
    private let requestPostEventAccess: PermissionRequest
    private let postCopy: CopyEvent
    private let waitAttempts: Int
    private let waitInterval: Duration
    private let backupBudget: PasteboardBackupBudget
    private var hasRequestedPermission = false

    init(
        pasteboard: NSPasteboard = .general,
        canPostEvents: @escaping PermissionCheck = { CGPreflightPostEventAccess() },
        requestPostEventAccess: @escaping PermissionRequest = { CGRequestPostEventAccess() },
        postCopy: @escaping CopyEvent = { SelectionCaptureService.postCommandC() },
        waitAttempts: Int = 30,
        waitInterval: Duration = .milliseconds(25),
        backupBudget: PasteboardBackupBudget = .standard
    ) {
        self.pasteboard = pasteboard
        self.canPostEvents = canPostEvents
        self.requestPostEventAccess = requestPostEventAccess
        self.postCopy = postCopy
        self.waitAttempts = waitAttempts
        self.waitInterval = waitInterval
        self.backupBudget = backupBudget
    }

    func readSelection() async throws -> CapturedContent {
        guard canPostEvents() else {
            if !hasRequestedPermission {
                hasRequestedPermission = true
                _ = requestPostEventAccess()
            }
            throw SelectionCaptureError.postEventPermissionRequired
        }

        let original = PasteboardBackup(pasteboard: pasteboard, budget: backupBudget)
        guard original.isComplete else {
            throw SelectionCaptureError.clipboardCouldNotBePreserved
        }

        let previousChangeCount = pasteboard.changeCount
        postCopy()
        guard let selectionChangeCount = await waitForPasteboardChange(after: previousChangeCount) else {
            throw SelectionCaptureError.noSelection
        }

        defer {
            original.restore(to: pasteboard, ifChangeCountIs: selectionChangeCount)
        }
        return try PasteboardCaptureReader.read(from: pasteboard)
    }

    private func waitForPasteboardChange(after changeCount: Int) async -> Int? {
        for attempt in 0...waitAttempts {
            let current = pasteboard.changeCount
            if current != changeCount { return current }
            guard attempt < waitAttempts else { break }
            try? await Task.sleep(for: waitInterval)
        }
        return nil
    }

    private static func postCommandC() {
        guard
            let source = CGEventSource(stateID: .hidSystemState),
            let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_C),
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_C),
                keyDown: false
            )
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

@MainActor
struct PasteboardBackup {
    let items: [[NSPasteboard.PasteboardType: Data]]
    let isComplete: Bool

    init(pasteboard: NSPasteboard, budget: PasteboardBackupBudget = .standard) {
        let sourceItems = pasteboard.pasteboardItems ?? []
        var copiedItems: [[NSPasteboard.PasteboardType: Data]] = []
        var copiedEveryType = true
        var aggregateBytes = 0

        guard sourceItems.count <= budget.maximumItems,
              budget.maximumItems >= 0,
              budget.maximumTypesPerItem >= 0,
              budget.maximumBytesPerType >= 0,
              budget.maximumBytesPerItem >= 0,
              budget.maximumAggregateBytes >= 0 else {
            items = []
            isComplete = false
            return
        }

        itemLoop: for sourceItem in sourceItems {
            guard sourceItem.types.count <= budget.maximumTypesPerItem else {
                copiedEveryType = false
                break
            }
            var copiedTypes: [NSPasteboard.PasteboardType: Data] = [:]
            var itemBytes = 0
            for type in sourceItem.types {
                guard let data = sourceItem.data(forType: type),
                      data.count <= budget.maximumBytesPerType else {
                    copiedEveryType = false
                    break itemLoop
                }
                let (nextItemBytes, itemOverflow) = itemBytes.addingReportingOverflow(data.count)
                let (nextAggregateBytes, aggregateOverflow) = aggregateBytes.addingReportingOverflow(data.count)
                guard !itemOverflow,
                      !aggregateOverflow,
                      nextItemBytes <= budget.maximumBytesPerItem,
                      nextAggregateBytes <= budget.maximumAggregateBytes else {
                    copiedEveryType = false
                    break itemLoop
                }
                itemBytes = nextItemBytes
                aggregateBytes = nextAggregateBytes
                copiedTypes[type] = data
            }
            copiedItems.append(copiedTypes)
        }

        items = copiedEveryType ? copiedItems : []
        isComplete = copiedEveryType
    }

    func restore(to pasteboard: NSPasteboard, ifChangeCountIs expectedChangeCount: Int) {
        guard pasteboard.changeCount == expectedChangeCount else { return }
        let restoredItems = items.map { copiedTypes in
            let item = NSPasteboardItem()
            for (type, data) in copiedTypes {
                item.setData(data, forType: type)
            }
            return item
        }

        pasteboard.clearContents()
        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
    }
}
#endif
