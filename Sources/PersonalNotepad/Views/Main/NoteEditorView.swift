import SwiftUI

struct NoteEditorView: View {
    private enum EditorMode: String, CaseIterable, Identifiable {
        case formatted = "Formatted"
        case markdown = "Markdown"
        var id: String { rawValue }
    }

    let isVault: Bool
    let appState: AppState
    @State private var draft: Note
    @State private var tagText: String
    @State private var lastEditedAt: Date
    @State private var showPermanentDelete = false
    @State private var editorMode: EditorMode = .formatted
    @State private var editorCommand: RichEditorCommandToken?

    init(note: Note, isVault: Bool, appState: AppState) {
        self.isVault = isVault
        self.appState = appState
        _draft = State(initialValue: note)
        _tagText = State(initialValue: note.tags.joined(separator: ", "))
        _lastEditedAt = State(initialValue: note.updatedAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            editorHeader
            .padding(.horizontal, 20)
            .padding(.top, 18)

            if !draft.attachments.isEmpty {
                AttachmentGallery(attachments: draft.attachments)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                if !draft.extractedText.isEmpty {
                    DisclosureGroup("Text found in image (searchable)") {
                        Text(draft.extractedText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }

            if editorMode == .formatted {
                RichFormattingBar { command in
                    editorCommand = RichEditorCommandToken(command: command)
                }
                RichMarkdownEditor(markdown: $draft.body, command: editorCommand)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 4)
                    .accessibilityLabel("Formatted note body")
            } else {
                TextEditor(text: $draft.body)
                    .font(.body.monospaced())
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 10)
                    .accessibilityLabel("Markdown source")
            }

            if !detectedLinks.isEmpty {
                Divider()
                DetectedLinksView(urls: detectedLinks)
            }

            Divider()
            metadataBar
        }
        .onChange(of: draft.body) { _, _ in draft.deriveInitialTitleIfNeeded() }
        .onChange(of: draft) { _, updated in
            lastEditedAt = Date()
            persist(updated)
        }
        .onChange(of: currentNote) { _, latest in
            guard let latest else { return }
            // Organization-only changes intentionally do not replace the
            // editor buffer. Content changes from another window do.
            guard draft.title != latest.title
                    || draft.body != latest.body
                    || draft.tags != latest.tags else { return }
            draft.title = latest.title
            draft.body = latest.body
            draft.tags = latest.tags
            tagText = latest.tags.joined(separator: ", ")
            lastEditedAt = latest.updatedAt
        }
        .onChange(of: tagText) { _, _ in commitTags() }
        .toolbar {
            ToolbarItemGroup {
                if currentNote?.trashedAt == nil {
                    Button { appState.togglePin(draft.id, isVault: isVault) } label: {
                        Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? AppIcon.NoteAction.unpin : AppIcon.NoteAction.pin)
                    }
                    .help(isPinned ? "Unpin Note" : "Pin Note")

                    Menu {
                        Button {
                            appState.toggleArchive(draft.id, isVault: isVault)
                        } label: {
                            Label(
                                isArchived ? "Unarchive" : "Archive",
                                systemImage: AppIcon.NoteAction.archive
                            )
                        }

                        if !isVault && isInInbox {
                            Button {
                                appState.moveOutOfInbox(draft.id)
                            } label: {
                                Label("File in All Notes", systemImage: AppIcon.NoteAction.removeFromInbox)
                            }
                        }

                        Divider()

                        Button(role: .destructive) {
                            appState.trash(draft.id, isVault: isVault)
                        } label: {
                            Label("Move to Trash", systemImage: AppIcon.NoteAction.moveToTrash)
                        }
                    } label: {
                        Label("More Note Actions", systemImage: AppIcon.NoteAction.more)
                    }
                    .help("More Note Actions")
                } else {
                    Button { appState.restore(draft.id, isVault: isVault) } label: {
                        Label("Restore", systemImage: AppIcon.NoteAction.restore)
                    }
                    .help("Restore Note")

                    Menu {
                        Button(role: .destructive) { showPermanentDelete = true } label: {
                            Label("Delete Permanently", systemImage: AppIcon.NoteAction.deletePermanently)
                        }
                    } label: {
                        Label("More Note Actions", systemImage: AppIcon.NoteAction.more)
                    }
                    .help("More Note Actions")
                }
            }
        }
        .confirmationDialog("Delete this note permanently?", isPresented: $showPermanentDelete) {
            Button("Delete Permanently", role: .destructive) {
                Task { await appState.permanentlyDelete(draft.id, isVault: isVault) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Clasp does not promise secure erasure on SSD storage.")
        }
    }

    private var editorHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                titleField
                vaultBadge
                editorModePicker
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    titleField
                    vaultBadge
                }
                editorModePicker
                    .frame(maxWidth: 260)
            }
        }
    }

    private var titleField: some View {
        TextField("Title", text: $draft.title)
            .textFieldStyle(.plain)
            .font(.title2.weight(.semibold))
            .accessibilityLabel("Note title")
    }

    @ViewBuilder
    private var vaultBadge: some View {
        if isVault {
            Label("Vault", systemImage: AppIcon.Vault.noteBadge)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
                .help("Encrypted Vault note")
                .accessibilityLabel("Encrypted Vault note")
        }
    }

    private var editorModePicker: some View {
        Picker("Editor mode", selection: $editorMode) {
            ForEach(EditorMode.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .labelsHidden()
        .frame(width: 210)
        .help("Switch between formatted editing and the stored Markdown source")
        .accessibilityLabel("Editor mode")
    }

    private var metadataBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                noteKindLabel
                tagEditor
                Spacer(minLength: 12)
                timestamps
            }

            VStack(alignment: .leading, spacing: 10) {
                noteKindLabel
                tagEditor
                timestamps
            }
        }
        .padding(12)
    }

    private var noteKindLabel: some View {
        Label(
            isVault && draft.contentType == .note ? "Secure Note" : draft.contentType.title,
            systemImage: isVault && draft.contentType == .note
                ? AppIcon.Vault.secureDocument
                : draft.contentType.symbol
        )
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .fixedSize()
    }

    private var tagEditor: some View {
        HStack(spacing: 7) {
            Label("Tags", systemImage: AppIcon.Editing.tag)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            TextField("Tags, separated by commas", text: $tagText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .onSubmit { commitTags() }
                .accessibilityLabel("Tags")
                .accessibilityHint("Separate multiple tags with commas")
        }
        .frame(minWidth: 120)
    }

    private var timestamps: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("Created \(draft.createdAt.formatted(date: .abbreviated, time: .shortened))")
            Text("Edited \(lastEditedAt.formatted(date: .abbreviated, time: .shortened))")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var detectedLinks: [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(draft.body.startIndex..., in: draft.body)
        return ExternalLinkPolicy.filterAllowed(
            detector.matches(in: draft.body, range: range).compactMap(\.url)
        )
    }

    private var currentNote: Note? {
        if isVault {
            return appState.vaultNotes?.first { $0.id == draft.id }
        }
        return appState.regularNotes.first { $0.id == draft.id }
    }

    private var isPinned: Bool { currentNote?.isPinned ?? false }
    private var isArchived: Bool { currentNote?.isArchived ?? false }
    private var isInInbox: Bool { currentNote?.isInInbox ?? false }

    private func commitTags() {
        let tags = tagText.split(separator: ",").map(String.init)
        if draft.tags != Note.normalizedTags(tags) { draft.tags = Note.normalizedTags(tags) }
    }

    private func persist(_ note: Note) {
        appState.updateEditorContent(
            id: note.id,
            isVault: isVault,
            title: note.title,
            body: note.body,
            tags: note.tags
        )
    }
}

private struct AttachmentGallery: View {
    let attachments: [NoteAttachment]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                    if let image = NSImage(data: attachment.data) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 520, maxHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay { RoundedRectangle(cornerRadius: 10).stroke(.separator.opacity(0.5)) }
                            .accessibilityLabel("Attached image \(index + 1) of \(attachments.count)")
                    }
                }
            }
        }
    }
}

private struct DetectedLinksView: View {
    let urls: [URL]

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 280), spacing: 10, alignment: .leading)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(urls.count == 1 ? "Detected Link" : "Detected Links", systemImage: AppIcon.Content.link)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(Array(urls.prefix(12).enumerated()), id: \.offset) { _, url in
                    Link(destination: url) {
                        Text(linkLabel(for: url))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .help(url.absoluteString)
                    .accessibilityLabel(url.absoluteString)
                }
            }
            if urls.count > 12 {
                Text("\(urls.count - 12) more links are available in the note body.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
    }

    private func linkLabel(for url: URL) -> String {
        guard let host = url.host() else { return url.absoluteString }
        let path = url.path(percentEncoded: false)
        return path == "/" || path.isEmpty ? host : "\(host)\(path)"
    }
}
