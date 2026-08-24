import AppKit
import Carbon
import XCTest
@testable import PersonalNotepad

@MainActor
final class CaptureShortcutPreferencesTests: XCTestCase {
    func testCatalogSeparatesAllBuildClipboardCaptureFromDirectSelectionCapture() {
        let actions = Set(GlobalHotKeyManager.definitions.map(\.action))
        XCTAssertTrue(actions.contains(.saveClipboardToInbox))
        XCTAssertTrue(actions.contains(.saveClipboardToVault))

        let selectionActions: Set<GlobalHotKeyAction> = [
            .captureSelectionToInbox,
            .captureSelectionToVault
        ]
        if DistributionCapabilities.supportsAccessibilitySelectionCapture {
            XCTAssertTrue(selectionActions.isSubset(of: actions))
        } else {
            XCTAssertTrue(selectionActions.isDisjoint(with: actions))
        }

        for action in [
            GlobalHotKeyAction.captureSelectionToInbox,
            .captureSelectionToVault,
            .saveClipboardToInbox,
            .saveClipboardToVault
        ] {
            XCTAssertEqual(Set(action.contentKinds), Set(CaptureShortcutContentKind.allCases))
        }
        XCTAssertEqual(GlobalHotKeyAction.saveClipboardToInbox.inputSource, .clipboard)
        XCTAssertEqual(GlobalHotKeyAction.saveClipboardToVault.inputSource, .clipboard)
        XCTAssertEqual(GlobalHotKeyAction.captureSelectionToInbox.inputSource, .selectedContent)
        XCTAssertEqual(GlobalHotKeyAction.captureSelectionToVault.inputSource, .selectedContent)
    }

    func testDefaultGlobalShortcutsAreUniqueAndDoNotCollideWithServices() {
        let global = GlobalHotKeyManager.defaultDefinitions.map(\.shortcut)
        XCTAssertEqual(Set(global).count, global.count)

        let serviceDefaults = Set(MacOSCaptureServiceDescriptor.all.map(\.defaultShortcut))
        XCTAssertTrue(Set(global.map(\.symbolDisplayName)).isDisjoint(with: serviceDefaults))
        XCTAssertEqual(serviceDefaults, ["⌃⌥N", "⌃⌥P"])
    }

    func testReplacePersistsNormalizesAndResetsToTheShippingDefault() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = GlobalHotKeyPreferences(defaults: defaults)
        let replacement = GlobalHotKeyShortcut(
            keyCode: UInt32(kVK_ANSI_B),
            modifiers: UInt32(controlKey | cmdKey),
            keyLabel: "b"
        )

        try preferences.replace(replacement, for: .saveClipboardToInbox)
        XCTAssertEqual(preferences.shortcut(for: .saveClipboardToInbox)?.keyLabel, "B")
        XCTAssertEqual(preferences.shortcut(for: .saveClipboardToInbox)?.symbolDisplayName, "⌃⌘B")
        XCTAssertTrue(
            preferences.assignments.first(where: { $0.action == .saveClipboardToInbox })?.isCustomized == true
        )

