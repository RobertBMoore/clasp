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

struct MarkdownPageAccessibilityAnnotation: Equatable {
    let range: NSRange
    let label: String
}

@MainActor
private final class MarkdownChecklistButton: NSButton {
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.isEmpty, event.charactersIgnoringModifiers == " " {
            performClick(nil)
            return
        }
        super.keyDown(with: event)
    }
}

@MainActor
final class MarkdownPageTextView: NSTextView {
    private var maximumPageWidth: CGFloat = DocumentStyle.appDefault.maxPageWidth
    private var pageHorizontalPadding: CGFloat = DocumentStyle.appDefault.pageHorizontalPadding
    private var sourceIsVisible = false
    private var blockDecorations: [MarkdownPageBlockDecoration] = []
    private var checklistDecorations: [MarkdownPageChecklistDecoration] = []
    private var checklistButtons: [Int: NSButton] = [:]
    private weak var observedClipView: NSClipView?
    private var isLayingOutChecklistControls = false

    /// Coordinator-owned mutation boundary. The view contributes only the
    /// analyzer-validated state range represented by the activated control.
    var checklistToggleHandler: ((NSRange) -> Bool)?

    func configurePage(style: DocumentStyle, showsSource: Bool) {
        maximumPageWidth = style.maxPageWidth
        pageHorizontalPadding = style.pageHorizontalPadding
        sourceIsVisible = showsSource
        if showsSource {
            checklistDecorations = []
            removeChecklistButtons()
        }
        updateResponsiveInsets()
        needsLayout = true
        needsDisplay = true
    }

    func updateBlockDecorations(_ decorations: [MarkdownPageBlockDecoration]) {
        blockDecorations = sourceIsVisible
            ? []
            : decorations.sorted { $0.range.location < $1.range.location }
        needsDisplay = true
    }

    func updateChecklistDecorations(_ decorations: [MarkdownPageChecklistDecoration]) {
        checklistDecorations = sourceIsVisible
            ? []
            : decorations.sorted { $0.stateRange.location < $1.stateRange.location }
        synchronizeScrollObservation()
        layoutChecklistControls()
    }

    /// Exposed internally for focused TextKit/accessibility regression tests.
    var visibleChecklistControls: [NSButton] {
        checklistButtons.values.sorted { $0.tag < $1.tag }
    }

    var presentedChecklistDecorations: [MarkdownPageChecklistDecoration] {
        checklistDecorations
    }

    func refreshVisibleChecklistControls() {
        synchronizeScrollObservation()
        layoutChecklistControls()
    }

    func accessibilityBlockAnnotations(for requestedRange: NSRange) -> [MarkdownPageAccessibilityAnnotation] {
        guard !sourceIsVisible, requestedRange.length > 0 else { return [] }
        return Self.blockDecorations(blockDecorations, intersecting: requestedRange).map { decoration in
            let intersection = NSIntersectionRange(decoration.range, requestedRange)
            let label: String
            switch decoration.kind {
            case .fencedCode: label = "Code block"
            case .thematicBreak: label = "Separator"
            case .table: label = "Table"
            }
            return MarkdownPageAccessibilityAnnotation(
                range: NSRange(
                    location: intersection.location - requestedRange.location,
                    length: intersection.length
                ),
                label: label
            )
        }
    }

    func accessibilityChecklistMarkerRanges(for requestedRange: NSRange) -> [NSRange] {
        guard !sourceIsVisible, requestedRange.length > 0 else { return [] }
        return checklistDecorations.compactMap { decoration in
            let intersection = NSIntersectionRange(decoration.markerRange, requestedRange)
            guard intersection.length > 0 else { return nil }
            return NSRange(
                location: intersection.location - requestedRange.location,
                length: intersection.length
            )
        }
    }

    override func accessibilityAttributedString(for range: NSRange) -> NSAttributedString? {
        let value = super.accessibilityAttributedString(for: range)
        guard !sourceIsVisible, let value else { return value }
        let accessibleValue = NSMutableAttributedString(attributedString: value)
        for annotation in accessibilityBlockAnnotations(for: range)
        where NSMaxRange(annotation.range) <= accessibleValue.length {
            accessibleValue.addAttribute(
                .accessibilityCustomText,
                value: [annotation.label],
                range: annotation.range
            )
        }
        for markerRange in accessibilityChecklistMarkerRanges(for: range)
        where NSMaxRange(markerRange) <= accessibleValue.length {
            // The adjacent native checkbox exposes role, state, and task label.
            // Suppress the duplicate source punctuation from VoiceOver in Page
            // mode without changing the text storage or accessibility ranges.
            accessibleValue.addAttribute(
                .accessibilityCustomText,
                value: [""],
                range: markerRange
            )
        }
        return accessibleValue
    }

    override func accessibilityChildren() -> [Any]? {
        var children = super.accessibilityChildren() ?? []
        guard !sourceIsVisible else { return children }
        for button in visibleChecklistControls where !children.contains(where: {
            ($0 as AnyObject) === button
        }) {
            children.append(button)
        }
        return children
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        synchronizeScrollObservation()
        needsLayout = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        synchronizeScrollObservation()
        needsLayout = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateResponsiveInsets()
        needsLayout = true
        layoutChecklistControls()
    }

    override func layout() {
        super.layout()
        layoutChecklistControls()
    }

