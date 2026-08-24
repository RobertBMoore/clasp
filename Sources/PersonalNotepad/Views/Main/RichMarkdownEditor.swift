import AppKit
import SwiftUI

enum RichEditorCommand: Equatable {
    case body
    case heading1
    case heading2
    case heading3
    case heading4
    case heading5
    case heading6
    case bold
    case italic
    case strikethrough
    case inlineCode
    case link(String)
    case bulletList
    case numberedList
    case checklist
    case blockquote
    case fencedCode
    case horizontalRule
}

struct RichEditorCommandToken: Equatable {
    let id = UUID()
    let command: RichEditorCommand
}

@MainActor
private final class MarkdownPageTextView: NSTextView {
    private var maximumPageWidth: CGFloat = DocumentStyle.appDefault.maxPageWidth
    private var pageHorizontalPadding: CGFloat = DocumentStyle.appDefault.pageHorizontalPadding
    private var sourceIsVisible = false

    func configurePage(style: DocumentStyle, showsSource: Bool) {
        maximumPageWidth = style.maxPageWidth
        pageHorizontalPadding = style.pageHorizontalPadding
        sourceIsVisible = showsSource
        updateResponsiveInsets()
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateResponsiveInsets()
    }

    override func draw(_ dirtyRect: NSRect) {
        if !sourceIsVisible {
            let page = pageRect
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.shadowColor.withAlphaComponent(0.16)
            shadow.shadowBlurRadius = 12
            shadow.shadowOffset = NSSize(width: 0, height: -2)
            shadow.set()
            NSColor.textBackgroundColor.setFill()
            NSBezierPath(roundedRect: page, xRadius: 12, yRadius: 12).fill()
            NSGraphicsContext.restoreGraphicsState()

            NSColor.separatorColor.withAlphaComponent(0.52).setStroke()
            let border = NSBezierPath(roundedRect: page.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
            border.lineWidth = 1
            border.stroke()
        }
        super.draw(dirtyRect)
    }

    private var pageRect: NSRect {
        let sideMargin: CGFloat = 12
        let available = max(0, bounds.width - sideMargin * 2)
        let width = min(maximumPageWidth, available)
        return NSRect(x: (bounds.width - width) / 2, y: 6, width: width, height: max(0, bounds.height - 12))
    }

    private func updateResponsiveInsets() {
        if sourceIsVisible {
            if textContainerInset != NSSize(width: 12, height: 18) {
                textContainerInset = NSSize(width: 12, height: 18)
            }
            return
        }
        let page = pageRect
        let horizontal = max(12, page.minX + min(pageHorizontalPadding, max(12, page.width * 0.2)))
        let inset = NSSize(width: horizontal, height: 30)
        if textContainerInset != inset { textContainerInset = inset }
    }
}

/// A source-backed Markdown editor. `NSTextView.string` and `markdown` always contain
/// the same raw source; Page mode is implemented exclusively with temporary TextKit
/// attributes and never by round-tripping an attributed document through a serializer.
struct RichMarkdownEditor: NSViewRepresentable {
    @Binding var markdown: String
    let command: RichEditorCommandToken?
    let style: DocumentStyle
    let showsSource: Bool

