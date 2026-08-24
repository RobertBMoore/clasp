import Foundation
import XCTest

final class UICompletionSourceContractTests: XCTestCase {
    func testIndependentScenesUseSharedAppStateErrorAlert() throws {
        for path in [
            "Sources/PersonalNotepad/Views/Main/MainRootView.swift",
            "Sources/PersonalNotepad/Views/Capture/QuickCaptureView.swift",
            "Sources/PersonalNotepad/Views/Onboarding/OnboardingView.swift",
            "Sources/PersonalNotepad/Views/Help/HelpView.swift",
            "Sources/PersonalNotepad/App/MenuBarContent.swift"
        ] {
            XCTAssertTrue(try source(at: path).contains(".appStateErrorAlert(appState)"), path)
        }
    }

    func testCaptureSurfacesGateRepeatedActivation() throws {
        for path in [
            "Sources/PersonalNotepad/Views/Capture/QuickCaptureView.swift",
            "Sources/PersonalNotepad/Views/Onboarding/OnboardingView.swift",
            "Sources/PersonalNotepad/App/MenuBarContent.swift"
        ] {
            let source = try source(at: path)
            XCTAssertTrue(source.contains("capturingClipboard"), path)
            XCTAssertTrue(source.contains("!capturingClipboard else"), path)
            XCTAssertTrue(source.contains(".disabled("), path)
        }
    }

    func testAdaptiveCaptureAndOnboardingContractsRemainPresent() throws {
        let quickCapture = try source(at: "Sources/PersonalNotepad/Views/Capture/QuickCaptureView.swift")
        XCTAssertTrue(quickCapture.contains("ViewThatFits(in: .horizontal)"))
        XCTAssertTrue(quickCapture.contains(".frame(minWidth:"))

        let onboarding = try source(at: "Sources/PersonalNotepad/Views/Onboarding/OnboardingView.swift")
        XCTAssertTrue(onboarding.contains("ScrollView {"))
        XCTAssertTrue(onboarding.contains(".frame(minWidth:"))
    }

    func testCaptureMenuIncludesExplicitClipboardClearing() throws {
        let app = try source(at: "Sources/PersonalNotepad/App/PersonalNotepadApp.swift")
        let receiver = try source(at: "Sources/PersonalNotepad/App/GlobalActionReceiver.swift")
        XCTAssertTrue(app.contains("Label(\"Clear Clipboard\""))
        XCTAssertTrue(app.contains("GlobalActionBus.post(.clearClipboard)"))
        XCTAssertTrue(receiver.contains("publisher(for: .clearClipboard)"))
    }

    func testHelpCanExposeTheSignedBuildPrivacyPolicyURL() throws {
        let help = try source(at: "Sources/PersonalNotepad/Views/Help/HelpView.swift")
        XCTAssertTrue(help.contains("ClaspPrivacyPolicyURL"))
        XCTAssertTrue(help.contains("Link(\"Read Clasp’s Privacy Policy\""))
        XCTAssertTrue(help.contains("url.scheme?.lowercased() == \"https\""))
    }

    func testQuickCaptureShowsForegroundCompletionStatus() throws {
        let quickCapture = try source(at: "Sources/PersonalNotepad/Views/Capture/QuickCaptureView.swift")
        XCTAssertTrue(quickCapture.contains("if let status = appState.statusMessage"))
        XCTAssertTrue(quickCapture.contains(".accessibilityLabel(\"Status: \\(status)\")"))
    }