    override func draw(_ dirtyRect: NSRect) {
        if !sourceIsVisible {
            let page = pageRect
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.shadowColor.withAlphaComponent(0.16)
            shadow.shadowBlurRadius = ClaspDesign.Metrics.editorPageShadowRadius
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.set()
            NSColor.textBackgroundColor.setFill()
            NSBezierPath(
                roundedRect: page,
                xRadius: ClaspDesign.Metrics.editorPageCornerRadius,
                yRadius: ClaspDesign.Metrics.editorPageCornerRadius
            ).fill()
            NSGraphicsContext.restoreGraphicsState()

            NSColor.separatorColor.withAlphaComponent(0.52).setStroke()
            let border = NSBezierPath(
                roundedRect: page.insetBy(dx: 0.5, dy: 0.5),
                xRadius: ClaspDesign.Metrics.editorPageCornerRadius,
                yRadius: ClaspDesign.Metrics.editorPageCornerRadius
            )
            border.lineWidth = 1
            border.stroke()

            drawBlockDecorations(in: dirtyRect)
        }
        super.draw(dirtyRect)
    }

    private func drawBlockDecorations(in dirtyRect: NSRect) {
        guard !blockDecorations.isEmpty,
              let layoutManager,
              let textContainer,
              let storage = textStorage,
              storage.length > 0 else { return }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let origin = textContainerOrigin
        let page = pageRect
        let left = max(page.minX + 18, origin.x - 10)
        let right = min(page.maxX - 18, bounds.maxX - origin.x + 10)
        guard right > left else { return }

        let containerDirtyRect = dirtyRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRect: containerDirtyRect,
            in: textContainer
        )
        let visibleCharacterRange = layoutManager.characterRange(
            forGlyphRange: visibleGlyphRange,
            actualGlyphRange: nil
        )

