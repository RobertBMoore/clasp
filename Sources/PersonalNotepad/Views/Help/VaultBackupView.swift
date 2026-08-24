import AppKit
import SwiftUI

@MainActor
final class VaultRecoveryKeyCustody {
    static let shared = VaultRecoveryKeyCustody()

    private(set) var hasUnstoredRecoveryKey = false
    private(set) var isBackupOperationInProgress = false

    private init() {}

    func markUnstored() { hasUnstoredRecoveryKey = true }
    func markStored() { hasUnstoredRecoveryKey = false }
    func beginOperation() { isBackupOperationInProgress = true }
    func endOperation() { isBackupOperationInProgress = false }
}

struct VaultBackupOperationState: Equatable {
    let isExporting: Bool
    let isImporting: Bool
    let hasUnstoredRecoveryKey: Bool

    var canStartOperation: Bool {
        !isExporting && !isImporting && !hasUnstoredRecoveryKey
    }

    var blocksDismissal: Bool {
        isExporting || isImporting || hasUnstoredRecoveryKey
    }
}

struct VaultBackupView: View {
    let appState: AppState
    @State private var recoveryKey: String?
    @State private var importKey = ""
    @State private var pendingImportURL: URL?
    @State private var confirmImport = false
    @State private var importError: String?
    @State private var exportError: String?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var confirmRecoveryKeyDismissal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack { backupButtons }
                VStack(alignment: .leading) { backupButtons }
            }
            if let recoveryKey {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Recovery key — shown once", systemImage: AppIcon.Vault.recoveryKey)
                        .font(.headline)
                    Text(recoveryKey)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .privacySensitive()
                        .accessibilityHint("Store this key separately from the exported Vault file")
                    Text("Store this separately from the exported file. A lost key cannot be recovered, and Clasp keeps Help open until you acknowledge that it is stored.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Store or hide this key before starting another Vault import or export.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Button("I Have Stored the Key") { confirmRecoveryKeyDismissal = true }
                }
                .padding()
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .confirmationDialog("Hide this recovery key?", isPresented: $confirmRecoveryKeyDismissal) {
            Button("Hide Recovery Key", role: .destructive) {
                recoveryKey = nil
                VaultRecoveryKeyCustody.shared.markStored()
            }
            Button("Keep Showing Key", role: .cancel) {}
        } message: {
            Text("Clasp cannot show this recovery key again. Confirm that you stored it separately from the encrypted export.")
        }
        .alert("Couldn’t Export Vault", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "The encrypted Vault export could not be created.")
        }
        .confirmationDialog("Replace the current Vault?", isPresented: $confirmImport) {
            Button("Continue to Recovery Key", role: .destructive) {
                importKey = ""
            }
            Button("Cancel", role: .cancel) { clearPendingImportURL() }
        } message: {
            Text("Clasp will keep a recoverable copy of the previous encrypted container before replacing it.")
        }
        .sheet(isPresented: Binding(
            get: { pendingImportURL != nil && !confirmImport },
            set: { if !$0 && !isImporting { clearPendingImportURL() } }
        )) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Enter Recovery Key").font(.title2.bold())
                Text("The key was shown once when this backup was exported.")
                    .foregroundStyle(.secondary)
                SecureField("Recovery key", text: $importKey)
                    .textFieldStyle(.roundedBorder)
                    .privacySensitive()
                HStack {
                    if isImporting {
                        ProgressView("Importing and protecting the previous Vault…")
                            .controlSize(.small)
                    }
                    Spacer()
                    Button("Cancel") { clearPendingImportURL() }
                        .keyboardShortcut(.cancelAction)
                        .disabled(isImporting)
                    Button("Import", role: .destructive) {
                        guard !isImporting, let url = pendingImportURL else { return }
                        do {
                            let encoded = importKey.trimmingCharacters(in: .whitespacesAndNewlines)
                            let key = try RecoveryKey(encoded: encoded)
                            isImporting = true
                            beginProtectedOperation()
                            Task {
                                let succeeded = await appState.importVault(from: url, recoveryKey: key)
                                isImporting = false
                                VaultRecoveryKeyCustody.shared.endOperation()
                                if succeeded {
                                    clearPendingImportURL()
                                    importKey = ""
                                } else {
                                    importError = takeAppError(
                                        fallback: "The encrypted Vault backup could not be imported."
                                    )
                                }
                            }
                        } catch {
                            importError = error.localizedDescription
                        }
                    }
                    .disabled(isImporting || importKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(24)
            .frame(width: 480)
            .interactiveDismissDisabled(isImporting)
            .alert("Couldn’t Import Vault", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "The encrypted Vault backup could not be imported.")
            }
        }
        .onDisappear {
            if !isImporting { clearPendingImportURL() }
        }
        .interactiveDismissDisabled(operationState.blocksDismissal)
        .background {
            VaultBackupWindowDismissalGuard(isDisabled: operationState.blocksDismissal)
                .frame(width: 0, height: 0)
        }
    }

    @ViewBuilder
    private var backupButtons: some View {
        Button {
            guard operationState.canStartOperation else { return }
            guard let url = FilePanelService.chooseExportURL() else { return }
            isExporting = true
            beginProtectedOperation()
            Task {
                defer {
                    isExporting = false
                    VaultRecoveryKeyCustody.shared.endOperation()
                    FilePanelService.releaseAccess(to: url)
                }
                guard await appState.ensureVaultUnlocked() else {
                    exportError = takeAppError(
                        fallback: "The Vault could not be unlocked for export."
                    )
                    return
                }
                guard let key = await appState.exportVault(to: url) else {
                    exportError = takeAppError(
                        fallback: "The encrypted Vault export could not be created."
                    )
                    return
                }
                recoveryKey = key.encoded
                VaultRecoveryKeyCustody.shared.markUnstored()
            }
        } label: {
            if isExporting {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Exporting…")
                }
            } else {
                Text("Export Encrypted Vault")
            }
        }
        .disabled(!operationState.canStartOperation)
        .help(recoveryKey == nil ? "Create an encrypted Vault export" : "Store or hide the current recovery key first")
        Button("Import Encrypted Vault") {
            guard operationState.canStartOperation else { return }
            pendingImportURL = FilePanelService.chooseImportURL()
            if pendingImportURL != nil { confirmImport = true }
        }
        .disabled(!operationState.canStartOperation)
        .help(recoveryKey == nil ? "Replace the Vault from an encrypted export" : "Store or hide the current recovery key first")
    }

    private var operationState: VaultBackupOperationState {
        VaultBackupOperationState(
            isExporting: isExporting,
            isImporting: isImporting,
            hasUnstoredRecoveryKey: recoveryKey != nil
        )
    }

    private func takeAppError(fallback: String) -> String {
        let message = appState.presentedError ?? fallback
        appState.presentedError = nil
        return message
    }

    private func beginProtectedOperation() {
        // The action runs in the Help window, so close the Command-W race
        // before SwiftUI has a chance to reconcile the dismissal guard.
        NSApp.keyWindow?.standardWindowButton(.closeButton)?.isEnabled = false
        VaultRecoveryKeyCustody.shared.beginOperation()
    }

    private func clearPendingImportURL() {
        guard !isImporting else { return }
        importKey = ""
        importError = nil
        confirmImport = false
        guard let url = pendingImportURL else { return }
        pendingImportURL = nil
        FilePanelService.releaseAccess(to: url)
    }
}

/// A Help window must stay alive until an import or export finishes. In
/// addition to SwiftUI presentation dismissal, disabling the standard close
/// button also gates Command-W/performClose for the containing macOS window.
private struct VaultBackupWindowDismissalGuard: NSViewRepresentable {
    let isDisabled: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        updateWindow(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        updateWindow(for: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Void) {
        nsView.window?.standardWindowButton(.closeButton)?.isEnabled = true
    }

    private func updateWindow(for view: NSView) {
        if let window = view.window {
            window.standardWindowButton(.closeButton)?.isEnabled = !isDisabled
            return
        }
        DispatchQueue.main.async { [weak view] in
            view?.window?.standardWindowButton(.closeButton)?.isEnabled = !isDisabled
        }
    }
}
