import Foundation

struct GlobalActionEvent: Sendable {
    let id = UUID()
}

enum MainNoteRequest: Sendable, Equatable {
    case contextual
    case vault
}

@MainActor
enum GlobalActionBus {
    private static var claimedIDs: [UUID] = []
    private static var pendingMainNoteRequests: [MainNoteRequest] = []

    static func post(_ name: Notification.Name, userInfo: [AnyHashable: Any]? = nil) {
        NotificationCenter.default.post(name: name, object: GlobalActionEvent(), userInfo: userInfo)
    }

    static func claim(_ notification: Notification) -> Bool {
        guard let event = notification.object as? GlobalActionEvent else { return true }
        guard !claimedIDs.contains(event.id) else { return false }
        claimedIDs.append(event.id)
        if claimedIDs.count > 64 { claimedIDs.removeFirst(claimedIDs.count - 64) }
        return true
    }

    /// Queue note creation before opening the single main window. An existing
    /// window receives the notification immediately; a newly created window
    /// consumes the same queue from `onAppear`, so Command-N cannot disappear
    /// while every Clasp window is closed.
    static func requestMainNote(_ request: MainNoteRequest) {
        pendingMainNoteRequests.append(request)
        post(.mainNoteRequested)
    }

    static func takeMainNoteRequests() -> [MainNoteRequest] {
        defer { pendingMainNoteRequests.removeAll(keepingCapacity: true) }
        return pendingMainNoteRequests
    }
}
