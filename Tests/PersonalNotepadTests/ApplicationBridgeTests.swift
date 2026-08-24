import AppKit
import XCTest
@testable import PersonalNotepad

@MainActor
final class ApplicationBridgeTests: XCTestCase {
    func testColdLaunchServiceSelectionQueuesUntilStateHandlerIsReady() {
        var received: [(CapturedContent, CaptureDestination)] = []
        ApplicationBridge.shared.submitCapture(.text("Cold-launch selection"), destination: .vault)
        XCTAssertTrue(received.isEmpty)

        ApplicationBridge.shared.configureCapture { received.append(($0, $1)) }
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received[0].0, .text("Cold-launch selection"))
        if case .vault = received[0].1 {} else { XCTFail("Expected queued Vault destination") }
    }

    func testGlobalActionCanOnlyBeClaimedOnceAcrossScenes() {
        let notification = Notification(name: .saveClipboard, object: GlobalActionEvent())
        XCTAssertTrue(GlobalActionBus.claim(notification))
        XCTAssertFalse(GlobalActionBus.claim(notification))
    }

    func testMainNoteRequestsQueueUntilTheMainWindowCanConsumeThem() {
        XCTAssertTrue(GlobalActionBus.takeMainNoteRequests().isEmpty)
        GlobalActionBus.requestMainNote(.contextual)
        GlobalActionBus.requestMainNote(.vault)
        XCTAssertEqual(GlobalActionBus.takeMainNoteRequests(), [.contextual, .vault])
        XCTAssertTrue(GlobalActionBus.takeMainNoteRequests().isEmpty)
    }

    func testServiceProviderExposesBothObjectiveCEntryPoints() {
        let provider = NotepadServiceProvider()
        XCTAssertTrue(provider.responds(to: NSSelectorFromString("addToClasp:userData:error:")))
        XCTAssertTrue(provider.responds(to: NSSelectorFromString("addToClaspVault:userData:error:")))
    }

    func testQuickCaptureHasPrimaryAndConflictFallbackShortcuts() {
        let quickCapture = GlobalHotKeyManager.definitions.filter {
            $0.action.notification == .openQuickCapture
        }
        XCTAssertEqual(
            Set(quickCapture.map(\.displayName)),
            ["Option-Space", "Control-Option-Command-Space"]
        )
        XCTAssertEqual(Set(GlobalHotKeyManager.definitions.map(\.action)).count, GlobalHotKeyManager.definitions.count)
    }

    func testClipboardHotKeysRemainAvailableWithoutAccessibility() {
        let clipboardShortcuts = GlobalHotKeyManager.definitions.filter {
            $0.action.notification == .saveClipboard || $0.action.notification == .saveClipboardToVault
        }
        XCTAssertEqual(
            Set(clipboardShortcuts.map(\.displayName)),
            ["Control-Option-Command-C", "Control-Option-Command-V"]
        )

        let selectionShortcuts = GlobalHotKeyManager.definitions.filter {
            $0.action.notification == .captureSelectionToInbox
                || $0.action.notification == .captureSelectionToVault
        }
        if DistributionCapabilities.supportsAccessibilitySelectionCapture {
            XCTAssertEqual(
                Set(selectionShortcuts.map(\.displayName)),
                ["Control-Option-Shift-N", "Control-Option-Shift-P"]
            )
        } else {
            XCTAssertTrue(selectionShortcuts.isEmpty)
        }

        let serviceDefaults = Set(MacOSCaptureServiceDescriptor.all.map(\.defaultShortcut))
        XCTAssertTrue(Set(clipboardShortcuts.map(\.shortcut.symbolDisplayName)).isDisjoint(with: serviceDefaults))
        XCTAssertTrue(Set(selectionShortcuts.map(\.shortcut.symbolDisplayName)).isDisjoint(with: serviceDefaults))
    }

    func testKeyboardSettingsSetupLinkTargetsTheKeyboardPane() {
        XCTAssertEqual(KeyboardSettingsOpener.keyboardSettingsURL.scheme, "x-apple.systempreferences")
        XCTAssertTrue(KeyboardSettingsOpener.keyboardSettingsURL.absoluteString.contains("Keyboard-Settings"))
        XCTAssertEqual(KeyboardSettingsOpener.accessibilitySettingsURL.scheme, "x-apple.systempreferences")
        XCTAssertTrue(
            KeyboardSettingsOpener.accessibilitySettingsURL.absoluteString.contains("Privacy_Accessibility")
        )
    }

    func testAuthenticationFocusChangeDoesNotTriggerVaultLock() {
        let coordinator = VaultLockCoordinator()
        var lockCount = 0
        coordinator.lockHandler = { lockCount += 1 }
        coordinator.start()

        NotificationCenter.default.post(name: NSApplication.willResignActiveNotification, object: nil)

        XCTAssertEqual(lockCount, 0)
    }

    func testDockMenuExposesMemorableQuickActions() {
        let menu = AppDelegate().applicationDockMenu(NSApplication.shared)
        let titles = menu?.items.filter { !$0.isSeparatorItem }.map(\.title)

        XCTAssertEqual(
            titles,
            ["Quick Capture", "Add Clipboard to Clasp", "Add Clipboard to Vault", "Open Clasp", "Lock Vault"]
        )
        XCTAssertNotNil(menu?.items.first(where: { $0.title == "Add Clipboard to Vault" })?.image)
    }

    func testCoreProductSymbolsAreAvailable() {
        for symbol in Set(AppIcon.allSystemNames) {
            XCTAssertNotNil(
                NSImage(systemSymbolName: symbol, accessibilityDescription: symbol),
                "Missing SF Symbol: \(symbol)"
            )
        }
    }

    func testVaultNotesUseADistinctStateSymbol() {
        XCTAssertNotEqual(AppIcon.Vault.noteBadge, AppIcon.Content.note)
        XCTAssertNotEqual(AppIcon.Vault.secureDocument, AppIcon.Content.note)
        XCTAssertEqual(AppIcon.Vault.noteBadge, "shield.fill")
        XCTAssertEqual(AppIcon.Vault.secureDocument, "lock.doc.fill")
    }
}