        for decoration in Self.blockDecorations(blockDecorations, intersecting: visibleCharacterRange) {
            let location = max(0, min(decoration.range.location, storage.length))
            let range = NSRange(
                location: location,
                length: max(0, min(decoration.range.length, storage.length - location))
            )
            guard range.length > 0 else { continue }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { continue }
            var glyphBounds = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            glyphBounds.origin.x += origin.x
            glyphBounds.origin.y += origin.y

            switch decoration.kind {
            case .fencedCode:
                let rect = NSRect(
                    x: left,
                    y: max(page.minY + 10, glyphBounds.minY - 7),
                    width: right - left,
                    height: glyphBounds.height + 14
                ).intersection(page.insetBy(dx: 12, dy: 10))
                guard !rect.isEmpty, rect.intersects(dirtyRect) else { continue }
                let fill = NSColor.controlBackgroundColor.blended(
                    withFraction: 0.06,
                    of: NSColor.labelColor
                ) ?? NSColor.controlBackgroundColor
                fill.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
                NSColor.separatorColor.withAlphaComponent(0.52).setStroke()
                let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
                border.lineWidth = 1
                border.stroke()
            case .thematicBreak:
                // Page mode remains visually stable while the caret moves.
                // The exact source marker is always available in Markdown mode.
                let y = glyphBounds.midY.rounded(.toNearestOrAwayFromZero)
                let rect = NSRect(x: left, y: y, width: right - left, height: 1)
                guard rect.intersects(dirtyRect) else { continue }
                NSColor.separatorColor.withAlphaComponent(0.78).setStroke()
                let rule = NSBezierPath()
                rule.move(to: NSPoint(x: left, y: y))
                rule.line(to: NSPoint(x: right, y: y))
                rule.lineWidth = max(0.5, 1 / (window?.backingScaleFactor ?? 2))
                rule.stroke()
            case .table:
                let rect = NSRect(
                    x: left,
                    y: max(page.minY + 10, glyphBounds.minY - 6),
                    width: right - left,
                    height: glyphBounds.height + 12
                ).intersection(page.insetBy(dx: 12, dy: 10))
                guard !rect.isEmpty, rect.intersects(dirtyRect) else { continue }

                let fill = NSColor.controlBackgroundColor.blended(
                    withFraction: 0.025,
                    of: NSColor.labelColor
                ) ?? NSColor.controlBackgroundColor
                fill.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()

                if let headerRange = decoration.headerRange,
                   NSMaxRange(headerRange) <= storage.length {
                    let headerGlyphRange = layoutManager.glyphRange(
                        forCharacterRange: headerRange,
                        actualCharacterRange: nil
                    )
                    var headerBounds = layoutManager.boundingRect(forGlyphRange: headerGlyphRange, in: textContainer)
                    headerBounds.origin.x += origin.x
                    headerBounds.origin.y += origin.y
                    let headerFillRect = NSRect(
                        x: rect.minX,
                        y: rect.minY,
                        width: rect.width,
                        height: min(rect.height, max(0, headerBounds.maxY + 5 - rect.minY))
                    )
                    NSColor.selectedContentBackgroundColor.withAlphaComponent(0.075).setFill()
                    NSBezierPath(
                        roundedRect: headerFillRect,
                        xRadius: 7,
                        yRadius: 7
                    ).fill()
                    NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
                    let headerRule = NSBezierPath()
                    let y = min(rect.maxY, headerFillRect.maxY)
                    headerRule.move(to: NSPoint(x: rect.minX, y: y))
                    headerRule.line(to: NSPoint(x: rect.maxX, y: y))
                    headerRule.lineWidth = max(0.5, 1 / (window?.backingScaleFactor ?? 2))
                    headerRule.stroke()
                }

                NSColor.separatorColor.withAlphaComponent(0.6).setStroke()
                let border = NSBezierPath(
                    roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                    xRadius: 7,
                    yRadius: 7
                )
                border.lineWidth = 1
                border.stroke()
            }
        }
    }

    static func blockDecorations(
        _ decorations: [MarkdownPageBlockDecoration],
        intersecting characterRange: NSRange
    ) -> [MarkdownPageBlockDecoration] {
        guard characterRange.length > 0 else { return [] }
        var result: [MarkdownPageBlockDecoration] = []
        result.reserveCapacity(min(decorations.count, 16))
        for decoration in decorations {
            if decoration.range.location >= NSMaxRange(characterRange) { break }
            if NSIntersectionRange(decoration.range, characterRange).length > 0 {
                result.append(decoration)
            }
        }
        return result
    }

    static func checklistDecorations(
        _ decorations: [MarkdownPageChecklistDecoration],
        intersecting characterRange: NSRange
    ) -> [MarkdownPageChecklistDecoration] {
        guard characterRange.length > 0 else { return [] }
        var result: [MarkdownPageChecklistDecoration] = []
        result.reserveCapacity(min(decorations.count, 24))
        for decoration in decorations {
            if decoration.lineRange.location >= NSMaxRange(characterRange) { break }
            if NSIntersectionRange(decoration.lineRange, characterRange).length > 0 {
                result.append(decoration)
            }
        }
        return result
    }

    private func synchronizeScrollObservation() {
        let clipView = enclosingScrollView?.contentView
        guard observedClipView !== clipView else { return }
        if let observedClipView {
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.boundsDidChangeNotification,
                object: observedClipView
            )
        }
        observedClipView = clipView
        guard let clipView else { return }
        clipView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )
    }

    @objc private func clipViewBoundsDidChange(_ notification: Notification) {
        layoutChecklistControls()
    }

    @objc private func toggleChecklist(_ sender: NSButton) {
        guard let decoration = checklistDecorations.first(where: { $0.stateRange.location == sender.tag }),
              let checklistToggleHandler,
              checklistToggleHandler(decoration.stateRange) else {
            if let decoration = checklistDecorations.first(where: { $0.stateRange.location == sender.tag }) {
                sender.state = decoration.isChecked ? .on : .off
            }
            return
        }
    }

    private func layoutChecklistControls() {
        guard !isLayingOutChecklistControls else { return }
        let previousVisibleLocations = Set(checklistButtons.keys)
        isLayingOutChecklistControls = true
        defer {
            isLayingOutChecklistControls = false
            if Set(checklistButtons.keys) != previousVisibleLocations {
                NSAccessibility.post(element: self, notification: .layoutChanged)
            }
        }

        guard !sourceIsVisible,
              !checklistDecorations.isEmpty,
              let layoutManager,
              let textContainer,
              let storage = textStorage,
              storage.length > 0 else {
            removeChecklistButtons()
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let origin = textContainerOrigin
        // NSClipView bounds are already expressed in document coordinates and
        // remain valid in headless test hosts where `visibleRect` may be empty.
        let viewportRect = enclosingScrollView?.contentView.bounds ?? visibleRect
        let expandedVisibleRect = viewportRect.insetBy(dx: 0, dy: -40)
        let containerVisibleRect = expandedVisibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRect: containerVisibleRect,
            in: textContainer
        )
        let visibleCharacterRange = layoutManager.characterRange(
            forGlyphRange: visibleGlyphRange,
            actualGlyphRange: nil
        )
        let visibleDecorations = Self.checklistDecorations(
            checklistDecorations,
            intersecting: visibleCharacterRange
        ).filter {
            NSMaxRange($0.markerRange) <= storage.length
                && NSMaxRange($0.contentRange) <= storage.length
        }
        let visibleLocations = Set(visibleDecorations.map(\.stateRange.location))

        let staleLocations = checklistButtons.keys.filter { !visibleLocations.contains($0) }
        for location in staleLocations {
            checklistButtons.removeValue(forKey: location)?.removeFromSuperview()
        }

        for decoration in visibleDecorations {
            let button = checklistButtons[decoration.stateRange.location] ?? makeChecklistButton()
            button.tag = decoration.stateRange.location
            let previousState = button.state
            button.state = decoration.isChecked ? .on : .off
            button.setAccessibilityValue(NSNumber(value: decoration.isChecked))
            if previousState != button.state {
                NSAccessibility.post(element: button, notification: .valueChanged)
            }
            let taskText = (storage.string as NSString)
                .substring(with: decoration.contentRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let label = taskText.isEmpty ? "Checklist item" : taskText
            button.setAccessibilityLabel(label)
            button.setAccessibilityHelp(
                decoration.isChecked ? "Uncheck this task" : "Mark this task complete"
            )
            button.toolTip = decoration.isChecked ? "Mark as incomplete" : "Mark as complete"

            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: decoration.markerRange,
                actualCharacterRange: nil
            )
            guard glyphRange.length > 0 else {
                button.isHidden = true
                continue
            }
            let lineRect = layoutManager.lineFragmentUsedRect(
                forGlyphAt: glyphRange.location,
                effectiveRange: nil
            )
            var markerRect = layoutManager.boundingRect(
                forGlyphRange: glyphRange,
                in: textContainer
            )
            markerRect.origin.x += origin.x
            markerRect.origin.y += origin.y
            let controlSize = NSSize(width: 18, height: 18)
            button.frame = NSRect(
                x: markerRect.minX,
                y: origin.y + lineRect.minY + max(0, (lineRect.height - controlSize.height) / 2),
                width: controlSize.width,
                height: controlSize.height
            ).integral
            button.isHidden = false

            if button.superview == nil { addSubview(button) }
            checklistButtons[decoration.stateRange.location] = button
        }
    }

    private func makeChecklistButton() -> NSButton {
        let button = MarkdownChecklistButton(
            checkboxWithTitle: "",
            target: self,
            action: #selector(toggleChecklist(_:))
        )
        button.controlSize = .regular
        button.refusesFirstResponder = false
        button.setAccessibilityElement(true)
        button.setAccessibilityRole(.checkBox)
        button.setAccessibilityParent(self)
        return button
    }

    private func removeChecklistButtons() {
        for button in checklistButtons.values { button.removeFromSuperview() }
        checklistButtons.removeAll(keepingCapacity: true)
    }

    private var pageRect: NSRect {
        let sideMargin = ClaspDesign.Metrics.editorCanvasInset
        let available = max(0, bounds.width - sideMargin * 2)
        let width = min(maximumPageWidth, available)
        let topInset = ClaspDesign.Metrics.editorPageTopInset
        return NSRect(
            x: (bounds.width - width) / 2,
            y: topInset,
            width: width,
            height: max(0, bounds.height - (topInset * 2))
        )
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
        let inset = NSSize(
            width: horizontal,
            height: page.minY + ClaspDesign.Metrics.editorPageContentTopPadding
        )
        if textContainerInset != inset { textContainerInset = inset }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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
        scrollView.drawsBackground = true
        scrollView.backgroundColor = showsSource ? .textBackgroundColor : ClaspDesign.Color.editorCanvas
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
        scrollView.backgroundColor = showsSource ? .textBackgroundColor : ClaspDesign.Color.editorCanvas

        let resolvedStyle = MarkdownEditorPresentationStyle(style)
        let presentationChanged = resolvedStyle != coordinator.style || showsSource != coordinator.showsSource
        coordinator.style = resolvedStyle
        coordinator.showsSource = showsSource
        (textView as? MarkdownPageTextView)?.configurePage(style: style, showsSource: showsSource)
        textView.setAccessibilityLabel(showsSource ? "Markdown source" : "Document page")

        if !MarkdownSourceIdentity.exactlyEqual(textView.string, markdown) {
            coordinator.replaceFromBinding(markdown, in: textView)
        }
        if presentationChanged {
            coordinator.requestPresentation(
                to: textView,
                preservingViewport: true,
                configurationChanged: true
            )
        }

        if let command, command.id != coordinator.lastCommandID {
            coordinator.lastCommandID = command.id
            coordinator.schedule(command.command, id: command.id, for: textView)
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.cancelPendingCommand()
        coordinator.cancelPendingPresentation()
        guard let textView = scrollView.documentView as? NSTextView else { return }
        MarkdownEditorStatePurger.purge(textView)
        if let pageTextView = textView as? MarkdownPageTextView {
            pageTextView.checklistToggleHandler = nil
            pageTextView.updateChecklistDecorations([])
        }
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
        private var pendingCommand: Task<Void, Never>?
        private var pendingCommandID: UUID?
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
            let source = MarkdownSourceIdentity.detachedCopy(textView.string)
            lastRenderedMarkdown = source
            if !MarkdownSourceIdentity.exactlyEqual(markdown.wrappedValue, source) { markdown.wrappedValue = source }
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

        /// SwiftUI invokes `updateNSView` while reconciling view state. Publishing
        /// the command's source result through the Binding from inside that phase
        /// can let a neighboring mode update replay an older source snapshot.
        /// Yield once so TextKit and SwiftUI are changed together from the next
        /// main-actor turn, outside the representable update callback.
        func schedule(_ command: RichEditorCommand, id: UUID, for textView: NSTextView) {
            pendingCommand?.cancel()
            pendingCommandID = id
            let expectedSource = MarkdownSourceIdentity.detachedCopy(textView.string)
            let expectedSelection = textView.selectedRange()
            pendingCommand = Task { @MainActor [weak self, weak textView] in
                await Task.yield()
                guard !Task.isCancelled,
                      let self,
                      let textView,
                      self.pendingCommandID == id,
                      self.textView === textView else { return }
                self.pendingCommand = nil
                self.pendingCommandID = nil
                guard MarkdownSourceIdentity.exactlyEqual(textView.string, expectedSource),
                      textView.selectedRange() == expectedSelection else { return }
                self.apply(command, to: textView)
            }
        }

        func cancelPendingCommand() {
            pendingCommand?.cancel()
            pendingCommand = nil
            pendingCommandID = nil
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

        /// Executes a Page-mode checkbox activation through the same native
        /// TextKit edit path as keyboard typing. Only the analyzer-provided
        /// one-character state range may change.
        @discardableResult
        func toggleChecklist(at stateRange: NSRange, in textView: NSTextView) -> Bool {
            guard !showsSource else { return false }
            let originalSource = textView.string
            let originalSelection = textView.selectedRange()
            let wasChecked = MarkdownSourceAnalyzer.checklistItems(in: originalSource).first {
                NSEqualRanges($0.stateRange, stateRange)
            }?.isChecked
            guard let wasChecked else { return false }
            let result = MarkdownSourceCommandTransformer.togglingChecklist(
                in: originalSource,
                atStateRange: stateRange,
                selection: originalSelection
            )
            guard !MarkdownSourceIdentity.exactlyEqual(result.source, originalSource),
                  let delta = MarkdownTextDelta.between(originalSource, and: result.source),
                  delta.range.length == 1,
                  (delta.replacement as NSString).length == 1,
                  NSMaxRange(delta.range) <= (originalSource as NSString).length else { return false }

            let viewport = scrollView?.contentView.bounds.origin
            let originalState = (originalSource as NSString).substring(with: delta.range)
            return replaceChecklistState(
                at: delta.range,
                with: delta.replacement,
                inverseReplacement: originalState,
                selection: result.selection,
                viewport: viewport,
                actionName: wasChecked ? "Reopen Task" : "Complete Task",
                in: textView
            )
        }

        func applyPresentation(
            to textView: NSTextView,
            preservingViewport: Bool,
            includesSemantics: Bool = true
        ) {
            guard let storage = textView.textStorage, !textView.hasMarkedText() else { return }
            let viewport = preservingViewport ? scrollView?.contentView.bounds.origin : nil
            isProgrammaticChange = true
            let presentation = MarkdownSourcePresentation.applyDocument(
                to: storage,
                style: style,
                showsSource: showsSource,
                includesSemantics: includesSemantics
            )
            if let pageTextView = textView as? MarkdownPageTextView {
                pageTextView.checklistToggleHandler = { [weak self, weak textView] stateRange in
                    guard let self, let textView else { return false }
                    return self.toggleChecklist(at: stateRange, in: textView)
                }
                pageTextView.updateBlockDecorations(presentation.blockDecorations)
                pageTextView.updateChecklistDecorations(presentation.checklistDecorations)
            }
            hasSemanticPresentation = !showsSource
                && includesSemantics
                && storage.length <= MarkdownSourcePresentation.maximumParsedUTF16Length
            // Presentation is attribute-only. Resetting an unchanged selection asks
            // AppKit to reveal its active endpoint and can jump a long document to
            // the bottom while the user is highlighting text.
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
            if !configurationChanged {
                // Ranges describe the exact source revision that produced
                // them. Clear immediately after edits so a debounced long
                // document can never paint stale geometry over new text.
                (textView as? MarkdownPageTextView)?.updateBlockDecorations([])
            }
            guard let storage = textView.textStorage, !textView.hasMarkedText() else { return }

            if showsSource {
                (textView as? MarkdownPageTextView)?.updateChecklistDecorations([])
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
                (textView as? MarkdownPageTextView)?.updateChecklistDecorations([])
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
            } else {
                refreshChecklistPresentation(
                    to: textView,
                    preservingViewport: preservingViewport
                )
            }

            let expectedSource = MarkdownSourceIdentity.detachedCopy(textView.string)
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

        private func refreshChecklistPresentation(
            to textView: NSTextView,
            preservingViewport: Bool
        ) {
            guard let storage = textView.textStorage, !textView.hasMarkedText() else { return }
            let viewport = preservingViewport ? scrollView?.contentView.bounds.origin : nil
            isProgrammaticChange = true
            let decorations = MarkdownSourcePresentation.refreshChecklistPresentation(
                in: storage,
                style: style
            )
            if let pageTextView = textView as? MarkdownPageTextView {
                pageTextView.checklistToggleHandler = { [weak self, weak textView] stateRange in
                    guard let self, let textView else { return false }
                    return self.toggleChecklist(at: stateRange, in: textView)
                }
                pageTextView.updateChecklistDecorations(decorations)
            }
            isProgrammaticChange = false
            if let viewport { restoreViewport(viewport, in: textView) }
        }

        /// Checklist state uses a manual native UndoManager registration so
        /// undo/redo restores the document state without AppKit selecting the
        /// one-character edit and scrolling it into view. The source mutation
        /// itself still follows NSTextView's should/did-change contract.
        @discardableResult
        private func replaceChecklistState(
            at stateRange: NSRange,
            with replacement: String,
            inverseReplacement: String,
            selection: NSRange,
            viewport: NSPoint?,
            actionName: String,
            in textView: NSTextView
        ) -> Bool {
            guard (replacement as NSString).length == 1,
                  (inverseReplacement as NSString).length == 1,
                  let storage = textView.textStorage,
                  NSMaxRange(stateRange) <= storage.length,
                  MarkdownSourceAnalyzer.checklistItems(in: textView.string).contains(where: {
                      NSEqualRanges($0.stateRange, stateRange)
                  }) else {
                return false
            }

            let undoManager = textView.undoManager
            textView.breakUndoCoalescing()
            isProgrammaticChange = true
            undoManager?.disableUndoRegistration()
            guard textView.shouldChangeText(in: stateRange, replacementString: replacement) else {
                undoManager?.enableUndoRegistration()
                isProgrammaticChange = false
                return false
            }
            storage.replaceCharacters(in: stateRange, with: replacement)
            if textView.selectedRange() != selection {
                textView.setSelectedRange(clamped(selection, to: storage.length))
            }
            textView.didChangeText()
            undoManager?.enableUndoRegistration()

            let source = MarkdownSourceIdentity.detachedCopy(textView.string)
            lastRenderedMarkdown = source
            if !MarkdownSourceIdentity.exactlyEqual(markdown.wrappedValue, source) {
                markdown.wrappedValue = source
            }
            isProgrammaticChange = false

            if let undoManager {
                undoManager.registerUndo(withTarget: self) { [weak textView] coordinator in
                    guard let textView else { return }
                    coordinator.replaceChecklistState(
                        at: stateRange,
                        with: inverseReplacement,
                        inverseReplacement: replacement,
                        selection: selection,
                        viewport: viewport,
                        actionName: actionName,
                        in: textView
                    )
                }
                undoManager.setActionName(actionName)
            }

            requestPresentation(to: textView, preservingViewport: true, configurationChanged: false)
            if let viewport { restoreViewport(viewport, in: textView) }
            return true
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

struct RichStylePickerPlacement: Equatable {
    enum VerticalAttachment: Equatable {
        case below
        case above
        case overlapping
    }

    let frame: CGRect
    let verticalAttachment: VerticalAttachment
}

enum RichStylePickerLayout {
    static let idealSize = ClaspDesign.Metrics.paragraphStylePickerSize
    // Keeps the panel's soft elevation shadow inside the editor pane too.
    static let edgeInset = ClaspDesign.Metrics.menuEdgeInset
    static let anchorGap: CGFloat = 6
    static let minimumSeparatedHeight: CGFloat = 180

    /// Resolves a menu-like panel entirely within the editor pane. The picker
    /// prefers the space below its trigger, flips above near the bottom edge,
    /// and uses the pane's full safe height with internal scrolling when a
    /// short window cannot provide a useful detached region on either side.
    static func placement(in rawBounds: CGRect, anchoredTo rawTrigger: CGRect) -> RichStylePickerPlacement {
        guard !rawBounds.isNull,
              !rawBounds.isInfinite,
              rawBounds.width.isFinite,
              rawBounds.height.isFinite else {
            return RichStylePickerPlacement(frame: .zero, verticalAttachment: .overlapping)
        }

        let bounds = rawBounds.standardized
        let horizontalInset = min(edgeInset, bounds.width / 2)
        let verticalInset = min(edgeInset, bounds.height / 2)
        let safeBounds = CGRect(
            x: bounds.minX + horizontalInset,
            y: bounds.minY + verticalInset,
            width: max(0, bounds.width - horizontalInset * 2),
            height: max(0, bounds.height - verticalInset * 2)
        )
        guard safeBounds.width > 0, safeBounds.height > 0 else {
            return RichStylePickerPlacement(
                frame: CGRect(origin: safeBounds.origin, size: .zero),
                verticalAttachment: .overlapping
            )
        }

        let trigger = rawTrigger.isNull || rawTrigger.isInfinite
            ? CGRect(x: safeBounds.minX, y: safeBounds.minY, width: 0, height: 0)
            : rawTrigger.standardized
        let width = min(idealSize.width, safeBounds.width)
        let maximumX = safeBounds.maxX - width
        let x = min(max(trigger.minX, safeBounds.minX), maximumX)

        let belowStart = min(max(trigger.maxY + anchorGap, safeBounds.minY), safeBounds.maxY)
        let aboveEnd = min(max(trigger.minY - anchorGap, safeBounds.minY), safeBounds.maxY)
        let belowCapacity = max(0, safeBounds.maxY - belowStart)
        let aboveCapacity = max(0, aboveEnd - safeBounds.minY)

        let height: CGFloat
        let rawY: CGFloat
        let attachment: RichStylePickerPlacement.VerticalAttachment
        if belowCapacity >= idealSize.height {
            height = idealSize.height
            rawY = belowStart
            attachment = .below
        } else if aboveCapacity >= idealSize.height {
            height = idealSize.height
            rawY = aboveEnd - height
            attachment = .above
        } else if max(belowCapacity, aboveCapacity) >= minimumSeparatedHeight {
            if belowCapacity >= aboveCapacity {
                height = min(idealSize.height, belowCapacity)
                rawY = belowStart
                attachment = .below
            } else {
                height = min(idealSize.height, aboveCapacity)
                rawY = aboveEnd - height
                attachment = .above
            }
        } else {
            // Very short windows are better served by a full-height in-pane
            // sheet than by an unusably tiny detached menu. The option list is
            // a ScrollView, so every style remains reachable.
            height = min(idealSize.height, safeBounds.height)
            rawY = belowCapacity >= aboveCapacity
                ? trigger.maxY + anchorGap
                : trigger.minY - anchorGap - height
            attachment = .overlapping
        }

        let maximumY = safeBounds.maxY - height
        let y = min(max(rawY, safeBounds.minY), maximumY)
        return RichStylePickerPlacement(
            frame: CGRect(x: x, y: y, width: width, height: height),
            verticalAttachment: attachment
        )
    }
}

enum RichStylePickerCoordinateSpace {
    static let name = "clasp.note-editor-pane"
}

struct RichStylePickerTriggerFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .null

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isNull {
            value = next
        }
    }
}

struct RichFormattingBar: View {
    @Binding var isStylePickerPresented: Bool
    let stylePickerFocus: FocusState<RichStylePickerFocus?>.Binding
    let send: (RichEditorCommand) -> Void
    @State private var showingLink = false
    @State private var linkDestination = "https://"

    var body: some View {
        HStack(spacing: ClaspDesign.Metrics.editorToolbarGroupSpacing) {
            stylePicker
            ViewThatFits(in: .horizontal) {
                expandedControls
                compactControls
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, ClaspDesign.Metrics.editorToolbarHorizontalPadding)
        .padding(.vertical, ClaspDesign.Metrics.editorToolbarVerticalPadding)
        .background(ClaspDesign.Color.toolbarSurface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.separator.opacity(0.42))
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Markdown formatting")
        .onChange(of: isStylePickerPresented) { _, isPresented in
            guard !isPresented, case .option = stylePickerFocus.wrappedValue else { return }
            stylePickerFocus.wrappedValue = .trigger
        }
    }

    private var expandedControls: some View {
        HStack(spacing: ClaspDesign.Metrics.editorToolbarGroupSpacing) {
            Divider().frame(height: 20).padding(.horizontal, 2)
            formatButton("Bold", symbol: AppIcon.Editing.bold, command: .bold)
            formatButton("Italic", symbol: AppIcon.Editing.italic, command: .italic)
            formatButton("Strike", symbol: "strikethrough", command: .strikethrough)
            formatButton("Code", symbol: "chevron.left.forwardslash.chevron.right", command: .inlineCode)
            Divider().frame(height: 20).padding(.horizontal, 2)
            listMenu
            insertMenu
            linkButton
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var compactControls: some View {
        HStack(spacing: ClaspDesign.Metrics.editorToolbarGroupSpacing) {
            Menu {
                Button("Bold") { send(.bold) }
                Button("Italic") { send(.italic) }
                Button("Strikethrough") { send(.strikethrough) }
                Button("Inline Code") { send(.inlineCode) }
            } label: {
                Image(systemName: "textformat")
                    .claspToolbarControlSurface()
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

    private var stylePicker: some View {
        Button {
            if isStylePickerPresented {
                isStylePickerPresented = false
                stylePickerFocus.wrappedValue = .trigger
            } else {
                isStylePickerPresented = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: AppIcon.Editing.textStyle)
                Text("Style")
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(ClaspToolbarButtonStyle(width: 96))
        .focused(stylePickerFocus, equals: .trigger)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: RichStylePickerTriggerFramePreferenceKey.self,
                    value: proxy.frame(in: .named(RichStylePickerCoordinateSpace.name))
                )
            }
        }
        .help("Paragraph style")
        .accessibilityLabel("Paragraph style")
        .accessibilityHint("Choose Body or Heading 1 through Heading 6")
        .accessibilityValue(isStylePickerPresented ? "Expanded" : "Collapsed")
        .accessibilityIdentifier("paragraph-style-trigger")
        .accessibilityRepresentation {
            DisclosureGroup(isExpanded: $isStylePickerPresented) {
                EmptyView()
            } label: {
                Text("Paragraph style")
            }
            .accessibilityHint("Choose Body or Heading 1 through Heading 6")
            .accessibilityIdentifier("paragraph-style-trigger")
        }
    }

    private var listMenu: some View {
        Menu {
            Button("Bulleted List") { send(.bulletList) }
            Button("Numbered List") { send(.numberedList) }
            Button("Checklist") { send(.checklist) }
        } label: {
            Image(systemName: AppIcon.Editing.bulletedList)
                .claspToolbarControlSurface()
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
                .claspToolbarControlSurface()
        }
        .menuStyle(.borderlessButton)
        .help("Insert Markdown block")
        .accessibilityLabel("Insert Markdown block")
    }

    private func formatButton(_ help: String, symbol: String, command: RichEditorCommand) -> some View {
        Button { send(command) } label: {
            Image(systemName: symbol)
        }
        .buttonStyle(ClaspToolbarButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }

    private var linkButton: some View {
        Button { showingLink.toggle() } label: {
            Image(systemName: AppIcon.Editing.link)
        }
        .buttonStyle(ClaspToolbarButtonStyle())
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

enum RichStylePickerFocus: Hashable {
    case trigger
    case option(String)
}

struct RichParagraphStyleOption: Identifiable {
    let id: String
    let title: String
    let detail: String
    let preview: String
    let previewSize: CGFloat
    let previewWeight: Font.Weight
    let command: RichEditorCommand

    static let all: [RichParagraphStyleOption] = [
        .init(
            id: "body",
            title: "Body",
            detail: "Paragraph text",
            preview: "Aa",
            previewSize: 15,
            previewWeight: .regular,
            command: .body
        ),
        .heading(level: 1, size: 22, weight: .bold, command: .heading1),
        .heading(level: 2, size: 20, weight: .bold, command: .heading2),
        .heading(level: 3, size: 18, weight: .semibold, command: .heading3),
        .heading(level: 4, size: 16, weight: .semibold, command: .heading4),
        .heading(level: 5, size: 15, weight: .semibold, command: .heading5),
        .heading(level: 6, size: 14, weight: .semibold, command: .heading6),
    ]

    private static func heading(
        level: Int,
        size: CGFloat,
        weight: Font.Weight,
        command: RichEditorCommand
    ) -> RichParagraphStyleOption {
        .init(
            id: "heading-\(level)",
            title: "Heading \(level)",
            detail: level == 1 ? "Page title" : "Section level \(level)",
            preview: "H\(level)",
            previewSize: size,
            previewWeight: weight,
            command: command
        )
    }
}

enum RichStylePickerInteraction {
    enum Movement {
        case previous
        case next
        case first
        case last
    }

    static func movedOptionID(from currentID: String?, by offset: Int) -> String? {
        let optionIDs = RichParagraphStyleOption.all.map(\.id)
        guard !optionIDs.isEmpty else { return nil }
        guard let currentID,
              let currentIndex = optionIDs.firstIndex(of: currentID) else {
            return offset < 0 ? optionIDs.last : optionIDs.first
        }
        let count = optionIDs.count
        let wrappedIndex = ((currentIndex + offset) % count + count) % count
        return optionIDs[wrappedIndex]
    }

    static func movedOptionID(from currentID: String?, movement: Movement) -> String? {
        switch movement {
        case .previous:
            movedOptionID(from: currentID, by: -1)
        case .next:
            movedOptionID(from: currentID, by: 1)
        case .first:
            RichParagraphStyleOption.all.first?.id
        case .last:
            RichParagraphStyleOption.all.last?.id
        }
    }

    static func command(forOptionID id: String) -> RichEditorCommand? {
        RichParagraphStyleOption.all.first { $0.id == id }?.command
    }
}

struct RichParagraphStylePicker: View {
    let focus: FocusState<RichStylePickerFocus?>.Binding
    let send: (RichEditorCommand) -> Void
    let dismissReturningToTrigger: () -> Void

    private var focusedOptionID: String? {
        guard case .option(let id) = focus.wrappedValue else { return nil }
        return id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Paragraph Style", systemImage: AppIcon.Editing.textStyle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Applies to the selected text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 3) {
                        ForEach(RichParagraphStyleOption.all) { option in
                            RichParagraphStyleOptionRow(
                                option: option,
                                focus: focus,
                                isKeyboardFocused: focus.wrappedValue == .option(option.id),
                                moveFocus: moveFocus
                            ) {
                                applyStyle(option.id)
                            }
                            .id(option.id)
                        }
                    }
                    .padding(8)
                }
                .scrollIndicators(.automatic)
                .onChange(of: focusedOptionID) { _, optionID in
                    guard let optionID else { return }
                    withAnimation(.easeOut(duration: ClaspDesign.Motion.quick)) {
                        proxy.scrollTo(optionID, anchor: .center)
                    }
                }
            }
        }
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: ClaspDesign.Metrics.menuCornerRadius, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: ClaspDesign.Metrics.menuCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ClaspDesign.Metrics.menuCornerRadius, style: .continuous)
                .stroke(.separator.opacity(0.72), lineWidth: 1)
        }
        .focusSection()
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                guard let firstID = RichParagraphStyleOption.all.first?.id else { return }
                focus.wrappedValue = .option(firstID)
            }
        }
        .onExitCommand(perform: dismissReturningToTrigger)
        .onKeyPress(.escape, phases: .down) { _ in
            dismissReturningToTrigger()
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Paragraph Style")
        .accessibilityIdentifier("paragraph-style-picker")
    }

    private func moveFocus(_ movement: RichStylePickerInteraction.Movement) {
        guard let nextID = RichStylePickerInteraction.movedOptionID(
            from: focusedOptionID,
            movement: movement
        ) else { return }
        focus.wrappedValue = .option(nextID)
    }

    private func applyStyle(_ optionID: String) {
        guard let command = RichStylePickerInteraction.command(forOptionID: optionID) else { return }
        focus.wrappedValue = nil
        // RichMarkdownEditor.Coordinator returns the caret to its NSTextView
        // after applying the source command, including source-preserving no-ops.
        send(command)
    }
}

private struct RichParagraphStyleOptionRow: View {
    let option: RichParagraphStyleOption
    let focus: FocusState<RichStylePickerFocus?>.Binding
    let isKeyboardFocused: Bool
    let moveFocus: (RichStylePickerInteraction.Movement) -> Void
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(option.preview)
                    .font(.system(size: option.previewSize, weight: option.previewWeight))
                    .foregroundStyle(.primary)
                    .frame(width: 36, alignment: .leading)

                VStack(alignment: .leading, spacing: 1) {
                    Text(option.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(option.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                Color.accentColor.opacity(isKeyboardFocused ? 0.18 : (isHovering ? 0.13 : 0)),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isKeyboardFocused ? Color.accentColor : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        // Explicit focusability keeps the picker keyboard-navigable even when
        // the system-wide "Keyboard navigation" preference for buttons is off.
        .focusable()
        .focused(focus, equals: .option(option.id))
        .onKeyPress(.return, phases: .down) { _ in
            action()
            return .handled
        }
        .onKeyPress(.space, phases: .down) { _ in
            action()
            return .handled
        }
        .onKeyPress(.downArrow, phases: .down) { _ in
            moveFocus(.next)
            return .handled
        }
        .onKeyPress(.upArrow, phases: .down) { _ in
            moveFocus(.previous)
            return .handled
        }
        .onKeyPress(.home, phases: .down) { _ in
            moveFocus(.first)
            return .handled
        }
        .onKeyPress(.end, phases: .down) { _ in
            moveFocus(.last)
            return .handled
        }
        .onKeyPress(.tab, phases: .down) { keyPress in
            moveFocus(keyPress.modifiers.contains(.shift) ? .previous : .next)
            return .handled
        }
        .onHover { isHovering = $0 }
        .accessibilityLabel(option.title)
        .accessibilityHint(option.detail)
        .accessibilityIdentifier("paragraph-style-option-\(option.id)")
    }
}
