import AppKit
import Foundation

struct ClipboardSnapshot: Equatable, Sendable {
    var content: CapturedContent
    var changeCount: Int

    init(content: CapturedContent, changeCount: Int) {
        self.content = content
        self.changeCount = changeCount
    }

    init(value: String, changeCount: Int) {
        self.init(content: .text(value), changeCount: changeCount)
    }
}

@MainActor
protocol ClipboardClient: AnyObject {
    func readContent() -> ClipboardSnapshot?
    func currentSnapshot() -> ClipboardSnapshot?
    func clear()
}

@MainActor
final class SystemClipboardClient: ClipboardClient {
    private let pasteboard = NSPasteboard.general

    func readContent() -> ClipboardSnapshot? {
        guard let content = try? PasteboardCaptureReader.read(from: pasteboard) else { return nil }
        return ClipboardSnapshot(content: content, changeCount: pasteboard.changeCount)
    }

    func currentSnapshot() -> ClipboardSnapshot? {
        guard let content = try? PasteboardCaptureReader.read(from: pasteboard) else { return nil }
        return ClipboardSnapshot(content: content, changeCount: pasteboard.changeCount)
    }

    func clear() {
        pasteboard.clearContents()
    }
}

enum ClipboardClearDelay: String, CaseIterable, Identifiable, Sendable {
    case immediately
    case fifteenSeconds
    case thirtySeconds
    case sixtySeconds
    case never

    var id: String { rawValue }
    var title: String {
        switch self {
        case .immediately: "Immediately"
        case .fifteenSeconds: "15 seconds"
        case .thirtySeconds: "30 seconds"
        case .sixtySeconds: "60 seconds"
        case .never: "Never"
        }
    }
    var duration: Duration? {
        switch self {
        case .immediately: .zero
        case .fifteenSeconds: .seconds(15)
        case .thirtySeconds: .seconds(30)
        case .sixtySeconds: .seconds(60)
        case .never: nil
        }
    }
}

@MainActor
final class ClipboardService {
    private let client: any ClipboardClient
    private var clearTask: Task<Void, Never>?

    init(client: any ClipboardClient = SystemClipboardClient()) {
        self.client = client
    }

    func readContent() -> ClipboardSnapshot? { client.readContent() }
    func clearNow() { client.clear() }

    func scheduleSafeClear(of snapshot: ClipboardSnapshot, after delay: Duration?) {
        clearTask?.cancel()
        guard let delay else { return }
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            if Self.shouldClear(captured: snapshot, current: self.client.currentSnapshot()) {
                self.client.clear()
            }
        }
    }

    static func shouldClear(captured: ClipboardSnapshot, current: ClipboardSnapshot?) -> Bool {
        current == captured
    }
}
