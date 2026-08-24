import AppKit
import SwiftUI

struct MenuBarContent: View {
    let appState: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var capturingClipboard = false

    var body: some View {
        Group {
            Button("Quick Capture") { openWindow(id: "quick-capture") }
            Button { captureClipboardToInbox() } label: {
                Label("Add Clipboard to Clasp", systemImage: AppIcon.Capture.clipboard)
            }
            .disabled(capturingClipboard)
            Button { captureClipboardToVault() } label: {
                Label("Add Clipboard to Vault", systemImage: AppIcon.Capture.clipboardToVault)
            }
            .disabled(capturingClipboard)
            Button("Open Clasp") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button { appState.clearClipboard() } label: { Label("Clear Clipboard", systemImage: AppIcon.Capture.clearClipboard) }
            Button { appState.lockVault() } label: { Label("Lock Vault", systemImage: AppIcon.Vault.lockNow) }
                .disabled(!appState.isVaultUnlocked)
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .appStateErrorAlert(appState)
    }

    private func captureClipboardToInbox() {
        guard !capturingClipboard else { return }
        capturingClipboard = true
        appState.saveClipboardToInbox()
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            capturingClipboard = false
        }
    }

    private func captureClipboardToVault() {
        guard !capturingClipboard else { return }
        capturingClipboard = true
        Task {
            await appState.saveClipboardToVaultAndClear()
            capturingClipboard = false
        }
    }
}
