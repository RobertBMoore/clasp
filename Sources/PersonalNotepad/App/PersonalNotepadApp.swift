import AppKit
import SwiftUI

extension Notification.Name {
    static let mainNoteRequested = Notification.Name("PersonalNotepad.mainNoteRequested")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
#if !CLASP_VISUAL_QA
    private let hotKeys = GlobalHotKeyManager()
    private let serviceProvider = NotepadServiceProvider()
#endif
#if !CLASP_APP_STORE && !CLASP_VISUAL_QA
    private let selectionCapture = SelectionCaptureService()
#endif
    private var terminationIsFinishing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
#if !CLASP_VISUAL_QA
        NSApp.servicesProvider = serviceProvider
        NSUpdateDynamicServices()
#endif
#if !CLASP_APP_STORE && !CLASP_VISUAL_QA
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(captureSelectionToInbox(_:)),
            name: .captureSelectionToInbox,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(captureSelectionToVault(_:)),
            name: .captureSelectionToVault,
            object: nil
        )
#endif
#if !CLASP_VISUAL_QA
        let hotKeyResult = hotKeys.register()
        reportQuickCaptureShortcutFallbackIfNeeded(hotKeyResult)
#if !CLASP_APP_STORE
        reportSelectionShortcutFailureIfNeeded(hotKeyResult)
