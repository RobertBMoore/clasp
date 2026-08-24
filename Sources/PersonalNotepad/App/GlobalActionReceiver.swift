import AppKit
import SwiftUI

struct GlobalActionReceiver: View {
    let appState: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var configured = false

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                guard !configured else { return }
                configured = true
                ApplicationBridge.shared.configureCapture { content, destination in
                    Task { _ = await appState.capture(content, to: destination) }
                }
                VaultLockCoordinator.shared.lockHandler = { appState.lockVault() }
                VaultLockCoordinator.shared.terminationHandler = { await appState.flushAndLockForTermination() }
                VaultLockCoordinator.shared.start()
#if !CLASP_VISUAL_QA
                if !OnboardingPreferences().isComplete {
                    openWindow(id: "onboarding")
                }
#endif
            }
            .onReceive(NotificationCenter.default.publisher(for: .openQuickCapture)) { notification in
                guard GlobalActionBus.claim(notification) else { return }
                appState.quickCaptureSeed = ""
                appState.quickCaptureDestination = .inbox
                openWindow(id: "quick-capture")
                NSApp.activate(ignoringOtherApps: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openMainWindow)) { notification in
                guard GlobalActionBus.claim(notification) else { return }
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .saveClipboard)) { notification in
                guard GlobalActionBus.claim(notification) else { return }
                appState.saveClipboardToInbox()
            }
            .onReceive(NotificationCenter.default.publisher(for: .saveClipboardToVault)) { notification in
                guard GlobalActionBus.claim(notification) else { return }
                Task { await appState.saveClipboardToVaultAndClear() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .clearClipboard)) { notification in
                guard GlobalActionBus.claim(notification) else { return }
                appState.clearClipboard()
            }
            .onReceive(NotificationCenter.default.publisher(for: .lockVault)) { notification in
                guard GlobalActionBus.claim(notification) else { return }
                appState.lockVault()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showOnboarding)) { notification in
                guard GlobalActionBus.claim(notification) else { return }
                openWindow(id: notification.userInfo?["window"] as? String ?? "onboarding")
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}
