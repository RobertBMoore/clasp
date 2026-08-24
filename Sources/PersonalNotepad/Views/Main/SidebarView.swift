import SwiftUI

struct SidebarView: View {
    let appState: AppState
    @Binding var selection: SidebarDestination?

    var body: some View {
        List(selection: $selection) {
            Section {
                row(.inbox)
                row(.allNotes)
                row(.pinned)
                row(.vault)
                row(.trash)
            }
            if !appState.allTags.isEmpty {
                Section("Tags") {
                    ForEach(appState.allTags, id: \.self) { row(.tag($0)) }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Clasp")
    }

    private func row(_ destination: SidebarDestination) -> some View {
        Label(destination.title, systemImage: destination.systemImage)
            .symbolRenderingMode(.monochrome)
            .imageScale(.medium)
            .tag(destination)
            .contextMenu {
                if destination == .vault && appState.isVaultUnlocked {
                    Button("Lock Vault") { appState.lockVault() }
                }
            }
    }
}
