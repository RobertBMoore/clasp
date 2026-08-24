import SwiftUI

struct MainRootView: View {
    let appState: AppState
    @State private var destination: SidebarDestination? = .inbox
#if CLASP_VISUAL_QA
    // The separately bundled visual-QA app uses only synthetic, memory-backed
    // notes. Select the primary fixture deterministically so screenshot review
    // never depends on driving a real note or persisted navigation state.
    @State private var selectedNoteID: UUID?
#else
    @State private var selectedNoteID: UUID?
#endif
    @State private var query = ""
    @State private var shortcutPreferences = GlobalHotKeyPreferences.shared

    var body: some View {
        NavigationSplitView {
            SidebarView(appState: appState, selection: $destination)
                .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } content: {
            NoteListView(
                items: visibleNotes,
                selectedNoteID: $selectedNoteID,
                query: $query,
                destination: destination ?? .inbox,
                appState: appState
            )
            .navigationSplitViewColumnWidth(min: 260, ideal: 330)
        } detail: {
            detail
        }
        .overlay(alignment: .bottom) {
            if let message = appState.statusMessage {
                Text(message)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityLabel("Status: \(message)")
            }
        }
        .animation(.easeOut(duration: 0.2), value: appState.statusMessage)
        .appStateErrorAlert(appState)
        .onChange(of: destination) { _, _ in
            selectedNoteID = nil
            query = ""
        }
#if CLASP_VISUAL_QA
        .onChange(of: appState.isLoading) { _, isLoading in
            guard !isLoading else { return }
            destination = .inbox
            selectedNoteID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")
        }
#endif
        .onChange(of: appState.isVaultUnlocked) { wasUnlocked, isUnlocked in
            guard wasUnlocked, !isUnlocked else { return }
            selectedNoteID = nil
            query = ""
        }
        .onChange(of: selectedLifecycle) { _, lifecycle in
            guard selectedNoteID != nil else { return }
            guard let lifecycle else {
                selectedNoteID = nil
                return
            }
            if !lifecycle.remainsVisible(in: destination ?? .inbox) {
                selectedNoteID = nil
            }
        }
        .onAppear { fulfillPendingMainNoteRequests() }
        .onReceive(NotificationCenter.default.publisher(for: .mainNoteRequested)) { _ in
            fulfillPendingMainNoteRequests()
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    createContextualNote()
                } label: {
                    Label(
                        destination == .vault ? "New Vault Note" : "New Note",
                        systemImage: AppIcon.Create.note
                    )
                }
                .help(destination == .vault ? "New Secure Vault Note — Command-N" : "New Note — Command-N")

                if destination != .vault {
                    Button {
                        Task {
                            destination = .vault
                            selectedNoteID = await appState.createVault()
                        }
                    } label: {
                        Label("New Secure Note", systemImage: AppIcon.Create.secureNote)
                    }
                    .help("New Secure Note in Vault — Shift-Command-N")
                }

                if appState.isVaultUnlocked {
                    Button { appState.lockVault() } label: {
                        Label("Lock Vault", systemImage: AppIcon.Vault.lockNow)
                    }
                    .help(lockVaultHelp)
                }
            }
        }
    }

    private func createContextualNote() {
        if destination == .vault {
            Task {
                selectedNoteID = await appState.createVault()
            }
        } else {
            destination = .inbox
            selectedNoteID = appState.createRegular()
        }
    }

    private var lockVaultHelp: String {
        guard let shortcut = shortcutPreferences.shortcut(for: .lockVault) else {
            return "Lock Vault — No global shortcut"
        }
        return "Lock Vault — \(shortcut.displayName)"
    }

    private func fulfillPendingMainNoteRequests() {
        let requests = GlobalActionBus.takeMainNoteRequests()
        guard !requests.isEmpty else { return }
        Task { @MainActor in
            for request in requests {
                switch request {
                case .contextual:
                    if destination == .vault {
                        selectedNoteID = await appState.createVault()
                    } else {
                        destination = .inbox
                        selectedNoteID = appState.createRegular()
                    }
                case .vault:
                    destination = .vault
                    selectedNoteID = await appState.createVault()
                }
            }
        }
    }

    private var visibleNotes: [SearchResult] {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return appState.search(query, in: destination ?? .inbox)
        }
        return appState.noteResults(for: destination ?? .inbox)
    }

    @ViewBuilder private var detail: some View {
        if appState.isLoading {
            ProgressView("Loading Notes…")
                .controlSize(.large)
        } else if destination == .vault && !appState.isVaultUnlocked {
            VaultLockedView(appState: appState)
        } else if let selectedNoteID,
                  let result = selectedResult(id: selectedNoteID) {
            NoteEditorView(note: result.note, isVault: result.source == .vault, appState: appState)
                .id(result.note.id)
        } else {
            ContentUnavailableView("Select a Note", systemImage: AppIcon.Content.note, description: Text("Choose a note or press Command-N to capture a new thought."))
        }
    }

    /// Keep an explicitly selected note mounted while a search or tag edit
    /// changes the current list filter. Navigation, deletion, and Vault lock
    /// remain the events that remove the selection.
    private func selectedResult(id: UUID) -> SearchResult? {
        if let note = appState.regularNotes.first(where: { $0.id == id }) {
            return SearchResult(note: note, source: .regular)
        }
        if let note = appState.vaultNotes?.first(where: { $0.id == id }) {
            return SearchResult(note: note, source: .vault)
        }
        return nil
    }

    private var selectedLifecycle: NoteSelectionLifecycle? {
        guard let selectedNoteID,
              let result = selectedResult(id: selectedNoteID) else { return nil }
        return NoteSelectionLifecycle(result: result)
    }
}

struct NoteSelectionLifecycle: Equatable {
    let source: SearchResult.Source
    let isPinned: Bool
    let isArchived: Bool
    let isInInbox: Bool
    let isTrashed: Bool

    init(result: SearchResult) {
        source = result.source
        isPinned = result.note.isPinned
        isArchived = result.note.isArchived
        isInInbox = result.note.isInInbox
        isTrashed = result.note.trashedAt != nil
    }

    func remainsVisible(in destination: SidebarDestination) -> Bool {
        switch destination {
        case .inbox:
            source == .regular && isInInbox && !isArchived && !isTrashed
        case .allNotes:
            !isTrashed
        case .pinned:
            source == .regular && isPinned && !isTrashed
        case .vault:
            source == .vault && !isTrashed
        case .trash:
            isTrashed
        case .tag:
            // Tag edits intentionally keep the editor mounted even when the
            // edited tag no longer matches the list. Trashing is a lifecycle
            // move and still clears the selection.
            source == .regular && !isTrashed
        }
    }
}
