import AppKit
import Foundation

@MainActor
final class ApplicationBridge {
    static let shared = ApplicationBridge()
    private var capture: ((CapturedContent, CaptureDestination) -> Void)?
    private var pendingCaptures: [(CapturedContent, CaptureDestination)] = []
    private init() {}

    func configureCapture(_ handler: @escaping (CapturedContent, CaptureDestination) -> Void) {
        capture = handler
        let pending = pendingCaptures
        pendingCaptures.removeAll(keepingCapacity: false)
        pending.forEach { handler($0.0, $0.1) }
    }

    func submitCapture(_ content: CapturedContent, destination: CaptureDestination) {
        if let capture { capture(content, destination) }
        else { pendingCaptures.append((content, destination)) }
    }
}

@MainActor
final class NotepadServiceProvider: NSObject {
    typealias CaptureSubmission = @MainActor (CapturedContent, CaptureDestination) -> Void
    typealias CaptureReader = @MainActor (NSPasteboard) throws -> CapturedContent

    private let captureSubmission: CaptureSubmission
    private let captureReader: CaptureReader

    override convenience init() {
        self.init(
            captureReader: { try PasteboardCaptureReader.read(from: $0) },
            captureSubmission: { content, destination in
                ApplicationBridge.shared.submitCapture(content, destination: destination)
            }
        )
    }

    init(
        captureReader: @escaping CaptureReader = { try PasteboardCaptureReader.read(from: $0) },
        captureSubmission: @escaping CaptureSubmission
    ) {
        self.captureReader = captureReader
        self.captureSubmission = captureSubmission
        super.init()
    }

    @objc func addToClasp(_ pasteboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        submit(pasteboard, to: .inbox, error: error)
    }

    @objc func addToClaspVault(_ pasteboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        submit(pasteboard, to: .vault, error: error)
    }

    @objc func saveSelection(_ pasteboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        submit(pasteboard, to: .inbox, error: error)
    }

    private func submit(
        _ pasteboard: NSPasteboard,
        to destination: CaptureDestination,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        do {
            let content = try captureReader(pasteboard)
            captureSubmission(content, destination)
        } catch let captureError as LocalizedError {
            errorPointer.pointee = (captureError.errorDescription ?? "Clasp could not read that content.") as NSString
        } catch {
            errorPointer.pointee = "Clasp could not read that content."
        }
    }
}