    func testVaultBackupGuardsOneTimeKeysAndInFlightWindowDismissal() throws {
        let backup = try source(at: "Sources/PersonalNotepad/Views/Help/VaultBackupView.swift")
        XCTAssertTrue(backup.contains("hasUnstoredRecoveryKey: recoveryKey != nil"))
        XCTAssertTrue(backup.contains("guard operationState.canStartOperation else"))
        XCTAssertTrue(backup.contains(".interactiveDismissDisabled(operationState.blocksDismissal)"))
        XCTAssertTrue(backup.contains("VaultBackupWindowDismissalGuard(isDisabled: operationState.blocksDismissal)"))
        XCTAssertTrue(backup.contains("VaultRecoveryKeyCustody.shared.markUnstored()"))
        XCTAssertTrue(backup.contains("beginProtectedOperation()"))
        XCTAssertTrue(backup.contains("VaultRecoveryKeyCustody.shared.endOperation()"))
        XCTAssertTrue(backup.contains("standardWindowButton(.closeButton)?.isEnabled = false"))
        XCTAssertTrue(backup.contains("importKey = \"\""))
        XCTAssertTrue(backup.contains("importError = nil"))

        let app = try source(at: "Sources/PersonalNotepad/App/PersonalNotepadApp.swift")
        XCTAssertTrue(app.contains("let backupCustody = VaultRecoveryKeyCustody.shared"))
        XCTAssertTrue(app.contains("backupCustody.hasUnstoredRecoveryKey"))
        XCTAssertTrue(app.contains("backupCustody.isBackupOperationInProgress"))
        XCTAssertTrue(app.contains("Vault Backup in Progress"))
        XCTAssertTrue(app.contains("Store Your Vault Recovery Key"))
        XCTAssertTrue(app.contains("guard !terminationIsFinishing else { return .terminateLater }"))
    }

    func testNewNoteCommandsOpenAndRouteThroughTheSingleMainWindow() throws {
        let app = try source(at: "Sources/PersonalNotepad/App/PersonalNotepadApp.swift")
        let root = try source(at: "Sources/PersonalNotepad/Views/Main/MainRootView.swift")
        let bus = try source(at: "Sources/PersonalNotepad/Services/GlobalActionBus.swift")

        XCTAssertTrue(app.contains("Window(\"Clasp\", id: \"main\")"))
        XCTAssertTrue(app.contains("@Environment(\\.openWindow) private var openWindow"))
        XCTAssertTrue(app.contains("GlobalActionBus.requestMainNote(request)"))
        XCTAssertTrue(app.contains("openWindow(id: \"main\")"))
        XCTAssertTrue(root.contains(".onAppear { fulfillPendingMainNoteRequests() }"))
        XCTAssertTrue(root.contains("publisher(for: .mainNoteRequested)"))
        XCTAssertTrue(bus.contains("pendingMainNoteRequests.append(request)"))
        XCTAssertTrue(bus.contains("static func takeMainNoteRequests()"))
    }

    func testHelpUsesTheDistributionAwareApplicationSupportPath() throws {
        let help = try source(at: "Sources/PersonalNotepad/Views/Help/HelpView.swift")
        XCTAssertTrue(help.contains("AppPaths.applicationSupportDirectory.path(percentEncoded: false)"))
        XCTAssertTrue(help.contains(".abbreviatingWithTildeInPath"))
        XCTAssertTrue(help.contains("DistributionCapabilities.isAppStoreBuild"))
        XCTAssertFalse(help.contains("~/Library/Application Support/Personal Notepad"))
    }

    func testPanelGrantedSecurityScopeIsBalancedAtTheAsyncOperationBoundary() throws {
        let panel = try source(at: "Sources/PersonalNotepad/Services/FilePanelService.swift")
        XCTAssertFalse(panel.contains("startAccessingSecurityScopedResource"))
        XCTAssertTrue(panel.contains("url.stopAccessingSecurityScopedResource()"))
        XCTAssertTrue(panel.contains("DistributionCapabilities.isAppStoreBuild"))

        let backup = try source(at: "Sources/PersonalNotepad/Views/Help/VaultBackupView.swift")
        XCTAssertEqual(
            backup.components(separatedBy: "FilePanelService.releaseAccess(to: url)").count - 1,
            2,
            "Export and import must each release their panel-granted URL exactly once"
        )
        XCTAssertTrue(backup.contains("defer {\n                    isExporting = false"))
        XCTAssertTrue(backup.contains("pendingImportURL = nil\n        FilePanelService.releaseAccess(to: url)"))
    }

    func testVaultNoteAccessibilitySummaryInterpolatesItsContentType() throws {
        let noteList = try source(at: "Sources/PersonalNotepad/Views/Main/NoteListView.swift")
        XCTAssertTrue(noteList.contains("Encrypted Vault \\(note.contentType.title.lowercased())"))
        XCTAssertFalse(noteList.contains("Encrypted Vault (note.contentType.title.lowercased())"))
    }

    private func source(at relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
