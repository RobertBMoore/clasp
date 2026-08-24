import AppKit
import Foundation
import XCTest
@testable import PersonalNotepad

@MainActor
final class ClipboardAndPreferencesTests: XCTestCase {
    func testDelayedClearOnlyClearsOriginalValue() async {
        let original = ClipboardSnapshot(value: "captured", changeCount: 4)
        let client = FakeClipboardClient(snapshot: original)
        let service = ClipboardService(client: client)
        service.scheduleSafeClear(of: original, after: .zero)
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(client.clearCount, 1)

        client.snapshot = original
        service.scheduleSafeClear(of: original, after: .milliseconds(20))
        client.snapshot = ClipboardSnapshot(value: "newer", changeCount: 5)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(client.clearCount, 1)
    }

    func testOnboardingPreferencePersistsAndResets() {
        let suite = "PersonalNotepadTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = OnboardingPreferences(defaults: defaults)
        XCTAssertFalse(preferences.isComplete)
        preferences.markComplete()
        XCTAssertTrue(OnboardingPreferences(defaults: defaults).isComplete)
        preferences.reset()
        XCTAssertFalse(preferences.isComplete)
    }

    func testAppearanceDefaultsToSystemAndMapsEveryOption() {
        XCTAssertEqual(AppAppearance(rawValue: "missing") ?? .system, .system)
        XCTAssertEqual(AppAppearance.allCases.map(\.title), ["System", "Light", "Dark"])
    }

    func testApplicationAppearanceControllerUsesOneNativeAppearanceForEveryTheme() throws {
        let suite = "PersonalNotepadTests.Appearance.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let application = FakeApplicationAppearance()

        XCTAssertNil(AppAppearanceController.appearanceName(for: .system))
        XCTAssertEqual(AppAppearanceController.appearanceName(for: .light), .aqua)
        XCTAssertEqual(AppAppearanceController.appearanceName(for: .dark), .darkAqua)

        defaults.set(AppAppearance.dark.rawValue, forKey: PreferenceKeys.appAppearance)
        AppAppearanceController.applyStoredPreference(defaults: defaults, to: application)
        XCTAssertEqual(application.appearance?.name, .darkAqua)

        defaults.set(AppAppearance.light.rawValue, forKey: PreferenceKeys.appAppearance)
        AppAppearanceController.applyStoredPreference(defaults: defaults, to: application)
        XCTAssertEqual(application.appearance?.name, .aqua)

        defaults.set("invalid", forKey: PreferenceKeys.appAppearance)
        AppAppearanceController.applyStoredPreference(defaults: defaults, to: application)
        XCTAssertNil(application.appearance, "Invalid preferences must fail safely to System")
    }

    func testVisualOnboardingCoversEveryCoreWorkflowAndClipboardBoundary() {
        XCTAssertEqual(
            OnboardingStep.allCases.map(\.shortTitle),
            ["Welcome", "Quick Capture", "Clipboard", "Right-Click", "Organize", "Vault", "Back Up"]
        )
        XCTAssertTrue(OnboardingStep.clipboard.message.contains("text, Markdown, a link, or an image"))
        XCTAssertTrue(OnboardingStep.clipboard.tip.contains("never watches the clipboard"))
        if DistributionCapabilities.supportsAccessibilitySelectionCapture {
            XCTAssertTrue(OnboardingStep.selection.message.contains("Control–Option–Shift–N"))
            XCTAssertTrue(OnboardingStep.selection.message.contains("Control–Option–Shift–P"))
        } else {
            XCTAssertFalse(OnboardingStep.selection.message.contains("Control–Option"))
            XCTAssertTrue(OnboardingStep.selection.message.contains("Services menu"))
        }
        XCTAssertTrue(OnboardingStep.selection.message.contains("source app’s Services menu"))
        XCTAssertEqual(
            OnboardingStep.vault.message.contains("Control–Option–Shift–P"),
            DistributionCapabilities.supportsAccessibilitySelectionCapture
        )
        XCTAssertTrue(OnboardingStep.vault.tip.contains("never anything copied afterward"))
    }

    func testPasteboardReaderAcceptsAndNormalizesImageContent() throws {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 3,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let png = bitmap.representation(using: .png, properties: [:]) else {
            return XCTFail("Could not create test image")
        }
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClaspTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)

        guard case .image(let image) = try PasteboardCaptureReader.read(from: pasteboard) else {
            return XCTFail("Expected image capture")
        }
        XCTAssertEqual(image.pixelWidth, 2)
        XCTAssertEqual(image.pixelHeight, 3)
        XCTAssertFalse(image.pngData.isEmpty)
    }

    func testPasteboardReaderAcceptsALinkWithoutPlainTextFallback() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClaspTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("https://example.com/clasp", forType: .URL)

        XCTAssertEqual(
            try PasteboardCaptureReader.read(from: pasteboard),
            .text("https://example.com/clasp")
        )
    }

    func testPasteboardReaderRejectsPlainTextOverCharacterOrUTF8Budgets() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClaspTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString(
            String(repeating: "a", count: PasteboardCaptureReader.maximumTextCharacters + 1),
            forType: .string
        )
        XCTAssertThrowsError(try PasteboardCaptureReader.read(from: pasteboard))

        let multiScalarCharacter = "👨‍👩‍👧‍👦"
        let repetitions = PasteboardCaptureReader.maximumTextUTF8Bytes / multiScalarCharacter.utf8.count + 1
        pasteboard.clearContents()
        pasteboard.setString(String(repeating: multiScalarCharacter, count: repetitions), forType: .URL)
        XCTAssertThrowsError(try PasteboardCaptureReader.read(from: pasteboard))
    }

    func testPasteboardReaderCapsFileURLAtMaximumPlusOneWithoutFileSizeMetadata() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaspPasteboard-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data([0, 1, 2, 3, 4]).write(to: fileURL)

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClaspTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([fileURL as NSURL]))

        XCTAssertThrowsError(
            try PasteboardCaptureReader.read(from: pasteboard, imageByteLimit: 4)
        ) { error in
            XCTAssertEqual(error as? PasteboardCaptureError, .imageTooLarge)
        }
    }
}

@MainActor
private final class FakeClipboardClient: ClipboardClient {
    var snapshot: ClipboardSnapshot?
    var clearCount = 0
    init(snapshot: ClipboardSnapshot?) { self.snapshot = snapshot }
    func readContent() -> ClipboardSnapshot? { snapshot }
    func currentSnapshot() -> ClipboardSnapshot? { snapshot }
    func clear() { clearCount += 1; snapshot = nil }
}

@MainActor
private final class FakeApplicationAppearance: AppAppearanceApplying {
    var appearance: NSAppearance?
}
