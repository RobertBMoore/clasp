import SwiftUI

struct NoteListView: View {
    let items: [SearchResult]
    @Binding var selectedNoteID: UUID?
    @Binding var query: String
    let destination: SidebarDestination
    let appState: AppState

    var body: some View {
        if destination == .vault && !appState.isVaultUnlocked {
            noteList
        } else {
            noteList
                .searchable(text: $query, placement: .toolbar, prompt: searchPrompt)
        }
    }

    private var noteList: some View {
        List(items, selection: $selectedNoteID) { item in
            let note = item.note
            let isVaultNote = item.source == .vault
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: leadingSymbol(for: note, isVault: isVaultNote))
                        .foregroundStyle(note.contentType == .image ? .purple : .secondary)
                        .frame(width: 16)
                    Text(note.displayTitle)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .help(note.displayTitle)
                    Spacer(minLength: 4)
                    if let state = primaryState(for: note) {
                        Image(systemName: state.symbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help(state.help)
                            .accessibilityHidden(true)
                    }
                }
                Text(note.excerpt.isEmpty ? "No additional text" : note.excerpt)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(note.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .tag(note.id)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(note.displayTitle)
            .accessibilityValue(accessibilitySummary(for: note, isVault: isVaultNote))
            .contextMenu {
                if note.trashedAt == nil {
                    Button {
                        appState.togglePin(note.id, isVault: isVaultNote)
                    } label: {
                        Label(
                            note.isPinned ? "Unpin" : "Pin",
                            systemImage: note.isPinned ? AppIcon.NoteAction.unpin : AppIcon.NoteAction.pin
                        )
                    }

                    Button {
                        appState.toggleArchive(note.id, isVault: isVaultNote)
                    } label: {
                        Label(
                            note.isArchived ? "Unarchive" : "Archive",
                            systemImage: AppIcon.NoteAction.archive
                        )
                    }

                    if !isVaultNote && note.isInInbox {
                        Button {
                            appState.moveOutOfInbox(note.id)
                        } label: {
                            Label("File in All Notes", systemImage: AppIcon.NoteAction.removeFromInbox)
                        }
                    }

                    Divider()

                    Button(role: .destructive) {
                        appState.trash(note.id, isVault: isVaultNote)
                    } label: {
                        Label("Move to Trash", systemImage: AppIcon.NoteAction.moveToTrash)
                    }
                } else {
                    Button {
                        appState.restore(note.id, isVault: isVaultNote)
                    } label: {
                        Label("Restore", systemImage: AppIcon.NoteAction.restore)
                    }
                }
            }
        }
        .overlay {
            if appState.isLoading {
                ProgressView("Loading Notes…")
                    .controlSize(.small)
            } else if items.isEmpty {
                emptyState
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if hasQuery {
            ContentUnavailableView(
                "No Results",
                systemImage: AppIcon.Utility.search,
                description: Text("No notes match “\(query.trimmingCharacters(in: .whitespacesAndNewlines))”.")
            )
        } else {
            let state = destination.emptyState(isVaultUnlocked: appState.isVaultUnlocked)
            ContentUnavailableView(
                state.title,
                systemImage: state.symbol,
                description: Text(state.description)
            )
        }
    }

    private func leadingSymbol(for note: Note, isVault: Bool) -> String {
        if isVault {
            return AppIcon.Vault.secureDocument
        }
        return note.contentType.symbol
    }

    private var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchPrompt: String {
        switch destination {
        case .inbox: "Search Inbox"
        case .allNotes: "Search all notes"
        case .pinned: "Search pinned notes"
        case .vault: "Search Vault"
        case .trash: "Search Trash"
        case .tag(let tag): "Search \(tag)"
        }
    }

    private func primaryState(for note: Note) -> (symbol: String, help: String)? {
        if note.isPinned {
            return (AppIcon.NoteAction.pinned, "Pinned")
        }
        if note.isArchived {
            return (AppIcon.NoteAction.archived, "Archived")
        }
        return nil
    }

    private func accessibilitySummary(for note: Note, isVault: Bool) -> String {
        var details: [String] = []
        let excerpt = note.excerpt.isEmpty ? "No additional text" : note.excerpt
        details.append(excerpt)
        if isVault { details.append("Encrypted Vault \(note.contentType.title.lowercased())") }
        if note.isPinned { details.append("Pinned") }
        if note.isArchived { details.append("Archived") }
        if note.trashedAt != nil { details.append("In Trash") }
        details.append("Edited \(note.updatedAt.formatted(.relative(presentation: .named)))")
        return details.joined(separator: ", ")
    }
}

private extension SidebarDestination {
    func emptyState(isVaultUnlocked: Bool) -> (title: String, symbol: String, description: String) {
        switch self {
        case .inbox:
            ("Inbox Is Clear", AppIcon.Navigation.inbox, "New notes and captures appear here.")
        case .allNotes:
            ("No Notes Yet", AppIcon.Content.note, "Create a note or capture something to get started.")
        case .pinned:
            ("No Pinned Notes", AppIcon.Navigation.pinned, "Pin a note to keep it close at hand.")
        case .vault where !isVaultUnlocked:
            ("Vault Locked", AppIcon.Vault.locked, "Unlock the Vault to see secure notes.")
        case .vault:
            ("No Vault Notes", AppIcon.Vault.secureDocument, "Create a secure Vault note to get started.")
        case .trash:
            ("Trash Is Empty", AppIcon.Navigation.trash, "Deleted notes remain here until you remove them permanently.")
        case .tag(let tag):
            ("No Notes Tagged \(tag)", AppIcon.Navigation.tag, "Add this tag to a note and it will appear here.")
        }
    }
}
