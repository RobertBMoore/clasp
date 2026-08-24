import SwiftUI

struct NoteEditorView: View {
    private enum EditorMode: String, CaseIterable, Identifiable {
        case page = "Page"
        case markdown = "Markdown"
        var id: String { rawValue }
    }

    let isVault: Bool
    let appState: AppState
    @State private var draft: Note
    @State private var tagText: String
    @State private var lastEditedAt: Date
    @State private var showPermanentDelete = false
    @SceneStorage("clasp.editorMode") private var editorModeRawValue = EditorMode.page.rawValue
    @State private var editorCommand: RichEditorCommandToken?
    @State private var showsDocumentStyle = false
    @AppStorage(PreferenceKeys.documentStylePreset) private var documentStylePreset = DocumentStylePreset.balanced.rawValue
    @AppStorage(PreferenceKeys.documentFontFamily) private var documentFontFamily = DocumentStyle.balanced.fontFamily.rawValue
    @AppStorage(PreferenceKeys.documentBodyPointSize) private var documentBodyPointSize = DocumentStyle.balanced.bodyPointSize
    @AppStorage(PreferenceKeys.documentLineHeightMultiplier) private var documentLineHeight = DocumentStyle.balanced.lineHeightMultiplier
    @AppStorage(PreferenceKeys.documentParagraphSpacing) private var documentParagraphSpacing = DocumentStyle.balanced.paragraphSpacing
    @AppStorage(PreferenceKeys.documentTargetCharactersPerLine) private var documentTargetCharacters = DocumentStyle.balanced.targetCharactersPerLine

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

            if editorMode == .page {
                RichFormattingBar { command in
                    editorCommand = RichEditorCommandToken(command: command)
                }
            } else {
                markdownSourceBar
            }