    init(
        markdown: Binding<String>,
        command: RichEditorCommandToken?,
        style: DocumentStyle = .appDefault,
        showsSource: Bool = false
    ) {
        _markdown = markdown
        self.command = command
        self.style = style
        self.showsSource = showsSource
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(markdown: $markdown, style: style, showsSource: showsSource)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = MarkdownPageTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.drawsBackground = false
        textView.insertionPointColor = .labelColor
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        textView.configurePage(style: style, showsSource: showsSource)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 0
        textView.string = markdown
        textView.setAccessibilityLabel(showsSource ? "Markdown source" : "Document page")

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.lastRenderedMarkdown = markdown
        context.coordinator.requestPresentation(
            to: textView,
            preservingViewport: false,
            configurationChanged: true
        )
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        coordinator.markdown = $markdown
        coordinator.scrollView = scrollView
        textView.insertionPointColor = .labelColor

        let resolvedStyle = MarkdownEditorPresentationStyle(style)
        let presentationChanged = resolvedStyle != coordinator.style || showsSource != coordinator.showsSource
        coordinator.style = resolvedStyle
        coordinator.showsSource = showsSource
        (textView as? MarkdownPageTextView)?.configurePage(style: style, showsSource: showsSource)
        textView.setAccessibilityLabel(showsSource ? "Markdown source" : "Document page")

        if !MarkdownSourceIdentity.exactlyEqual(textView.string, markdown) {
            coordinator.replaceFromBinding(markdown, in: textView)
        } else if presentationChanged {
            coordinator.requestPresentation(
                to: textView,
                preservingViewport: true,
                configurationChanged: true
            )
        }

        if let command, command.id != coordinator.lastCommandID {
            coordinator.lastCommandID = command.id
            coordinator.apply(command.command, to: textView)
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        coordinator.cancelPendingPresentation()
        MarkdownEditorStatePurger.purge(textView)
        textView.delegate = nil
        coordinator.textView = nil
        coordinator.scrollView = nil
        coordinator.lastRenderedMarkdown = ""
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var markdown: Binding<String>
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        var lastRenderedMarkdown = ""
        var lastCommandID: UUID?
        var style: MarkdownEditorPresentationStyle
        var showsSource: Bool

        private var isProgrammaticChange = false
        private var lastActiveParagraph = NSRange(location: NSNotFound, length: 0)
        private var pendingPresentation: Task<Void, Never>?
        private var hasSemanticPresentation = false

        /// Small and typical notes update their semantic styling inline. Long
        /// documents debounce the expensive full TextKit pass so typing and
        /// Page/Markdown switching remain responsive.
        private static let immediatePresentationUTF16Length = 32_000
        private static let presentationDebounceNanoseconds: UInt64 = 120_000_000

        init(markdown: Binding<String>, style: DocumentStyle, showsSource: Bool) {
            self.markdown = markdown
            self.style = MarkdownEditorPresentationStyle(style)
            self.showsSource = showsSource
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticChange, let textView = notification.object as? NSTextView else { return }
            // TextKit's plain string is the persistence format. Presentation attributes
            // are intentionally ignored so unknown Markdown survives byte-for-byte.
            let source = textView.string
            lastRenderedMarkdown = source
            if !MarkdownSourceIdentity.exactlyEqual(markdown.wrappedValue, source) { markdown.wrappedValue = source }
            requestPresentation(to: textView, preservingViewport: true, configurationChanged: false)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !showsSource,
                  !isProgrammaticChange,
                  let textView = notification.object as? NSTextView else { return }
            let paragraph = activeParagraphRange(in: textView)
            guard paragraph != lastActiveParagraph else { return }
            lastActiveParagraph = paragraph
            requestPresentation(to: textView, preservingViewport: true, configurationChanged: false)
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let isAllowed: Bool
            if let url = link as? URL {
                isAllowed = ExternalLinkPolicy.allows(url)
            } else if let destination = link as? String {
                isAllowed = ExternalLinkPolicy.allows(destination)
            } else {
                isAllowed = false
            }
            // Consume unsafe or unknown destinations. AppKit may open only the
            // shared allowlist (http, https, and mailto).
            return !isAllowed
        }

        func replaceFromBinding(_ source: String, in textView: NSTextView) {
            guard let delta = MarkdownTextDelta.between(textView.string, and: source),
                  let storage = textView.textStorage else { return }
            let selection = delta.mapping(textView.selectedRange())
            let viewport = scrollView?.contentView.bounds.origin

            isProgrammaticChange = true
            let undoManager = textView.undoManager
            undoManager?.disableUndoRegistration()
            storage.replaceCharacters(in: delta.range, with: delta.replacement)
            undoManager?.enableUndoRegistration()
            textView.setSelectedRange(clamped(selection, to: storage.length))
            lastRenderedMarkdown = source
            isProgrammaticChange = false
            requestPresentation(to: textView, preservingViewport: true, configurationChanged: false)

            if let viewport { restoreViewport(viewport, in: textView) }
        }

        func apply(_ command: RichEditorCommand, to textView: NSTextView) {
            let originalSource = textView.string
            let originalSelection = textView.selectedRange()
            let result = MarkdownSourceCommandTransformer.applying(
                command,
                to: originalSource,
                selection: originalSelection
            )
            guard !MarkdownSourceIdentity.exactlyEqual(result.source, originalSource),
                  let delta = MarkdownTextDelta.between(originalSource, and: result.source),
                  textView.shouldChangeText(in: delta.range, replacementString: delta.replacement),
                  let storage = textView.textStorage else {
                textView.window?.makeFirstResponder(textView)
                return
            }

            let viewport = scrollView?.contentView.bounds.origin
            isProgrammaticChange = true
            storage.replaceCharacters(in: delta.range, with: delta.replacement)
            textView.setSelectedRange(clamped(result.selection, to: storage.length))
            textView.didChangeText()
            lastRenderedMarkdown = result.source
            if !MarkdownSourceIdentity.exactlyEqual(markdown.wrappedValue, result.source) {
                markdown.wrappedValue = result.source
            }
            isProgrammaticChange = false
            requestPresentation(to: textView, preservingViewport: true, configurationChanged: false)

            if let viewport { restoreViewport(viewport, in: textView) }
            textView.window?.makeFirstResponder(textView)
        }

        func applyPresentation(
            to textView: NSTextView,
            preservingViewport: Bool,
            includesSemantics: Bool = true
        ) {
            guard let storage = textView.textStorage, !textView.hasMarkedText() else { return }
            let selection = clamped(textView.selectedRange(), to: storage.length)
            let viewport = preservingViewport ? scrollView?.contentView.bounds.origin : nil
            let isActivelyEditing = textView.window?.firstResponder === textView
            let activeParagraph = showsSource || !isActivelyEditing ? nil : activeParagraphRange(in: textView)
            lastActiveParagraph = activeParagraph ?? NSRange(location: NSNotFound, length: 0)

            isProgrammaticChange = true
            MarkdownSourcePresentation.apply(
                to: storage,
                style: style,
                showsSource: showsSource,
                activeParagraphRange: activeParagraph,
                includesSemantics: includesSemantics
            )
            hasSemanticPresentation = !showsSource
                && includesSemantics
                && storage.length <= MarkdownSourcePresentation.maximumParsedUTF16Length
            textView.setSelectedRange(selection)
            textView.typingAttributes = [
                .font: showsSource ? style.sourceFont : style.bodyFont,
                .foregroundColor: NSColor.labelColor,
            ]
            isProgrammaticChange = false

            if let viewport { restoreViewport(viewport, in: textView) }
        }

        func requestPresentation(
            to textView: NSTextView,
            preservingViewport: Bool,
            configurationChanged: Bool
        ) {
            pendingPresentation?.cancel()
            pendingPresentation = nil
            guard let storage = textView.textStorage, !textView.hasMarkedText() else { return }

            if showsSource {
                if configurationChanged {
                    applyPresentation(
                        to: textView,
                        preservingViewport: preservingViewport,
                        includesSemantics: false
                    )
                }
                return
            }

            if storage.length > MarkdownSourcePresentation.maximumParsedUTF16Length {
                if configurationChanged || hasSemanticPresentation {
                    applyPresentation(
                        to: textView,
                        preservingViewport: preservingViewport,
                        includesSemantics: false
                    )
                }
                return
            }

            if storage.length <= Self.immediatePresentationUTF16Length {
                applyPresentation(to: textView, preservingViewport: preservingViewport)
                return
            }

            // Apply the selected typeface and layout immediately when modes or
            // settings change. Semantic Markdown styling follows once editing
            // has been idle briefly; rapid keystrokes continuously cancel it.
            if configurationChanged {
                applyPresentation(
                    to: textView,
                    preservingViewport: preservingViewport,
                    includesSemantics: false
                )
            }

            let expectedSource = textView.string
            pendingPresentation = Task { @MainActor [weak self, weak textView] in
                do {
                    try await Task.sleep(nanoseconds: Self.presentationDebounceNanoseconds)
                } catch {
                    return
                }
                guard !Task.isCancelled,
                      let self,
                      let textView,
                      !self.showsSource,
                      MarkdownSourceIdentity.exactlyEqual(textView.string, expectedSource) else { return }
                self.applyPresentation(to: textView, preservingViewport: preservingViewport)
                self.pendingPresentation = nil
            }
        }

        func cancelPendingPresentation() {
            pendingPresentation?.cancel()
            pendingPresentation = nil
        }

        private func activeParagraphRange(in textView: NSTextView) -> NSRange {
            let source = textView.string as NSString
            guard source.length > 0 else { return NSRange(location: 0, length: 0) }
            let location = min(textView.selectedRange().location, source.length - 1)
            return source.lineRange(for: NSRange(location: location, length: 0))
        }

        private func restoreViewport(_ origin: NSPoint, in textView: NSTextView) {
            guard let scrollView else { return }
            if let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
                layoutManager.ensureLayout(for: textContainer)
            }
            let documentHeight = textView.bounds.height
            let viewportHeight = scrollView.contentView.bounds.height
            let maximumY = max(0, documentHeight - viewportHeight)
            scrollView.contentView.scroll(to: NSPoint(x: max(0, origin.x), y: min(max(0, origin.y), maximumY)))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func clamped(_ range: NSRange, to length: Int) -> NSRange {
            let location = max(0, min(range.location, length))
            return NSRange(location: location, length: max(0, min(range.length, length - location)))
        }
    }
}

@MainActor
enum MarkdownEditorStatePurger {
    /// An editor can contain decrypted Vault text. Clear the view and its undo
    /// history whenever SwiftUI dismantles it so note switches and Vault locks
    /// cannot leave plaintext recoverable through the window's Undo command.
    static func purge(_ textView: NSTextView) {
        textView.breakUndoCoalescing()
        textView.undoManager?.removeAllActions()
        textView.textStorage?.setAttributedString(NSAttributedString())
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.typingAttributes = [:]
    }
}

struct RichFormattingBar: View {
    let send: (RichEditorCommand) -> Void
    @State private var showingLink = false
    @State private var linkDestination = "https://"

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Formatting")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Stored as Markdown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ViewThatFits(in: .horizontal) {
                expandedControls
                compactControls
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.25))
    }

    private var expandedControls: some View {
        HStack(spacing: 8) {
            styleMenu
            Divider().frame(height: 26)
            formatButton("Bold", symbol: AppIcon.Editing.bold, command: .bold)
            formatButton("Italic", symbol: AppIcon.Editing.italic, command: .italic)
            formatButton("Strike", symbol: "strikethrough", command: .strikethrough)
            formatButton("Code", symbol: "chevron.left.forwardslash.chevron.right", command: .inlineCode)
            Divider().frame(height: 26)
            listMenu
            insertMenu
            linkButton
        }
        .padding(.vertical, 1)
    }

    private var compactControls: some View {
        HStack(spacing: 7) {
            styleMenu
            Menu {
                Button("Bold") { send(.bold) }
                Button("Italic") { send(.italic) }
                Button("Strikethrough") { send(.strikethrough) }
                Button("Inline Code") { send(.inlineCode) }
            } label: {
                Image(systemName: "textformat")
                    .frame(minWidth: 24, minHeight: 26)
            }
            .menuStyle(.borderlessButton)
            .help("Text formatting")
            .accessibilityLabel("Text formatting")
            listMenu
            insertMenu
            linkButton
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var styleMenu: some View {
        Menu {
            Button("Body") { send(.body) }
            Divider()
            Button("Heading 1") { send(.heading1) }
            Button("Heading 2") { send(.heading2) }
            Button("Heading 3") { send(.heading3) }
            Button("Heading 4") { send(.heading4) }
            Button("Heading 5") { send(.heading5) }
            Button("Heading 6") { send(.heading6) }
        } label: {
            Label("Style", systemImage: AppIcon.Editing.textStyle)
                .frame(minHeight: 26)
        }
        .menuStyle(.borderlessButton)
        .controlSize(.regular)
        .padding(.horizontal, 8)
        .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 7))
        .help("Paragraph style")
    }

    private var listMenu: some View {
        Menu {
            Button("Bulleted List") { send(.bulletList) }
            Button("Numbered List") { send(.numberedList) }
            Button("Checklist") { send(.checklist) }
        } label: {
            Image(systemName: AppIcon.Editing.bulletedList)
                .frame(minWidth: 24, minHeight: 26)
        }
        .menuStyle(.borderlessButton)
        .help("Lists")
        .accessibilityLabel("List formatting")
    }

    private var insertMenu: some View {
        Menu {
            Button("Block Quote") { send(.blockquote) }
            Button("Code Block") { send(.fencedCode) }
            Button("Horizontal Rule") { send(.horizontalRule) }
        } label: {
            Image(systemName: "plus")
                .frame(minWidth: 24, minHeight: 26)
        }
        .menuStyle(.borderlessButton)
        .help("Insert Markdown block")
        .accessibilityLabel("Insert Markdown block")
    }

    private func formatButton(_ help: String, symbol: String, command: RichEditorCommand) -> some View {
        Button { send(command) } label: {
            Image(systemName: symbol)
                .frame(minWidth: 24, minHeight: 26)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .help(help)
        .accessibilityLabel(help)
    }

    private var linkButton: some View {
        Button { showingLink.toggle() } label: {
            Image(systemName: AppIcon.Editing.link)
                .frame(minWidth: 24, minHeight: 26)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .help("Add Link")
        .accessibilityLabel("Add Link")
        .popover(isPresented: $showingLink) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Link destination").font(.headline)
                TextField("https://example.com", text: $linkDestination)
                    .frame(width: 260)
                    .onSubmit { applyLink() }
                HStack {
                    Spacer()
                    Button("Cancel") { showingLink = false }
                        .keyboardShortcut(.cancelAction)
                    Button("Apply") { applyLink() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!ExternalLinkPolicy.allows(linkDestination))
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(14)
        }
    }

    private func applyLink() {
        guard ExternalLinkPolicy.allows(linkDestination) else { return }
        send(.link(linkDestination))
        showingLink = false
    }
}