#endif
#endif
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu(title: "Clasp")
        menu.addItem(dockItem("Quick Capture", symbol: AppIcon.Capture.quick, action: #selector(openQuickCaptureFromDock)))
        menu.addItem(dockItem("Add Clipboard to Clasp", symbol: AppIcon.Capture.clipboard, action: #selector(saveClipboardFromDock)))
        menu.addItem(dockItem("Add Clipboard to Vault", symbol: AppIcon.Capture.clipboardToVault, action: #selector(saveClipboardToVaultFromDock)))
        menu.addItem(dockItem("Open Clasp", symbol: AppIcon.Utility.app, action: #selector(openClaspFromDock)))
        menu.addItem(.separator())
        menu.addItem(dockItem("Lock Vault", symbol: AppIcon.Vault.lockNow, action: #selector(lockVaultFromDock)))
        return menu
    }

    @objc private func openQuickCaptureFromDock() { GlobalActionBus.post(.openQuickCapture) }
    @objc private func saveClipboardFromDock() { GlobalActionBus.post(.saveClipboard) }
    @objc private func saveClipboardToVaultFromDock() { GlobalActionBus.post(.saveClipboardToVault) }
    @objc private func openClaspFromDock() { GlobalActionBus.post(.openMainWindow) }
    @objc private func lockVaultFromDock() { GlobalActionBus.post(.lockVault) }

#if !CLASP_APP_STORE && !CLASP_VISUAL_QA
    @objc private func captureSelectionToInbox(_ notification: Notification) {
        guard GlobalActionBus.claim(notification) else { return }
        Task { await captureSelection(to: .inbox) }
    }

    @objc private func captureSelectionToVault(_ notification: Notification) {
        guard GlobalActionBus.claim(notification) else { return }
        Task { await captureSelection(to: .vault) }
    }

    private func captureSelection(to destination: CaptureDestination) async {
        do {
            let content = try await selectionCapture.readSelection()
            ApplicationBridge.shared.submitCapture(content, destination: destination)
        } catch let error as LocalizedError {
            LocalConfirmationPresenter.shared.show(
                error.errorDescription ?? "Clasp could not capture the current selection.",
                kind: .error
            )
        } catch {
            LocalConfirmationPresenter.shared.show(
                "Clasp could not capture the current selection.",
                kind: .error
            )
        }
    }
#endif

#if !CLASP_VISUAL_QA
    private func reportQuickCaptureShortcutFallbackIfNeeded(_ result: GlobalHotKeyRegistrationResult) {
        guard !result.contains(.quickCapturePrimary) else { return }
        DispatchQueue.main.async {
            let message = result.contains(.quickCaptureFallback)
                ? "Option-Space is in use. Quick Capture: Control-Option-Command-N"
                : "Quick Capture shortcuts are in use. Use the Clasp menu bar icon."
            LocalConfirmationPresenter.shared.show(message, kind: .warning)
        }
    }
#endif

#if !CLASP_APP_STORE && !CLASP_VISUAL_QA
    private func reportSelectionShortcutFailureIfNeeded(_ result: GlobalHotKeyRegistrationResult) {
        let required: Set<GlobalHotKeyAction> = [.captureSelectionToInbox, .captureSelectionToVault]
        guard !required.isSubset(of: result.registered) else { return }
        DispatchQueue.main.async {
            LocalConfirmationPresenter.shared.show(
                "A Clasp selection shortcut is in use by another app. Right-click › Services remains available.",
                kind: .warning
            )
        }
    }
#endif

    private func dockItem(_ title: String, symbol: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let backupCustody = VaultRecoveryKeyCustody.shared
        guard !backupCustody.isBackupOperationInProgress else {
            sender.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Vault Backup in Progress"
            alert.informativeText = "Wait for the current Vault import or export to finish before quitting Clasp."
            alert.addButton(withTitle: "Return to Help")
            alert.runModal()
            return .terminateCancel
        }
        guard !backupCustody.hasUnstoredRecoveryKey else {
            sender.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Store Your Vault Recovery Key"
            alert.informativeText = "Clasp is still showing a one-time recovery key in Help. Store it separately from the encrypted export, then choose ‘I Have Stored the Key’ before quitting."
            alert.addButton(withTitle: "Return to Help")
            alert.runModal()
            return .terminateCancel
        }
        // A repeated quit request must join the existing flush rather than
        // bypass it. The first termination task owns the single AppKit reply.
        guard !terminationIsFinishing else { return .terminateLater }
        guard VaultLockCoordinator.shared.terminationHandler != nil else { return .terminateNow }
        terminationIsFinishing = true
        Task { @MainActor in
            await VaultLockCoordinator.shared.flushAndLockForTermination()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
    }
}

@main
struct PersonalNotepadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    @AppStorage(PreferenceKeys.appAppearance) private var appearance = AppAppearance.system.rawValue
#if CLASP_DIRECT_DISTRIBUTION
    @StateObject private var updater = UpdaterService()
#endif

    private var preferredColorScheme: ColorScheme? {
        AppAppearance(rawValue: appearance)?.colorScheme
    }

    var body: some Scene {
        Window("Clasp", id: "main") {
            MainRootView(appState: appState)
                .background(GlobalActionReceiver(appState: appState))
                .preferredColorScheme(preferredColorScheme)
                .task { await appState.start() }
        }
#if CLASP_VISUAL_QA
        // Apple accepts 16:10 Mac screenshots. The synthetic QA build opens at
        // that exact review viewport without changing the shipping default.
        .defaultSize(width: 1_280, height: 800)
#else
        .defaultSize(width: 1_180, height: 720)
#endif
        .commands {
            NotepadCommands()
#if CLASP_DIRECT_DISTRIBUTION
            CommandGroup(after: .appInfo) {
                CheckForUpdatesCommand(updater: updater)
            }
#endif
        }

        Window("Quick Capture", id: "quick-capture") {
            QuickCaptureView(appState: appState)
                .background(FloatingWindowConfigurator())
                .background(GlobalActionReceiver(appState: appState))
                .preferredColorScheme(preferredColorScheme)
        }
        .defaultSize(width: 520, height: 330)
        .windowResizability(.contentSize)

        Window("Welcome", id: "onboarding") {
            OnboardingView()
                .environment(appState)
                .preferredColorScheme(preferredColorScheme)
        }
        .defaultSize(width: 900, height: 640)
        .windowResizability(.contentSize)

        Window("Clasp Help", id: "help") {
            HelpView()
                .environment(appState)
                .preferredColorScheme(preferredColorScheme)
        }
        .defaultSize(width: 720, height: 620)

        Settings {
            SettingsView()
                .preferredColorScheme(preferredColorScheme)
        }

        MenuBarExtra("Clasp", systemImage: AppIcon.Utility.app) {
            MenuBarContent(appState: appState)
                .background(GlobalActionReceiver(appState: appState))
                .preferredColorScheme(preferredColorScheme)
        }
    }
}

private struct NotepadCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note") {
                requestMainNote(.contextual)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Secure Note") {
                requestMainNote(.vault)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandMenu("Capture") {
            Button("Quick Capture") {
                GlobalActionBus.post(.openQuickCapture)
            }

            Button {
                GlobalActionBus.post(.saveClipboard)
            } label: {
                Label("Add Clipboard to Clasp", systemImage: AppIcon.Capture.clipboard)
            }

            Button {
                GlobalActionBus.post(.saveClipboardToVault)
            } label: {
                Label("Add Clipboard to Vault", systemImage: AppIcon.Capture.clipboardToVault)
            }

            Divider()

            Button {
                GlobalActionBus.post(.clearClipboard)
            } label: {
                Label("Clear Clipboard", systemImage: AppIcon.Capture.clearClipboard)
            }

            Button("Lock Vault") {
                GlobalActionBus.post(.lockVault)
            }
            .keyboardShortcut("l", modifiers: [.control, .option, .command])
        }

        CommandGroup(replacing: .help) {
            Button("Clasp Help") {
                GlobalActionBus.post(.showOnboarding, userInfo: ["window": "help"])
            }
            Button("Show Onboarding") {
                GlobalActionBus.post(.showOnboarding, userInfo: ["window": "onboarding"])
            }
        }
    }

    private func requestMainNote(_ request: MainNoteRequest) {
        GlobalActionBus.requestMainNote(request)
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