            RichMarkdownEditor(
                markdown: $draft.body,
                command: editorCommand,
                style: activeDocumentStyle,
                showsSource: editorMode == .markdown
            )
            .accessibilityLabel(editorMode == .page ? "Document page" : "Markdown source")

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
                Spacer(minLength: 8)
                editorModePicker
                documentStyleButton
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    titleField
                    vaultBadge
                }
                HStack(spacing: 10) {
                    editorModePicker
                    documentStyleButton
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var titleField: some View {
        TextField("Title", text: $draft.title)
            .textFieldStyle(.plain)
            .font(.title2.weight(.semibold))
            .frame(minWidth: 160)
            .layoutPriority(1)
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
        Picker("Editor mode", selection: editorModeBinding) {
            ForEach(EditorMode.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .labelsHidden()
        .frame(width: 190)
        .help("Switch between the document page and its stored Markdown source")
        .accessibilityLabel("Editor mode")
    }

    private var editorMode: EditorMode {
        EditorMode(rawValue: editorModeRawValue) ?? .page
    }

    private var editorModeBinding: Binding<EditorMode> {
        Binding(
            get: { editorMode },
            set: { editorModeRawValue = $0.rawValue }
        )
    }

    private var documentStyleButton: some View {
        Button {
            showsDocumentStyle.toggle()
        } label: {
            Image(systemName: "textformat.size")
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .help("Document Style")
        .accessibilityLabel("Document Style")
        .accessibilityHint("Adjust how Markdown is presented without changing the Markdown")
        .popover(isPresented: $showsDocumentStyle, arrowEdge: .bottom) {
            DocumentStylePopover()
        }
    }

    private var markdownSourceBar: some View {
        HStack(spacing: 8) {
            Label("Markdown Source", systemImage: "chevron.left.forwardslash.chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("Same document · changes appear in Page instantly")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.25))
        .accessibilityElement(children: .combine)
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

    private var activeDocumentStyle: DocumentStyle {
        let preset = DocumentStylePreset(rawValue: documentStylePreset) ?? .balanced
        return DocumentStyle(
            preset: preset,
            fontFamily: DocumentFontFamily(rawValue: documentFontFamily) ?? preset.style.fontFamily,
            bodyPointSize: documentBodyPointSize,
            lineHeightMultiplier: documentLineHeight,
            paragraphSpacing: documentParagraphSpacing,
            targetCharactersPerLine: documentTargetCharacters
        )
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

private struct DocumentStylePopover: View {
    @AppStorage(PreferenceKeys.documentStylePreset) private var presetRawValue = DocumentStylePreset.balanced.rawValue
    @AppStorage(PreferenceKeys.documentFontFamily) private var fontFamilyRawValue = DocumentStyle.balanced.fontFamily.rawValue
    @AppStorage(PreferenceKeys.documentBodyPointSize) private var bodyPointSize = DocumentStyle.balanced.bodyPointSize
    @AppStorage(PreferenceKeys.documentLineHeightMultiplier) private var lineHeightMultiplier = DocumentStyle.balanced.lineHeightMultiplier
    @AppStorage(PreferenceKeys.documentParagraphSpacing) private var paragraphSpacing = DocumentStyle.balanced.paragraphSpacing
    @AppStorage(PreferenceKeys.documentTargetCharactersPerLine) private var targetCharactersPerLine = DocumentStyle.balanced.targetCharactersPerLine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label("Document Style", systemImage: "textformat.size")
                    .font(.headline)
                Spacer()
                Text("Presentation only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Tune every Page view without adding style data to any note or Markdown file.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Preset", selection: presetBinding) {
                ForEach(DocumentStylePreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }

            if style != selectedPreset.style {
                Label("Adjusted from \(selectedPreset.title)", systemImage: "slider.horizontal.3")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Typeface")
                    Picker("Typeface", selection: fontFamilyBinding) {
                        ForEach(DocumentFontFamily.allCases) { family in
                            Text(family.title).tag(family)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel("Document typeface")
                }

                GridRow {
                    Text("Text")
                    Stepper(value: bodyPointSizeBinding, in: DocumentStyle.bodyPointSizeRange, step: 1) {
                        Text("\(style.bodyPointSize, specifier: "%.0f") pt")
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .accessibilityLabel("Body text size")
                }

                GridRow {
                    Text("Line height")
                    Stepper(value: lineHeightBinding, in: DocumentStyle.lineHeightMultiplierRange, step: 0.05) {
                        Text("\(style.lineHeightMultiplier, specifier: "%.2f")×")
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .accessibilityLabel("Line height")
                }

                GridRow {
                    Text("Line length")
                    Stepper(
                        value: targetCharactersBinding,
                        in: DocumentStyle.targetCharactersPerLineRange,
                        step: 1
                    ) {
                        Text("\(style.targetCharactersPerLine, specifier: "%.0f") characters")
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .accessibilityLabel("Target line length")
                }
            }

            HStack {
                Button("Balanced Defaults") {
                    apply(.balanced)
                }
                .help("Reset document presentation settings")

                Spacer()

                SettingsLink {
                    Text("More Settings…")
                }
            }
        }
        .padding(16)
        .frame(width: 350)
        .accessibilityElement(children: .contain)
    }

    private var selectedPreset: DocumentStylePreset {
        DocumentStylePreset(rawValue: presetRawValue) ?? .balanced
    }

    private var style: DocumentStyle {
        DocumentStyle(
            preset: selectedPreset,
            fontFamily: DocumentFontFamily(rawValue: fontFamilyRawValue) ?? selectedPreset.style.fontFamily,
            bodyPointSize: bodyPointSize,
            lineHeightMultiplier: lineHeightMultiplier,
            paragraphSpacing: paragraphSpacing,
            targetCharactersPerLine: targetCharactersPerLine
        )
    }

    private var presetBinding: Binding<DocumentStylePreset> {
        Binding(
            get: { selectedPreset },
            set: { apply($0) }
        )
    }

    private var fontFamilyBinding: Binding<DocumentFontFamily> {
        Binding(
            get: { style.fontFamily },
            set: { fontFamilyRawValue = $0.rawValue }
        )
    }

    private var bodyPointSizeBinding: Binding<Double> {
        clampedBinding($bodyPointSize, using: DocumentStyle.clampBodyPointSize)
    }

    private var lineHeightBinding: Binding<Double> {
        clampedBinding($lineHeightMultiplier, using: DocumentStyle.clampLineHeightMultiplier)
    }

    private var targetCharactersBinding: Binding<Double> {
        clampedBinding($targetCharactersPerLine, using: DocumentStyle.clampTargetCharactersPerLine)
    }

    private func clampedBinding(_ source: Binding<Double>, using clamp: @escaping (Double) -> Double) -> Binding<Double> {
        Binding(
            get: { clamp(source.wrappedValue) },
            set: { source.wrappedValue = clamp($0) }
        )
    }

    private func apply(_ preset: DocumentStylePreset) {
        let value = preset.style
        presetRawValue = preset.rawValue
        fontFamilyRawValue = value.fontFamily.rawValue
        bodyPointSize = value.bodyPointSize
        lineHeightMultiplier = value.lineHeightMultiplier
        paragraphSpacing = value.paragraphSpacing
        targetCharactersPerLine = value.targetCharactersPerLine
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
