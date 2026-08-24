import SwiftUI

struct VaultLockedView: View {
    let appState: AppState
    @State private var working = false

    var body: some View {
        ContentUnavailableView {
            Label("Vault Locked", systemImage: AppIcon.Vault.locked)
        } description: {
            Text("Vault titles, tags, bodies, and search results stay encrypted until you authenticate.")
        } actions: {
            if appState.isVaultLocking {
                ProgressView("Finishing lock…")
                    .controlSize(.small)
            } else if working {
                ProgressView("Unlocking Vault…")
                    .controlSize(.small)
            } else {
                Button("Unlock Vault") {
                    working = true
                    Task {
                        _ = await appState.unlockVault()
                        working = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .help("Authenticate with Touch ID or your Mac login password")
            }
        }
    }
}