        let reloaded = GlobalHotKeyPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.shortcut(for: .saveClipboardToInbox)?.symbolDisplayName, "⌃⌘B")

        reloaded.reset(.saveClipboardToInbox)
        XCTAssertEqual(
            reloaded.shortcut(for: .saveClipboardToInbox),
            GlobalHotKeyManager.defaultDefinitions
                .first(where: { $0.action == .saveClipboardToInbox })?
                .shortcut
        )
    }

    func testClearPersistsAndResetAllRestoresEveryAvailableAction() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = GlobalHotKeyPreferences(defaults: defaults)

        preferences.clear(.saveClipboardToVault)
        XCTAssertNil(preferences.shortcut(for: .saveClipboardToVault))
        XCTAssertEqual(preferences.registrationState(for: .saveClipboardToVault), .disabled)
        XCTAssertNil(GlobalHotKeyPreferences(defaults: defaults).shortcut(for: .saveClipboardToVault))

        try preferences.replace(
            GlobalHotKeyShortcut(
                keyCode: UInt32(kVK_ANSI_B),
                modifiers: UInt32(optionKey | cmdKey),
                keyLabel: "B"
            ),
            for: .saveClipboardToInbox
        )
        preferences.resetAll()

        XCTAssertEqual(
            preferences.definitions,
            GlobalHotKeyManager.definitions
        )
        XCTAssertTrue(preferences.assignments.allSatisfy { !$0.isCustomized && $0.isEnabled })
    }

    func testShortcutPresentationValuesFollowReplacementAndClear() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = GlobalHotKeyPreferences(defaults: defaults)
        let replacement = GlobalHotKeyShortcut(
            keyCode: UInt32(kVK_ANSI_B),
            modifiers: UInt32(controlKey | shiftKey | cmdKey),
            keyLabel: "b"
        )

        try preferences.replace(replacement, for: .quickCapturePrimary)

        let effective = try XCTUnwrap(preferences.shortcut(for: .quickCapturePrimary))
        XCTAssertEqual(effective.displayName, "Control-Shift-Command-B")
        XCTAssertEqual(effective.symbolDisplayName, "⌃⇧⌘B")
        XCTAssertEqual(effective.keycapLabels, ["⌃", "⇧", "⌘", "B"])

        preferences.clear(.quickCapturePrimary)

        XCTAssertNil(preferences.shortcut(for: .quickCapturePrimary))
        XCTAssertFalse(
            preferences.assignments
                .first(where: { $0.action == .quickCapturePrimary })?
                .isEnabled ?? true
        )
    }

    func testClearingShortcutImmediatelyRemovesItsGlobalRegistration() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = GlobalHotKeyPreferences(defaults: defaults)
        let manager = GlobalHotKeyManager(preferences: preferences) { _ in true }

        XCTAssertTrue(manager.register().registered.contains(.lockVault))

        preferences.clear(.lockVault)

        XCTAssertNil(manager.definition(for: .lockVault))
        XCTAssertFalse(manager.result.registered.contains(.lockVault))
        XCTAssertFalse(manager.result.failed.contains(.lockVault))
    }

    func testConflictAndUnsafeReplacementFailWithoutChangingTheExistingAssignment() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = GlobalHotKeyPreferences(defaults: defaults)
        let original = try XCTUnwrap(preferences.shortcut(for: .saveClipboardToVault))
        let clipboardInbox = try XCTUnwrap(preferences.shortcut(for: .saveClipboardToInbox))

        XCTAssertThrowsError(
            try preferences.replace(clipboardInbox, for: .saveClipboardToVault)
        ) { error in
            XCTAssertEqual(
                error as? GlobalHotKeyPreferenceError,
                .conflict(existingAction: .saveClipboardToInbox)
            )
        }
        XCTAssertEqual(preferences.shortcut(for: .saveClipboardToVault), original)

        XCTAssertThrowsError(
            try preferences.replace(
                GlobalHotKeyShortcut(
                    keyCode: UInt32(kVK_ANSI_V),
                    modifiers: 0,
                    keyLabel: "V"
                ),
                for: .saveClipboardToVault
            )
        ) { error in
            XCTAssertEqual(error as? GlobalHotKeyPreferenceError, .unsafeShortcut)
        }
        XCTAssertEqual(preferences.shortcut(for: .saveClipboardToVault), original)
    }

    func testMalformedPersistenceFailsSafelyToTheDefault() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(
            Data("not-json".utf8),
            forKey: GlobalHotKeyPreferences.storagePrefix + GlobalHotKeyAction.saveClipboardToInbox.storageID
        )
        let preferences = GlobalHotKeyPreferences(defaults: defaults)

        XCTAssertEqual(
            preferences.shortcut(for: .saveClipboardToInbox),
            GlobalHotKeyManager.defaultDefinitions
                .first(where: { $0.action == .saveClipboardToInbox })?
                .shortcut
        )
    }

    func testRegistrationFailureIsPublishedWithoutDroppingOtherShortcuts() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = GlobalHotKeyPreferences(defaults: defaults)
        let manager = GlobalHotKeyManager(preferences: preferences) { definition in
            !(definition.action == .saveClipboardToInbox && definition.shortcut.keyLabel == "B")
        }

        let initial = manager.register()
        XCTAssertTrue(initial.failed.isEmpty)

        try preferences.replace(
            GlobalHotKeyShortcut(
                keyCode: UInt32(kVK_ANSI_B),
                modifiers: UInt32(controlKey | optionKey | cmdKey),
                keyLabel: "B"
            ),
            for: .saveClipboardToInbox
        )

        XCTAssertEqual(manager.result.failed, [.saveClipboardToInbox])
        XCTAssertEqual(
            manager.result.registered,
            Set(preferences.definitions.map(\.action)).subtracting([.saveClipboardToInbox])
        )
        XCTAssertEqual(preferences.registrationState(for: .saveClipboardToInbox), .unavailable)
        XCTAssertTrue(
            preferences.definitions
                .filter { $0.action != .saveClipboardToInbox }
                .allSatisfy { preferences.registrationState(for: $0.action) == .registered }
        )
    }

    func testQuickCaptureFailureCopyUsesTheEffectiveShortcuts() {
        let primary = GlobalHotKeyDefinition(
            action: .quickCapturePrimary,
            shortcut: GlobalHotKeyShortcut(
                keyCode: UInt32(kVK_ANSI_B),
                modifiers: UInt32(controlKey | cmdKey),
                keyLabel: "B"
            )
        )
        let fallback = GlobalHotKeyDefinition(
            action: .quickCaptureFallback,
            shortcut: GlobalHotKeyShortcut(
                keyCode: UInt32(kVK_ANSI_Q),
                modifiers: UInt32(optionKey | cmdKey),
                keyLabel: "Q"
            )
        )
        let message = GlobalHotKeyMessageFormatter.quickCaptureFailureMessage(
            result: GlobalHotKeyRegistrationResult(
                registered: [.quickCaptureFallback],
                failed: [.quickCapturePrimary]
            ),
            definitions: [primary, fallback]
        )

        XCTAssertEqual(message, "Control-Command-B is already in use. Quick Capture: Option-Command-Q")
        XCTAssertFalse(message?.contains("Option-Space") == true)
    }

    func testSupportingShortcutFailureWarningIsCombinedPreferenceDerivedAndSafetyAware() throws {
        let inbox = GlobalHotKeyDefinition(
            action: .saveClipboardToInbox,
            shortcut: GlobalHotKeyShortcut(
                keyCode: UInt32(kVK_ANSI_B),
                modifiers: UInt32(controlKey | cmdKey),
                keyLabel: "B"
            )
        )
        let vault = GlobalHotKeyDefinition(
            action: .saveClipboardToVault,
            shortcut: GlobalHotKeyShortcut(
                keyCode: UInt32(kVK_ANSI_G),
                modifiers: UInt32(optionKey | cmdKey),
                keyLabel: "G"
            )
        )
        let lock = GlobalHotKeyDefinition(
            action: .lockVault,
            shortcut: GlobalHotKeyShortcut(
                keyCode: UInt32(kVK_ANSI_K),
                modifiers: UInt32(controlKey | optionKey),
                keyLabel: "K"
            )
        )

        let message = try XCTUnwrap(
            GlobalHotKeyMessageFormatter.supportingActionFailureMessage(
                result: GlobalHotKeyRegistrationResult(
                    registered: [.saveClipboardToVault],
                    failed: [.saveClipboardToInbox, .lockVault]
                ),
                definitions: [inbox, vault, lock]
            )
        )

        XCTAssertTrue(message.contains("Clipboard to Inbox (Control-Command-B)"))
        XCTAssertTrue(message.contains("Lock Vault (Control-Option-K)"))
        XCTAssertFalse(message.contains("Clipboard to Vault"))
        XCTAssertFalse(message.contains("Control-Option-Command-C"))
        XCTAssertTrue(message.contains("Clipboard capture remains available"))
        XCTAssertTrue(message.contains("Lock the Vault from either menu"))
        XCTAssertEqual(message.components(separatedBy: "Settings › Shortcuts & Capture").count - 1, 1)
    }

    func testSupportingShortcutFailureWarningIgnoresClearedAndWorkingActions() {
        let working = GlobalHotKeyDefinition(
            action: .saveClipboardToVault,
            shortcut: GlobalHotKeyShortcut(
                keyCode: UInt32(kVK_ANSI_G),
                modifiers: UInt32(optionKey | cmdKey),
                keyLabel: "G"
            )
        )

        XCTAssertNil(
            GlobalHotKeyMessageFormatter.supportingActionFailureMessage(
                result: GlobalHotKeyRegistrationResult(registered: [.saveClipboardToVault]),
                definitions: [working]
            )
        )
        XCTAssertNil(
            GlobalHotKeyMessageFormatter.supportingActionFailureMessage(
                result: GlobalHotKeyRegistrationResult(failed: [.saveClipboardToInbox, .lockVault]),
                definitions: []
            ),
            "Cleared shortcuts have no effective definition and must not trigger startup warnings"
        )
    }

    func testStartupSupportingShortcutWarningUsesOnlyEffectivePreferenceDefinitions() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let app = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/PersonalNotepad/App/PersonalNotepadApp.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(app.contains("reportSupportingShortcutFailuresIfNeeded(hotKeyResult)"))
        XCTAssertTrue(app.contains(".compactMap { hotKeys.definition(for: $0) }"))
        XCTAssertTrue(app.contains("supportingActionFailureMessage("))
        XCTAssertFalse(app.contains("Control-Option-Command-C"))
        XCTAssertFalse(app.contains("Control-Option-Command-V"))
        XCTAssertFalse(app.contains("Control-Option-Command-L"))
    }

    func testServiceProviderRoutesNormalTextAndSecureImageToTheRequestedDestination() throws {
        var captures: [(CapturedContent, CaptureDestination)] = []
        let image = CapturedImage(
            pngData: Data("image fixture".utf8),
            pixelWidth: 1,
            pixelHeight: 1
        )
        var suppliedContent: [CapturedContent] = [
            .text("# Markdown heading"),
            .image(image)
        ]
        let provider = NotepadServiceProvider(
            captureReader: { _ in suppliedContent.removeFirst() },
            captureSubmission: { captures.append(($0, $1)) }
        )
        let pasteboard = NSPasteboard.general
        var serviceError: NSString?

        provider.addToClasp(pasteboard, userData: "", error: &serviceError)
        XCTAssertNil(serviceError)
        XCTAssertEqual(captures.first?.0, .text("# Markdown heading"))
        assertDestination(captures.first?.1, is: .inbox)

        serviceError = nil
        provider.addToClaspVault(pasteboard, userData: "", error: &serviceError)

        XCTAssertNil(serviceError)
        guard captures.count == 2, case .image = captures[1].0 else {
            return XCTFail("Expected image routed to Vault")
        }
        assertDestination(captures[1].1, is: .vault)
    }

    func testInfoPlistServicesExactlyMatchSystemManagedDescriptors() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let data = try Data(contentsOf: root.appendingPathComponent("release/Info.plist"))
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let services = try XCTUnwrap(plist["NSServices"] as? [[String: Any]])
        XCTAssertEqual(services.count, MacOSCaptureServiceDescriptor.all.count)

        for (service, descriptor) in zip(services, MacOSCaptureServiceDescriptor.all) {
            let menu = try XCTUnwrap(service["NSMenuItem"] as? [String: String])
            let equivalent = try XCTUnwrap(service["NSKeyEquivalent"] as? [String: String])
            XCTAssertEqual(menu["default"], descriptor.title)
            XCTAssertEqual(service["NSServiceDescription"] as? String, descriptor.serviceDescription)
            XCTAssertEqual(equivalent["default"], descriptor.systemKeyEquivalent)
            XCTAssertEqual(descriptor.isManagedBySystem, true)

            let sendTypes = Set(try XCTUnwrap(service["NSSendTypes"] as? [String]))
            XCTAssertTrue(sendTypes.isSuperset(of: [
                "public.utf8-plain-text", "public.rtf", "public.html",
                "public.url", "public.image", "public.png", "public.tiff"
            ]))
        }
    }

    func testHelpAndOnboardingDeriveCurrentShortcutsWithoutRetiredCopy() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let paths = [
            "Sources/PersonalNotepad/Views/Help/HelpView.swift",
            "Sources/PersonalNotepad/Views/Onboarding/OnboardingStep.swift",
            "Sources/PersonalNotepad/Views/Onboarding/OnboardingView.swift",
            "Sources/PersonalNotepad/Views/Onboarding/OnboardingIllustration.swift"
        ]
        let source = try paths
            .map { try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")

        for retired in [
            "Control–Option–N creates",
            "Control–Option–P creates",
            "Control-Option-Command-N",
            "Create Private Note in Clasp"
        ] {
            XCTAssertFalse(source.contains(retired), "Retired copy returned: \(retired)")
        }
        XCTAssertTrue(source.contains("shortcutWords(.captureSelectionToInbox)"))
        XCTAssertTrue(source.contains("shortcutWords(.saveClipboardToVault)"))
        XCTAssertTrue(source.contains("MacOSCaptureServiceDescriptor"))
        XCTAssertTrue(source.contains("The shortcuts shown above are macOS defaults"))
        XCTAssertGreaterThanOrEqual(
            source.components(separatedBy: "\"Default \\(").count - 1,
            3,
            "System-owned Service shortcut values must be labeled as defaults"
        )

        if DistributionCapabilities.supportsAccessibilitySelectionCapture {
            XCTAssertTrue(OnboardingStep.selection.message.contains("Control–Option–Shift–N"))
            XCTAssertTrue(OnboardingStep.selection.message.contains("Control–Option–Shift–P"))
        } else {
            XCTAssertTrue(OnboardingStep.selection.message.contains(MacOSCaptureServiceDescriptor.all[0].title))
            XCTAssertTrue(OnboardingStep.selection.message.contains(MacOSCaptureServiceDescriptor.all[1].title))
        }
    }

    func testShippingShortcutSurfacesDoNotRetainHardCodedCustomizableTriggers() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let app = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/PersonalNotepad/App/PersonalNotepadApp.swift"
            ),
            encoding: .utf8
        )
        let main = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/PersonalNotepad/Views/Main/MainRootView.swift"
            ),
            encoding: .utf8
        )
        let illustration = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/PersonalNotepad/Views/Onboarding/OnboardingIllustration.swift"
            ),
            encoding: .utf8
        )
        let step = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/PersonalNotepad/Views/Onboarding/OnboardingStep.swift"
            ),
            encoding: .utf8
        )

        XCTAssertFalse(app.contains(".keyboardShortcut(\"l\""))
        XCTAssertFalse(main.contains("Control-Option-Command-L"))
        XCTAssertTrue(main.contains("shortcutPreferences.shortcut(for: .lockVault)"))
        XCTAssertFalse(illustration.contains("KeycapGroup(keys: [\"⌥\", \"Space\"]"))
        XCTAssertTrue(illustration.contains("shortcutPreferences.shortcut(for: .quickCapturePrimary)"))
        XCTAssertFalse(step.contains("shortcuts use N for Normal and P for Protected"))
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "CaptureShortcutPreferencesTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    private func assertDestination(
        _ actual: CaptureDestination?,
        is expected: CaptureDestination,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch (actual, expected) {
        case (.inbox?, .inbox), (.vault?, .vault): break
        default: XCTFail("Unexpected capture destination", file: file, line: line)
        }
    }
}
