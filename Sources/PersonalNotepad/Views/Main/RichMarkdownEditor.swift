import AppKit
import SwiftUI

enum RichEditorCommand: Equatable {
    case bold
    case italic
    case underline
    case body
    case heading1
    case heading2
    case bulletList
    case numberedList
    case link(String)
}

struct RichEditorCommandToken: Equatable {
    let id = UUID()
    let command: RichEditorCommand
}

struct RichMarkdownEditor: NSViewRepresentable {
    @Binding var markdown: String
    let command: RichEditorCommandToken?

    func makeCoordinator() -> Coordinator {
        Coordinator(markdown: $markdown)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = NSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        // Untrusted note text must not become an activatable file, FTP, or
        // custom-scheme URL outside the shared external-link allowlist.
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.drawsBackground = false
        textView.insertionPointColor = .labelColor
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        textView.textContainerInset = NSSize(width: 8, height: 14)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.typingAttributes = [
            .font: MarkdownRichTextCodec.bodyFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: MarkdownRichTextCodec.bodyParagraphStyle()
        ]
        textView.setAccessibilityLabel("Formatted note body")
        textView.textStorage?.setAttributedString(MarkdownRichTextCodec.attributedString(from: markdown))
        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.lastRenderedMarkdown = markdown
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.markdown = $markdown
        textView.insertionPointColor = .labelColor

        if context.coordinator.lastRenderedMarkdown != markdown {
            let selection = textView.selectedRange()
            textView.textStorage?.setAttributedString(MarkdownRichTextCodec.attributedString(from: markdown))
            textView.setSelectedRange(NSRange(location: min(selection.location, textView.string.utf16.count), length: 0))
            context.coordinator.lastRenderedMarkdown = markdown
        }

        if let command, command.id != context.coordinator.lastCommandID {
            context.coordinator.lastCommandID = command.id
            context.coordinator.apply(command.command, to: textView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var markdown: Binding<String>
        weak var textView: NSTextView?
        var lastRenderedMarkdown = ""
        var lastCommandID: UUID?

        init(markdown: Binding<String>) {
            self.markdown = markdown
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            synchronize(textView)
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
            // Returning true consumes unsafe/unknown links; false lets AppKit
            // perform its normal action only for an allowlisted destination.
            return !isAllowed
        }

        func apply(_ command: RichEditorCommand, to textView: NSTextView) {
            switch command {
            case .bold:
                toggleFontTrait(.boldFontMask, symbolicTrait: .bold, in: textView)
            case .italic:
                toggleItalic(in: textView)
            case .underline:
                toggleUnderline(in: textView)
            case .body:
                applyParagraphFont(MarkdownRichTextCodec.bodyFont, to: textView)
            case .heading1:
                applyParagraphFont(MarkdownRichTextCodec.readingFont(ofSize: 26, weight: .bold), to: textView)
            case .heading2:
                applyParagraphFont(MarkdownRichTextCodec.readingFont(ofSize: 22, weight: .bold), to: textView)
            case .bulletList:
                toggleList(prefix: "•\t", matching: #"^(?:•[\t ]|[-*] )"#, in: textView)
            case .numberedList:
                toggleList(prefix: "1.\t", matching: #"^\d+\.[\t ]"#, in: textView)
            case .link(let destination):
                applyLink(destination, to: textView)
            }
            textView.didChangeText()
            synchronize(textView)
            textView.window?.makeFirstResponder(textView)
        }

        private func synchronize(_ textView: NSTextView) {
            let updated = MarkdownRichTextCodec.markdown(from: textView.attributedString())
            lastRenderedMarkdown = updated
            if markdown.wrappedValue != updated { markdown.wrappedValue = updated }
        }

        private func applyParagraphFont(_ font: NSFont, to textView: NSTextView) {
            let range = (textView.string as NSString).lineRange(for: textView.selectedRange())
            textView.textStorage?.addAttribute(.font, value: font, range: range)
            textView.typingAttributes[.font] = font
        }

        private func toggleFontTrait(
            _ fontTrait: NSFontTraitMask,
            symbolicTrait: NSFontDescriptor.SymbolicTraits,
            in textView: NSTextView
        ) {
            guard let storage = textView.textStorage else { return }
            let selection = textView.selectedRange()
            if selection.length == 0 {
                let current = textView.typingAttributes[.font] as? NSFont ?? MarkdownRichTextCodec.bodyFont
                let hasTrait = current.fontDescriptor.symbolicTraits.contains(symbolicTrait)
                textView.typingAttributes[.font] = hasTrait
                    ? NSFontManager.shared.convert(current, toNotHaveTrait: fontTrait)
                    : NSFontManager.shared.convert(current, toHaveTrait: fontTrait)
                return
            }

            var everyRunHasTrait = true
            storage.enumerateAttribute(.font, in: selection) { value, _, _ in
                let font = value as? NSFont ?? MarkdownRichTextCodec.bodyFont
                if !font.fontDescriptor.symbolicTraits.contains(symbolicTrait) { everyRunHasTrait = false }
            }
            storage.enumerateAttribute(.font, in: selection) { value, range, _ in
                let font = value as? NSFont ?? MarkdownRichTextCodec.bodyFont
                let converted = everyRunHasTrait
                    ? NSFontManager.shared.convert(font, toNotHaveTrait: fontTrait)
                    : NSFontManager.shared.convert(font, toHaveTrait: fontTrait)
                storage.addAttribute(.font, value: converted, range: range)
            }
        }

        private func toggleItalic(in textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let selection = textView.selectedRange()
            if selection.length == 0 {
                var attributes = textView.typingAttributes
                let font = attributes[.font] as? NSFont ?? MarkdownRichTextCodec.bodyFont
                let obliqueness = (attributes[.obliqueness] as? NSNumber)?.doubleValue ?? 0
                let isItalic = font.fontDescriptor.symbolicTraits.contains(.italic) || abs(obliqueness) > 0.001
                if isItalic {
                    attributes[.font] = NSFontManager.shared.convert(font, toNotHaveTrait: .italicFontMask)
                    attributes.removeValue(forKey: .obliqueness)
                } else {
                    let italicFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                    if italicFont.fontDescriptor.symbolicTraits.contains(.italic) {
                        attributes[.font] = italicFont
                    } else {
                        attributes[.obliqueness] = MarkdownRichTextCodec.italicObliqueness
                    }
                }
                textView.typingAttributes = attributes
                return
            }

            var everyRunIsItalic = true
            storage.enumerateAttributes(in: selection) { attributes, _, _ in
                let font = attributes[.font] as? NSFont ?? MarkdownRichTextCodec.bodyFont
                let obliqueness = (attributes[.obliqueness] as? NSNumber)?.doubleValue ?? 0
                if !font.fontDescriptor.symbolicTraits.contains(.italic) && abs(obliqueness) <= 0.001 {
                    everyRunIsItalic = false
                }
            }
            storage.enumerateAttributes(in: selection) { attributes, range, _ in
                let font = attributes[.font] as? NSFont ?? MarkdownRichTextCodec.bodyFont
                if everyRunIsItalic {
                    storage.addAttribute(
                        .font,
                        value: NSFontManager.shared.convert(font, toNotHaveTrait: .italicFontMask),
                        range: range
                    )
                    storage.removeAttribute(.obliqueness, range: range)
                } else {
                    let italicFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                    if italicFont.fontDescriptor.symbolicTraits.contains(.italic) {
                        storage.addAttribute(.font, value: italicFont, range: range)
                        storage.removeAttribute(.obliqueness, range: range)
                    } else {
                        storage.addAttribute(
                            .obliqueness,
                            value: MarkdownRichTextCodec.italicObliqueness,
                            range: range
                        )
                    }
                }
            }
        }

        private func toggleUnderline(in textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let selection = textView.selectedRange()
            if selection.length == 0 {
                let current = textView.typingAttributes[.underlineStyle] as? Int ?? 0
                textView.typingAttributes[.underlineStyle] = current == 0 ? NSUnderlineStyle.single.rawValue : 0
                return
            }
            var everyRunUnderlined = true
            storage.enumerateAttribute(.underlineStyle, in: selection) { value, _, _ in
                if (value as? Int ?? 0) == 0 { everyRunUnderlined = false }
            }
            storage.addAttribute(
                .underlineStyle,
                value: everyRunUnderlined ? 0 : NSUnderlineStyle.single.rawValue,
                range: selection
            )
        }

        private func applyLink(_ destination: String, to textView: NSTextView) {
            guard MarkdownRichTextCodec.isSafeLink(destination), let url = URL(string: destination) else { return }
            let selection = textView.selectedRange()
            if selection.length == 0 {
                let linked = NSAttributedString(
                    string: destination,
                    attributes: [.link: url, .foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
                )
                textView.textStorage?.insert(linked, at: selection.location)
                textView.setSelectedRange(NSRange(location: selection.location + linked.length, length: 0))
            } else {
                textView.textStorage?.addAttributes(
                    [.link: url, .foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue],
                    range: selection
                )
            }
        }

        private func toggleList(prefix: String, matching pattern: String, in textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let fullString = textView.string as NSString
            let selectedLines = fullString.lineRange(for: textView.selectedRange())
            var lines: [(location: Int, prefixRange: NSRange?)] = []
            var cursor = selectedLines.location

            while cursor < NSMaxRange(selectedLines) {
                let lineRange = fullString.lineRange(for: NSRange(location: cursor, length: 0))
                let line = fullString.substring(with: lineRange)
                let localRange = (line as NSString).range(of: pattern, options: .regularExpression)
                let prefixRange = localRange.location == NSNotFound ? nil : NSRange(
                    location: lineRange.location + localRange.location,
                    length: localRange.length
                )
                lines.append((lineRange.location, prefixRange))
                cursor = NSMaxRange(lineRange)
            }

            let allMatching = !lines.isEmpty && lines.allSatisfy { item in
                guard let prefixRange = item.prefixRange else { return false }
                return fullString.substring(with: prefixRange).hasPrefix(String(prefix.first!))
            }

            for line in lines.reversed() {
                if let range = line.prefixRange { storage.deleteCharacters(in: range) }
                if !allMatching {
                    storage.insert(NSAttributedString(string: prefix, attributes: textView.typingAttributes), at: line.location)
                }
            }
        }
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
                controls(compact: false)
                controls(compact: true)
                condensedControls
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.25))
    }

    private func controls(compact: Bool) -> some View {
        HStack(spacing: 8) {
            styleMenu(compact: compact)

            Divider().frame(height: 26)
            formatButton("Bold", symbol: AppIcon.Editing.bold, command: .bold, compact: compact)
            formatButton("Italic", symbol: AppIcon.Editing.italic, command: .italic, compact: compact)
            formatButton("Underline", symbol: AppIcon.Editing.underline, command: .underline, compact: compact)
            Divider().frame(height: 26)
            formatButton("Bullets", symbol: AppIcon.Editing.bulletedList, command: .bulletList, compact: compact)
            formatButton("Numbers", symbol: AppIcon.Editing.numberedList, command: .numberedList, compact: compact)
            linkButton(compact: compact)
        }
        .padding(.vertical, 1)
    }

    private var condensedControls: some View {
        HStack(spacing: 7) {
            styleMenu(compact: true)

            Menu {
                Button("Bold") { send(.bold) }
                Button("Italic") { send(.italic) }
                Button("Underline") { send(.underline) }
            } label: {
                Image(systemName: "textformat")
                    .frame(minWidth: 24, minHeight: 26)
            }
            .menuStyle(.borderlessButton)
            .help("Bold, italic, and underline")
            .accessibilityLabel("Text formatting")

            Menu {
                Button("Bulleted List") { send(.bulletList) }
                Button("Numbered List") { send(.numberedList) }
            } label: {
                Image(systemName: AppIcon.Editing.bulletedList)
                    .frame(minWidth: 24, minHeight: 26)
            }
            .menuStyle(.borderlessButton)
            .help("Bulleted and numbered lists")
            .accessibilityLabel("List formatting")

            linkButton(compact: true)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func styleMenu(compact: Bool) -> some View {
        Menu {
            Button("Body") { send(.body) }
            Button("Heading 1") { send(.heading1) }
            Button("Heading 2") { send(.heading2) }
        } label: {
            Label(compact ? "Style" : "Text Style", systemImage: AppIcon.Editing.textStyle)
                .frame(minHeight: 26)
        }
        .menuStyle(.borderlessButton)
        .controlSize(.regular)
        .padding(.horizontal, 8)
        .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 7))
        .help("Paragraph style")
    }

    private func formatButton(
        _ help: String,
        symbol: String,
        command: RichEditorCommand,
        compact: Bool
    ) -> some View {
        Button { send(command) } label: {
            if compact {
                Image(systemName: symbol)
                    .frame(minWidth: 24, minHeight: 26)
            } else {
                Label(help, systemImage: symbol)
                    .frame(minHeight: 26)
            }
        }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .help(help)
            .accessibilityLabel(help)
    }

    private func linkButton(compact: Bool) -> some View {
        Button { showingLink.toggle() } label: {
            if compact {
                Image(systemName: AppIcon.Editing.link)
                    .frame(minWidth: 24, minHeight: 26)
            } else {
                Label("Link", systemImage: AppIcon.Editing.link)
                    .frame(minHeight: 26)
            }
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
                        .disabled(!MarkdownRichTextCodec.isSafeLink(linkDestination))
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(14)
        }
    }

    private func applyLink() {
        guard MarkdownRichTextCodec.isSafeLink(linkDestination) else { return }
        send(.link(linkDestination))
        showingLink = false
    }
}
