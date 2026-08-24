import AppKit
import Combine
import SwiftUI
import XCTest
@testable import PersonalNotepad

/// End-to-end interaction contracts for the AppKit-backed Markdown editor.
///
/// Transformer unit tests establish the intended source edit. These tests take
/// that edit through the real MarkdownPageTextView and Coordinator, where
/// TextKit selection, viewport, layout, and undo behavior can regress even when
/// the resulting Markdown string is correct.
@MainActor
final class RichMarkdownEditorInteractionTests: XCTestCase {
    private let upperAnchor = "UPPER SURROUNDING BLOCK — cafe\u{301} 😀"
    private let lowerAnchor = "LOWER SURROUNDING BLOCK — untouched 🧭"

    func testParagraphStylePickerPlacementStaysInsideEditorPaneAtEveryEdgeAndCompactSize() {
        let idealSize = RichStylePickerLayout.idealSize
        let edgeInset = RichStylePickerLayout.edgeInset
        let fixtures: [(
            name: String,
            bounds: CGRect,
            trigger: CGRect,
            expectedAttachment: RichStylePickerPlacement.VerticalAttachment
        )] = [
            (
                "top left",
                CGRect(x: 0, y: 0, width: 820, height: 720),
                CGRect(x: 20, y: 72, width: 92, height: 30),
                .below
            ),
            (
                "top right",
                CGRect(x: 0, y: 0, width: 820, height: 720),
                CGRect(x: 742, y: 72, width: 64, height: 30),
                .below
            ),
            (
                "bottom",
                CGRect(x: 0, y: 0, width: 820, height: 720),
                CGRect(x: 280, y: 668, width: 92, height: 30),
                .above
            ),
            (
                "narrow",
                CGRect(x: 0, y: 0, width: 210, height: 720),
                CGRect(x: 108, y: 72, width: 90, height: 30),
                .below
            ),
            (
                "short",
                CGRect(x: 0, y: 0, width: 420, height: 190),
                CGRect(x: 18, y: 72, width: 92, height: 30),
                .overlapping
            ),
        ]

        for fixture in fixtures {
            let placement = RichStylePickerLayout.placement(
                in: fixture.bounds,
                anchoredTo: fixture.trigger
            )
            let safeBounds = fixture.bounds.insetBy(dx: edgeInset, dy: edgeInset)

            XCTAssertEqual(placement.verticalAttachment, fixture.expectedAttachment, fixture.name)
            XCTAssertGreaterThan(placement.frame.width, 0, fixture.name)
            XCTAssertGreaterThan(placement.frame.height, 0, fixture.name)
            XCTAssertGreaterThanOrEqual(placement.frame.minX, safeBounds.minX - 0.001, fixture.name)
            XCTAssertLessThanOrEqual(placement.frame.maxX, safeBounds.maxX + 0.001, fixture.name)
            XCTAssertGreaterThanOrEqual(placement.frame.minY, safeBounds.minY - 0.001, fixture.name)
            XCTAssertLessThanOrEqual(placement.frame.maxY, safeBounds.maxY + 0.001, fixture.name)
            XCTAssertLessThanOrEqual(placement.frame.width, idealSize.width + 0.001, fixture.name)
            XCTAssertLessThanOrEqual(placement.frame.height, idealSize.height + 0.001, fixture.name)
        }

        let left = RichStylePickerLayout.placement(
            in: fixtures[0].bounds,
            anchoredTo: fixtures[0].trigger
        )
        XCTAssertEqual(left.frame.minX, fixtures[0].trigger.minX, accuracy: 0.001)

        let right = RichStylePickerLayout.placement(
            in: fixtures[1].bounds,
            anchoredTo: fixtures[1].trigger
        )
        XCTAssertEqual(right.frame.maxX, fixtures[1].bounds.maxX - edgeInset, accuracy: 0.001)

        let narrow = RichStylePickerLayout.placement(
            in: fixtures[3].bounds,
            anchoredTo: fixtures[3].trigger
        )
        XCTAssertEqual(narrow.frame.width, fixtures[3].bounds.width - edgeInset * 2, accuracy: 0.001)

        let short = RichStylePickerLayout.placement(
            in: fixtures[4].bounds,
            anchoredTo: fixtures[4].trigger
        )
        XCTAssertEqual(short.frame.height, fixtures[4].bounds.height - edgeInset * 2, accuracy: 0.001)
    }

    func testParagraphStylePickerKeyboardCycleAndCommandRoutingAreStable() {
        let optionIDs = RichParagraphStyleOption.all.map(\.id)
        XCTAssertEqual(
            optionIDs,
            ["body", "heading-1", "heading-2", "heading-3", "heading-4", "heading-5", "heading-6"]
        )
        XCTAssertEqual(RichStylePickerInteraction.movedOptionID(from: nil, by: 1), "body")
        XCTAssertEqual(RichStylePickerInteraction.movedOptionID(from: nil, by: -1), "heading-6")
        XCTAssertEqual(RichStylePickerInteraction.movedOptionID(from: "body", by: -1), "heading-6")
        XCTAssertEqual(RichStylePickerInteraction.movedOptionID(from: "heading-6", by: 1), "body")
        XCTAssertEqual(
            RichStylePickerInteraction.movedOptionID(from: "heading-4", movement: .first),
            "body"
        )
        XCTAssertEqual(
            RichStylePickerInteraction.movedOptionID(from: "heading-2", movement: .last),
            "heading-6"
        )
        XCTAssertEqual(RichStylePickerInteraction.command(forOptionID: "body"), .body)
        XCTAssertEqual(RichStylePickerInteraction.command(forOptionID: "heading-2"), .heading2)
        XCTAssertNil(RichStylePickerInteraction.command(forOptionID: "unknown"))
    }

    func testEveryRichEditorCommandPreservesInteractionContractsAndUndoRedo() throws {
        for fixture in commandFixtures {
            try assertInteractionContracts(for: fixture)
        }
    }

    func testNativePageChecklistTogglePreservesExactSourceSelectionViewportLayoutAndUndoRedo() throws {
        let task = "- [ ] Ship the accessible release"
        let source = commandSource(for: .init(
            name: "interactive checklist",
            command: .checklist,
            targetBlock: task,
            selectionText: "Ship the accessible release"
        ))
        let item = try XCTUnwrap(MarkdownSourceAnalyzer.checklistItems(in: source).first)
        let expected = MarkdownSourceCommandTransformer.togglingChecklist(
            in: source,
            atStateRange: item.stateRange,
            selection: item.contentRange
        )
        let harness = RichEditorInteractionHarness(source: source, showsSource: false)
        defer { harness.close() }
        harness.textView.setSelectedRange(item.contentRange)
        try harness.centerViewport(on: item.lineRange)
        harness.settleLayoutKeepingCurrentViewport()
        harness.clearUndoHistory()
        harness.textView.refreshVisibleChecklistControls()

        let viewportBefore = harness.viewport
        let before = try harness.layoutSnapshot(upperAnchor: upperAnchor, lowerAnchor: lowerAnchor)
        XCTAssertEqual(harness.textView.presentedChecklistDecorations, [
            MarkdownPageChecklistDecoration(item: item)
        ])
        let control = try XCTUnwrap(
            harness.textView.visibleChecklistControls.first { $0.tag == item.stateRange.location }
        )
        XCTAssertEqual(control.state, .off)
        XCTAssertEqual(control.accessibilityRole(), .checkBox)
        XCTAssertEqual(control.accessibilityLabel(), "Ship the accessible release")
        XCTAssertFalse(control.refusesFirstResponder)
        XCTAssertTrue(control.acceptsFirstResponder)
        XCTAssertEqual((control.accessibilityValue() as? NSNumber)?.intValue, 0)
        XCTAssertTrue(harness.textView.accessibilityChildren()?.contains(where: {
            ($0 as AnyObject) === control
        }) == true)

        let accessibleText = try XCTUnwrap(
            harness.textView.accessibilityAttributedString(
                for: NSRange(location: 0, length: (source as NSString).length)
            )
        )
        XCTAssertEqual(
            accessibleText.attribute(.accessibilityCustomText, at: item.markerRange.location, effectiveRange: nil) as? [String],
            [""]
        )

        // Exercise the actual keyboard path. The coordinator intentionally
        // leaves focus on the native checkbox after activation.
        XCTAssertTrue(harness.focus(control))
        XCTAssertTrue(harness.firstResponder === control)
        let space = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: 49
        ))
        control.keyDown(with: space)
        harness.settleLayoutKeepingCurrentViewport()
        let after = try harness.layoutSnapshot(upperAnchor: upperAnchor, lowerAnchor: lowerAnchor)

        XCTAssertEqual(Data(harness.textView.string.utf8), Data(expected.source.utf8))
        XCTAssertEqual(Data(harness.state.markdown.utf8), Data(expected.source.utf8))
        XCTAssertEqual(harness.textView.selectedRange(), item.contentRange)
        XCTAssertEqual(harness.viewport.origin.x, viewportBefore.origin.x, accuracy: 0.01)
        XCTAssertEqual(harness.viewport.origin.y, viewportBefore.origin.y, accuracy: 0.01)
        assertRect(after.upperAnchor, equals: before.upperAnchor, accuracy: 0.01)
        assertRect(after.lowerAnchor, equals: before.lowerAnchor, accuracy: 0.01)
        assertRect(after.usedRect, equals: before.usedRect, accuracy: 0.01)
        XCTAssertEqual(after.textViewSize.width, before.textViewSize.width, accuracy: 0.01)
        XCTAssertEqual(after.textViewSize.height, before.textViewSize.height, accuracy: 0.01)
        XCTAssertEqual(
            harness.textView.visibleChecklistControls.first { $0.tag == item.stateRange.location }?.state,
            .on
        )
        XCTAssertEqual((control.accessibilityValue() as? NSNumber)?.intValue, 1)
        XCTAssertTrue(harness.firstResponder === control)

        let undoManager = try XCTUnwrap(harness.textView.undoManager)
        XCTAssertTrue(undoManager.canUndo)
        undoManager.undo()
        harness.settleLayoutKeepingCurrentViewport()
        XCTAssertEqual(Data(harness.textView.string.utf8), Data(source.utf8))
        XCTAssertEqual(Data(harness.state.markdown.utf8), Data(source.utf8))
        XCTAssertEqual(harness.textView.selectedRange(), item.contentRange)
        XCTAssertEqual(harness.viewport.origin.y, viewportBefore.origin.y, accuracy: 0.01)
        XCTAssertEqual(
            harness.textView.visibleChecklistControls.first { $0.tag == item.stateRange.location }?.state,
            .off
        )

        XCTAssertTrue(undoManager.canRedo)
        undoManager.redo()
        harness.settleLayoutKeepingCurrentViewport()
        XCTAssertEqual(Data(harness.textView.string.utf8), Data(expected.source.utf8))
        XCTAssertEqual(Data(harness.state.markdown.utf8), Data(expected.source.utf8))
        XCTAssertEqual(harness.textView.selectedRange(), item.contentRange)
        XCTAssertEqual(harness.viewport.origin.y, viewportBefore.origin.y, accuracy: 0.01)

        harness.setMode(showsSource: true)
        XCTAssertTrue(harness.textView.visibleChecklistControls.isEmpty)
        XCTAssertFalse(harness.textView.accessibilityChildren()?.contains(where: {
            ($0 as AnyObject) === control
        }) == true)
        XCTAssertEqual(Data(harness.textView.string.utf8), Data(expected.source.utf8))
        let sourceMarkerColor = try XCTUnwrap(
            harness.textView.textStorage?.attribute(
                .foregroundColor,
                at: item.markerRange.location,
                effectiveRange: nil
            ) as? NSColor
        )
        XCTAssertFalse(sourceMarkerColor.isEqual(NSColor.clear))
    }

    func testLongDocumentChecklistControlRefreshesSynchronouslyBeforeSemanticDebounce() throws {
        let task = "- [ ] Long document task"
        let source = longSource(
            lineCount: 620,
            replacements: [
                307: upperAnchor,
                308: task,
                309: lowerAnchor,
            ]
        )
        XCTAssertGreaterThan((source as NSString).length, 32_000)
        let item = try XCTUnwrap(MarkdownSourceAnalyzer.checklistItems(in: source).first)
        let harness = RichEditorInteractionHarness(source: source, showsSource: false)
        defer { harness.close() }
        harness.textView.setSelectedRange(item.contentRange)
        try harness.centerViewport(on: item.lineRange)
        harness.settleLayoutKeepingCurrentViewport()
        harness.clearUndoHistory()

        let control = try XCTUnwrap(
            harness.textView.visibleChecklistControls.first { $0.tag == item.stateRange.location }
        )
        control.performClick(nil)

        // No sleep or debounce flush: the lightweight checklist pass must
        // already expose the new source-backed state without blinking.
        XCTAssertEqual((harness.textView.string as NSString).substring(with: item.stateRange), "x")
        XCTAssertEqual(
            harness.textView.visibleChecklistControls.first { $0.tag == item.stateRange.location }?.state,
            .on
        )
        XCTAssertEqual(harness.textView.selectedRange(), item.contentRange)
        harness.coordinator.cancelPendingPresentation()
    }

    func testChecklistDecorationFilteringSupportsVisibleRowVirtualization() {
        let decorations = [
            MarkdownPageChecklistDecoration(
                lineRange: NSRange(location: 0, length: 12),
                markerRange: NSRange(location: 0, length: 6),
                stateRange: NSRange(location: 3, length: 1),
                contentRange: NSRange(location: 6, length: 6),
                isChecked: false
            ),
            MarkdownPageChecklistDecoration(
                lineRange: NSRange(location: 40, length: 14),
                markerRange: NSRange(location: 40, length: 6),
                stateRange: NSRange(location: 43, length: 1),
                contentRange: NSRange(location: 46, length: 8),
                isChecked: true
            ),
        ]

        XCTAssertEqual(
            MarkdownPageTextView.checklistDecorations(
                decorations,
                intersecting: NSRange(location: 35, length: 12)
            ),
            [decorations[1]]
        )
        XCTAssertTrue(
            MarkdownPageTextView.checklistDecorations(
                decorations,
                intersecting: NSRange(location: 15, length: 10)
            ).isEmpty
        )
    }

    func testScrollingVirtualizesChecklistControlsWithoutStaleRangesOrState() throws {
        let source = (0..<140).map { index in
            switch index {
            case 1: "- [ ] Top visible task"
            case 138: "- [x] Bottom visible task"
            default: String(format: "Paragraph %03d with stable scrolling content.", index)
            }
        }.joined(separator: "\n")
        let items = MarkdownSourceAnalyzer.checklistItems(in: source)
        XCTAssertEqual(items.count, 2)
        let harness = RichEditorInteractionHarness(
            source: source,
            showsSource: false,
            viewportSize: NSSize(width: 500, height: 220)
        )
        defer { harness.close() }

        harness.textView.refreshVisibleChecklistControls()
        XCTAssertEqual(harness.textView.visibleChecklistControls.map(\.tag), [items[0].stateRange.location])
        XCTAssertEqual(harness.textView.visibleChecklistControls.first?.state, .off)

        try harness.centerViewport(on: items[1].lineRange)
        harness.settleLayoutKeepingCurrentViewport()
        harness.textView.refreshVisibleChecklistControls()
        XCTAssertEqual(harness.textView.visibleChecklistControls.map(\.tag), [items[1].stateRange.location])
        XCTAssertEqual(harness.textView.visibleChecklistControls.first?.state, .on)
        XCTAssertEqual(harness.textView.visibleChecklistControls.first?.accessibilityLabel(), "Bottom visible task")
    }

    func testChecklistControlFitsFixedMarkerGeometryForEveryDocumentFontFamily() throws {
        for family in DocumentFontFamily.allCases {
            let style = DocumentStyle(
                preset: .balanced,
                fontFamily: family,
                bodyPointSize: 18,
                lineHeightMultiplier: 1.55,
                paragraphSpacing: 12,
                targetCharactersPerLine: 68
            )
            let source = "Prelude\n- [ ] Stable marker geometry\nEpilogue"
            let item = try XCTUnwrap(MarkdownSourceAnalyzer.checklistItems(in: source).first)
            let harness = RichEditorInteractionHarness(
                source: source,
                showsSource: false,
                style: style,
                viewportSize: NSSize(width: 500, height: 220)
            )
            defer { harness.close() }
            harness.textView.refreshVisibleChecklistControls()
            let control = try XCTUnwrap(
                harness.textView.visibleChecklistControls.first { $0.tag == item.stateRange.location },
                family.rawValue
            )
            let markerRect = try harness.documentRect(for: item.markerRange)
            let markerFont = try XCTUnwrap(
                harness.textView.textStorage?.attribute(
                    .font,
                    at: item.markerRange.location,
                    effectiveRange: nil
                ) as? NSFont
            )
            XCTAssertTrue(markerFont.isFixedPitch, family.rawValue)
            XCTAssertGreaterThanOrEqual(control.frame.minX, markerRect.minX - 0.5, family.rawValue)
            XCTAssertLessThanOrEqual(control.frame.maxX, markerRect.maxX + 0.5, family.rawValue)

            let frameBefore = control.frame
            let layoutBefore = try harness.layoutSnapshot(upperAnchor: "Prelude", lowerAnchor: "Epilogue")
            control.performClick(nil)
            harness.settleLayoutKeepingCurrentViewport()
            let controlAfter = try XCTUnwrap(
                harness.textView.visibleChecklistControls.first { $0.tag == item.stateRange.location },
                family.rawValue
            )
            let layoutAfter = try harness.layoutSnapshot(upperAnchor: "Prelude", lowerAnchor: "Epilogue")
            assertRect(controlAfter.frame, equals: frameBefore, accuracy: 0.01, message: family.rawValue)
            assertRect(layoutAfter.upperAnchor, equals: layoutBefore.upperAnchor, accuracy: 0.01, message: family.rawValue)
            assertRect(layoutAfter.lowerAnchor, equals: layoutBefore.lowerAnchor, accuracy: 0.01, message: family.rawValue)
            assertRect(layoutAfter.usedRect, equals: layoutBefore.usedRect, accuracy: 0.01, message: family.rawValue)
        }
    }

    func testItalicPresentationDoesNotReassignSelectionJumpViewportOrShiftUnrelatedGeometry() throws {
        let selectedText = "italic focus cafe\u{301} 👩🏽‍💻"
        let source = longSource(
            lineCount: 620,
            replacements: [
                307: upperAnchor,
                308: "A comfortably short \(selectedText) remains on one visual line.",
                309: lowerAnchor,
            ]
        )
        XCTAssertGreaterThan((source as NSString).length, 32_000)
        XCTAssertLessThan((source as NSString).length, MarkdownSourcePresentation.maximumParsedUTF16Length)

        let harness = RichEditorInteractionHarness(source: source, showsSource: false)
        defer { harness.close() }
        let selection = try range(of: selectedText, in: source)
        let expected = MarkdownSourceCommandTransformer.applying(.italic, to: source, selection: selection)

        harness.textView.setSelectedRange(selection)
        try harness.centerViewport(on: selection)
        harness.clearUndoHistory()
        let viewportBefore = harness.viewport
        let layoutBefore = try harness.layoutSnapshot(upperAnchor: upperAnchor, lowerAnchor: lowerAnchor)

        harness.coordinator.apply(.italic, to: harness.textView)
        harness.settleLayoutKeepingCurrentViewport()
        let viewportAfterCommand = harness.viewport
        XCTAssertEqual(viewportAfterCommand.origin.x, viewportBefore.origin.x, accuracy: 0.01)
        XCTAssertEqual(viewportAfterCommand.origin.y, viewportBefore.origin.y, accuracy: 0.01)
        XCTAssertEqual(harness.textView.selectedRange(), expected.selection)
        assertExactBytesOutsideEdit(original: source, actual: harness.textView.string, expected: expected.source)

        // Long-document formatting is normally debounced. Exercise the exact
        // eventual attribute-only pass synchronously and observe redundant
        // selection assignment, the historical trigger for the viewport jump.
        let selectionNotifications = RichEditorSelectionNotificationRecorder(textView: harness.textView)
        selectionNotifications.reset()
        harness.coordinator.applyPresentation(to: harness.textView, preservingViewport: true)
        harness.settleLayoutKeepingCurrentViewport()

        let layoutAfter = try harness.layoutSnapshot(upperAnchor: upperAnchor, lowerAnchor: lowerAnchor)
        XCTAssertEqual(selectionNotifications.changeCount, 0, "Attribute-only presentation must not reassign the selection")
        XCTAssertEqual(harness.textView.selectedRange(), expected.selection)
        XCTAssertEqual(harness.viewport.origin.x, viewportBefore.origin.x, accuracy: 0.01)
        XCTAssertEqual(harness.viewport.origin.y, viewportBefore.origin.y, accuracy: 0.01)
        XCTAssertEqual(Data(harness.textView.string.utf8), Data(expected.source.utf8))
        XCTAssertEqual(Data(harness.state.markdown.utf8), Data(expected.source.utf8))

        // The chosen line is comfortably below its wrap threshold. Hidden
        // italic markers therefore must not change any document geometry.
        assertRect(layoutAfter.upperAnchor, equals: layoutBefore.upperAnchor, accuracy: 0.5)
        assertRect(layoutAfter.lowerAnchor, equals: layoutBefore.lowerAnchor, accuracy: 0.5)
        assertRect(layoutAfter.usedRect, equals: layoutBefore.usedRect, accuracy: 0.5)
        XCTAssertEqual(layoutAfter.textViewSize.width, layoutBefore.textViewSize.width, accuracy: 0.01)
        XCTAssertEqual(layoutAfter.textViewSize.height, layoutBefore.textViewSize.height, accuracy: 0.5)
        XCTAssertEqual(layoutAfter.containerSize.width, layoutBefore.containerSize.width, accuracy: 0.01)
        XCTAssertEqual(layoutAfter.viewportSize.width, layoutBefore.viewportSize.width, accuracy: 0.01)
        XCTAssertEqual(layoutAfter.viewportSize.height, layoutBefore.viewportSize.height, accuracy: 0.01)
    }

    func testPageMarkdownSwitchingPreservesOneBufferSelectionViewportAndBytesForShortAndLongDocuments() throws {
        let selectedText = "mode target cafe\u{301} 🧑🏾‍🚀"
        let shortSource = [
            upperAnchor,
            "A short \(selectedText) with **existing Markdown**.",
            lowerAnchor,
        ].joined(separator: "\r\n")
        let longSource = longSource(
            lineCount: 620,
            replacements: [
                307: upperAnchor,
                308: "A long \(selectedText) with **existing Markdown**.",
                309: lowerAnchor,
            ]
        )

        for (name, source) in [("short", shortSource), ("long", longSource)] {
            let harness = RichEditorInteractionHarness(source: source, showsSource: false)
            let selection = try range(of: selectedText, in: source)
            harness.textView.setSelectedRange(selection)
            try harness.centerViewport(on: selection)
            let bytes = Data(source.utf8)
            let viewport = harness.viewport
            let originalTextViewWidth = harness.textView.frame.width

            harness.setMode(showsSource: true)
            harness.settleLayoutKeepingCurrentViewport()
            XCTAssertEqual(Data(harness.textView.string.utf8), bytes, "\(name): Page → Markdown changed source bytes")
            XCTAssertEqual(Data(harness.state.markdown.utf8), bytes, "\(name): binding changed during Page → Markdown")
            XCTAssertEqual(harness.textView.selectedRange(), selection, "\(name): Page → Markdown changed selection")
            XCTAssertEqual(harness.viewport.origin.x, viewport.origin.x, accuracy: 0.01, "\(name): Page → Markdown moved x")
            XCTAssertEqual(harness.viewport.origin.y, viewport.origin.y, accuracy: 0.01, "\(name): Page → Markdown moved y")
            XCTAssertEqual(harness.textView.frame.width, originalTextViewWidth, accuracy: 0.01)

            harness.setMode(showsSource: false)
            harness.settleLayoutKeepingCurrentViewport()
            XCTAssertEqual(Data(harness.textView.string.utf8), bytes, "\(name): Markdown → Page changed source bytes")
            XCTAssertEqual(Data(harness.state.markdown.utf8), bytes, "\(name): binding changed during Markdown → Page")
            XCTAssertEqual(harness.textView.selectedRange(), selection, "\(name): Markdown → Page changed selection")
            XCTAssertEqual(harness.viewport.origin.x, viewport.origin.x, accuracy: 0.01, "\(name): Markdown → Page moved x")
            XCTAssertEqual(harness.viewport.origin.y, viewport.origin.y, accuracy: 0.01, "\(name): Markdown → Page moved y")
            XCTAssertEqual(harness.textView.frame.width, originalTextViewWidth, accuracy: 0.01)
            harness.close()
        }
    }

    func testHostedRepresentableKeepsPartialHeadingAndBodyAcrossImmediateModeTurns() async throws {
        try await assertHostedRepresentableModeRoundTrip(
            name: "partial heading",
            source: "Before\r\nAlpha target omega\r\nAfter",
            selectedText: "target",
            command: .heading2,
            switchesToMarkdownImmediately: false
        )
        try await assertHostedRepresentableModeRoundTrip(
            name: "partial body",
            source: "Before\r\n### Alpha target omega\r\nAfter",
            selectedText: "target",
            command: .body,
            switchesToMarkdownImmediately: true
        )

        let longTarget = "hosted long target cafe\u{301} 🛰️"
        let longDocument = longSource(
            lineCount: 620,
            replacements: [
                307: upperAnchor,
                308: "Long prefix \(longTarget) long suffix",
                309: lowerAnchor,
            ]
        )
        XCTAssertGreaterThan((longDocument as NSString).length, 32_000)
        try await assertHostedRepresentableModeRoundTrip(
            name: "long partial heading",
            source: longDocument,
            selectedText: longTarget,
            command: .heading3,
            switchesToMarkdownImmediately: true
        )
    }

    func testDismantlingRepresentableCancelsDeferredCommand() async {
        let source = "Alpha target omega"
        let harness = RichEditorInteractionHarness(source: source, showsSource: false)
        let command = RichEditorCommandToken(command: .heading2)
        harness.textView.setSelectedRange((source as NSString).range(of: "target"))

        harness.coordinator.schedule(command.command, id: command.id, for: harness.textView)
        RichMarkdownEditor.dismantleNSView(harness.scrollView, coordinator: harness.coordinator)
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(harness.state.markdown, source)
        XCTAssertEqual(harness.textView.string, "")
        harness.close()
    }

    func testVisibleAndOffscreenSelectionsPreserveAnchoredAndLegitimateScrollBehavior() throws {
        let visibleText = "Paragraph 0118"
        let offscreenText = "Paragraph 0599"
        let source = offscreenControlSource(
            lineCount: 600,
            replacements: [:]
        )
        XCTAssertGreaterThan((source as NSString).length, 32_000)

        // A command applied to an already visible selection must not move the
        // viewport away from the user's reading position.
        let visibleHarness = RichEditorInteractionHarness(
            source: source,
            showsSource: false,
            viewportSize: NSSize(width: 420, height: 220),
            attachesToWindow: false
        )
        let visibleSelection = try range(of: visibleText, in: source)
        visibleHarness.textView.setSelectedRange(visibleSelection)
        try visibleHarness.centerViewport(on: visibleSelection)
        let visibleViewport = visibleHarness.viewport
        let visibleExpected = MarkdownSourceCommandTransformer.applying(.bold, to: source, selection: visibleSelection)

        visibleHarness.coordinator.apply(.bold, to: visibleHarness.textView)
        visibleHarness.coordinator.applyPresentation(to: visibleHarness.textView, preservingViewport: true)
        visibleHarness.settleLayoutKeepingCurrentViewport()
        XCTAssertEqual(visibleHarness.viewport.origin.x, visibleViewport.origin.x, accuracy: 0.01)
        XCTAssertEqual(visibleHarness.viewport.origin.y, visibleViewport.origin.y, accuracy: 0.01)
        XCTAssertEqual(visibleHarness.textView.selectedRange(), visibleExpected.selection)
        assertExactBytesOutsideEdit(original: source, actual: visibleHarness.textView.string, expected: visibleExpected.source)
        visibleHarness.close()

        // Use a fresh, unedited TextKit layout as the AppKit control for
        // legitimate programmatic selection reveal. This keeps that behavior
        // independent from the visible-edit assertion above.
        let offscreenHarness = RichEditorInteractionHarness(
            source: source,
            showsSource: false,
            viewportSize: NSSize(width: 420, height: 220),
            attachesToWindow: false
        )
        defer { offscreenHarness.close() }
        let startingSelection = try range(of: visibleText, in: source)
        try offscreenHarness.centerViewport(on: startingSelection)
        let offscreenSelection = try range(of: offscreenText, in: source)
        let offscreenRect = try offscreenHarness.documentRect(for: offscreenSelection)
        let viewportBeforeReveal = offscreenHarness.viewport
        XCTAssertFalse(viewportBeforeReveal.intersects(offscreenRect), "Offscreen fixture must begin outside the viewport")
        XCTAssertLessThanOrEqual(
            offscreenRect.maxY,
            offscreenHarness.textView.bounds.maxY,
            "Layout-manager selection rect must fit the AppKit document view before reveal"
        )

        offscreenHarness.textView.setSelectedRange(offscreenSelection)
        offscreenHarness.textView.scrollRangeToVisible(offscreenSelection)
        offscreenHarness.scrollView.reflectScrolledClipView(offscreenHarness.scrollView.contentView)
        let revealedViewport = offscreenHarness.viewport
        XCTAssertGreaterThan(revealedViewport.origin.y, viewportBeforeReveal.origin.y)
        XCTAssertTrue(
            revealedViewport.intersects(offscreenRect),
            "AppKit must retain normal offscreen reveal behavior; viewport=\(revealedViewport), range=\(offscreenRect), document=\(offscreenHarness.textView.bounds)"
        )

        let sourceBeforeOffscreenEdit = MarkdownSourceIdentity.detachedCopy(offscreenHarness.textView.string)
        let offscreenExpected = MarkdownSourceCommandTransformer.applying(
            .strikethrough,
            to: sourceBeforeOffscreenEdit,
            selection: offscreenSelection
        )
        offscreenHarness.coordinator.apply(.strikethrough, to: offscreenHarness.textView)
        offscreenHarness.coordinator.applyPresentation(to: offscreenHarness.textView, preservingViewport: true)
        offscreenHarness.settleLayoutKeepingCurrentViewport()

        XCTAssertEqual(offscreenHarness.viewport.origin.x, revealedViewport.origin.x, accuracy: 0.01)
        XCTAssertEqual(offscreenHarness.viewport.origin.y, revealedViewport.origin.y, accuracy: 0.01)
        XCTAssertEqual(offscreenHarness.textView.selectedRange(), offscreenExpected.selection)
        XCTAssertTrue(offscreenHarness.viewport.intersects(try offscreenHarness.documentRect(for: offscreenExpected.selection)))
        assertExactBytesOutsideEdit(
            original: sourceBeforeOffscreenEdit,
            actual: offscreenHarness.textView.string,
            expected: offscreenExpected.source
        )
    }

    func testSourceModeMarkerReflowIsLocalWhileSurroundingMetricsAndViewportRemainAnchored() throws {
        let probe = RichEditorInteractionHarness(
            source: sourceModeReflowSource(target: String(repeating: "W", count: 24)),
            showsSource: true,
            viewportSize: NSSize(width: 270, height: 230)
        )
        let lineWidth = try probe.lineFragmentWidth(at: range(of: upperAnchor, in: probe.textView.string))
        let characterWidth = ("W" as NSString).size(withAttributes: [
            .font: MarkdownEditorPresentationStyle(.balanced).sourceFont,
        ]).width
        probe.close()

        let estimatedColumns = max(8, Int(floor(lineWidth / characterWidth)))
        var exercisedReflow = false

        for count in max(4, estimatedColumns - 5)...(estimatedColumns + 5) {
            let selectedText = String(repeating: "W", count: count)
            let source = sourceModeReflowSource(target: selectedText)
            let harness = RichEditorInteractionHarness(
                source: source,
                showsSource: true,
                viewportSize: NSSize(width: 270, height: 230)
            )
            let selection = try range(of: selectedText, in: source)
            let expected = MarkdownSourceCommandTransformer.applying(.bold, to: source, selection: selection)
            harness.textView.setSelectedRange(selection)
            try harness.centerViewport(on: selection)
            let viewportBefore = harness.viewport
            let before = try harness.layoutSnapshot(upperAnchor: upperAnchor, lowerAnchor: lowerAnchor)
            let localBefore = try harness.documentRect(for: selection)

            harness.coordinator.apply(.bold, to: harness.textView)
            harness.coordinator.applyPresentation(to: harness.textView, preservingViewport: true)
            harness.settleLayoutKeepingCurrentViewport()

            let localAfter = try harness.documentRect(for: expected.selection)
            guard localAfter.height > localBefore.height + 0.5 else {
                harness.close()
                continue
            }

            exercisedReflow = true
            let after = try harness.layoutSnapshot(upperAnchor: upperAnchor, lowerAnchor: lowerAnchor)
            let localHeightDelta = localAfter.height - localBefore.height
            let downstreamShift = after.lowerAnchor.minY - before.lowerAnchor.minY

            XCTAssertEqual(harness.viewport.origin.x, viewportBefore.origin.x, accuracy: 0.01)
            XCTAssertEqual(harness.viewport.origin.y, viewportBefore.origin.y, accuracy: 0.01)
            XCTAssertEqual(harness.textView.selectedRange(), expected.selection)
            assertExactBytesOutsideEdit(original: source, actual: harness.textView.string, expected: expected.source)
            assertRect(after.upperAnchor, equals: before.upperAnchor, accuracy: 0.5)
            XCTAssertEqual(after.lowerAnchor.minX, before.lowerAnchor.minX, accuracy: 0.5)
            XCTAssertEqual(after.lowerAnchor.width, before.lowerAnchor.width, accuracy: 0.5)
            XCTAssertEqual(after.lowerAnchor.height, before.lowerAnchor.height, accuracy: 0.5)
            XCTAssertEqual(downstreamShift, localHeightDelta, accuracy: 1.0)
            XCTAssertEqual(after.usedRect.height - before.usedRect.height, localHeightDelta, accuracy: 1.0)
            XCTAssertEqual(after.containerSize.width, before.containerSize.width, accuracy: 0.01)
            XCTAssertEqual(after.viewportSize.width, before.viewportSize.width, accuracy: 0.01)
            XCTAssertEqual(after.viewportSize.height, before.viewportSize.height, accuracy: 0.01)
            harness.close()
            break
        }

        XCTAssertTrue(exercisedReflow, "Fixture search must find a line where inserted Markdown markers create legitimate local wrapping")
    }

    private func assertInteractionContracts(for fixture: RichEditorCommandFixture) throws {
        let source = commandSource(for: fixture)
        let selection = try range(of: fixture.selectionText, in: source)
        let expected = MarkdownSourceCommandTransformer.applying(fixture.command, to: source, selection: selection)
        XCTAssertFalse(
            MarkdownSourceIdentity.exactlyEqual(expected.source, source),
            "\(fixture.name): fixture must exercise a source-changing command"
        )

        let harness = RichEditorInteractionHarness(source: source, showsSource: false)
        defer { harness.close() }
        harness.textView.setSelectedRange(selection)
        try harness.centerViewport(on: selection)
        harness.clearUndoHistory()
        let viewportBefore = harness.viewport
        let before = try harness.layoutSnapshot(upperAnchor: upperAnchor, lowerAnchor: lowerAnchor)

        harness.coordinator.apply(fixture.command, to: harness.textView)
        harness.settleLayoutKeepingCurrentViewport()
        let after = try harness.layoutSnapshot(upperAnchor: upperAnchor, lowerAnchor: lowerAnchor)

        XCTAssertEqual(Data(harness.textView.string.utf8), Data(expected.source.utf8), "\(fixture.name): text view source")
        XCTAssertEqual(Data(harness.state.markdown.utf8), Data(expected.source.utf8), "\(fixture.name): binding source")
        XCTAssertEqual(harness.textView.selectedRange(), expected.selection, "\(fixture.name): UTF-16 selection mapping")
        assertExactBytesOutsideEdit(
            original: source,
            actual: harness.textView.string,
            expected: expected.source,
            message: fixture.name
        )
        XCTAssertEqual(harness.viewport.origin.x, viewportBefore.origin.x, accuracy: 0.01, "\(fixture.name): viewport x")
        XCTAssertEqual(harness.viewport.origin.y, viewportBefore.origin.y, accuracy: 0.01, "\(fixture.name): viewport y")

        // Content above the edited block cannot move. Content below it may
        // translate by the target block's legitimate reflow, but its own line
        // geometry and the editor/container widths remain invariant.
        assertRect(after.upperAnchor, equals: before.upperAnchor, accuracy: 0.75, message: fixture.name)
        XCTAssertEqual(after.lowerAnchor.minX, before.lowerAnchor.minX, accuracy: 0.75, "\(fixture.name): lower anchor x")
        XCTAssertEqual(after.lowerAnchor.width, before.lowerAnchor.width, accuracy: 0.75, "\(fixture.name): lower anchor width")
        XCTAssertEqual(after.lowerAnchor.height, before.lowerAnchor.height, accuracy: 0.75, "\(fixture.name): lower anchor height")
        XCTAssertEqual(
            after.lowerAnchor.minY - before.lowerAnchor.minY,
            after.usedRect.height - before.usedRect.height,
            accuracy: 1.5,
            "\(fixture.name): only the edited block may change downstream position"
        )
        XCTAssertEqual(after.textViewSize.width, before.textViewSize.width, accuracy: 0.01, "\(fixture.name): text view width")
        XCTAssertEqual(after.containerSize.width, before.containerSize.width, accuracy: 0.01, "\(fixture.name): container width")
        XCTAssertEqual(after.viewportSize.width, before.viewportSize.width, accuracy: 0.01, "\(fixture.name): viewport width")
        XCTAssertEqual(after.viewportSize.height, before.viewportSize.height, accuracy: 0.01, "\(fixture.name): viewport height")

        let undoManager = try XCTUnwrap(harness.textView.undoManager, "\(fixture.name): actual text view needs native undo")
        XCTAssertTrue(undoManager.canUndo, "\(fixture.name): command must register native undo")
        undoManager.undo()
        harness.settleLayoutKeepingCurrentViewport()
        XCTAssertEqual(Data(harness.textView.string.utf8), Data(source.utf8), "\(fixture.name): undo bytes")
        XCTAssertEqual(Data(harness.state.markdown.utf8), Data(source.utf8), "\(fixture.name): undo binding")

        XCTAssertTrue(undoManager.canRedo, "\(fixture.name): command must register native redo")
        undoManager.redo()
        harness.settleLayoutKeepingCurrentViewport()
        XCTAssertEqual(Data(harness.textView.string.utf8), Data(expected.source.utf8), "\(fixture.name): redo bytes")
        XCTAssertEqual(Data(harness.state.markdown.utf8), Data(expected.source.utf8), "\(fixture.name): redo binding")
    }

    private func assertHostedRepresentableModeRoundTrip(
        name: String,
        source: String,
        selectedText: String,
        command: RichEditorCommand,
        switchesToMarkdownImmediately: Bool
    ) async throws {
        let harness = try HostedRichMarkdownEditorHarness(source: source)
        defer { harness.close() }
        let selection = try range(of: selectedText, in: source)
        let expected = MarkdownSourceCommandTransformer.applying(command, to: source, selection: selection)
        XCTAssertFalse(MarkdownSourceIdentity.exactlyEqual(expected.source, source), "\(name): fixture must edit source")

        harness.textView.setSelectedRange(selection)
        harness.centerViewport(on: selection)
        let viewportBefore = harness.viewport
        harness.state.command = RichEditorCommandToken(command: command)
        if switchesToMarkdownImmediately {
            // Coalesce the command token and mode change into one SwiftUI update.
            // The command still must publish its source after updateNSView returns.
            harness.state.showsSource = true
        }

        try await waitUntil("\(name): deferred command and binding update") {
            MarkdownSourceIdentity.exactlyEqual(harness.textView.string, expected.source)
                && MarkdownSourceIdentity.exactlyEqual(harness.state.markdown, expected.source)
        }
        if !switchesToMarkdownImmediately {
            // Exercise the reported order: Page visibly reflects the command,
            // then the adjacent mode turn must expose the same raw source.
            XCTAssertEqual(harness.textView.selectedRange(), expected.selection)
            harness.state.showsSource = true
        }
        try await waitUntil("\(name): Markdown mode update") {
            harness.textView.accessibilityLabel() == "Markdown source"
        }

        XCTAssertEqual(Data(harness.textView.string.utf8), Data(expected.source.utf8), "\(name): Markdown bytes")
        XCTAssertEqual(Data(harness.state.markdown.utf8), Data(expected.source.utf8), "\(name): binding bytes")
        XCTAssertEqual(harness.textView.selectedRange(), expected.selection, "\(name): Markdown selection")
        XCTAssertEqual(harness.viewport.origin.x, viewportBefore.origin.x, accuracy: 0.01, "\(name): Markdown viewport x")
        XCTAssertEqual(harness.viewport.origin.y, viewportBefore.origin.y, accuracy: 0.75, "\(name): Markdown viewport y")

        harness.state.showsSource = false
        try await waitUntil("\(name): Page mode update") {
            harness.textView.accessibilityLabel() == "Document page"
        }
        XCTAssertEqual(Data(harness.textView.string.utf8), Data(expected.source.utf8), "\(name): Page bytes")
        XCTAssertEqual(Data(harness.state.markdown.utf8), Data(expected.source.utf8), "\(name): Page binding bytes")
        XCTAssertEqual(harness.textView.selectedRange(), expected.selection, "\(name): Page selection")
        XCTAssertEqual(harness.viewport.origin.x, viewportBefore.origin.x, accuracy: 0.01, "\(name): Page viewport x")
        XCTAssertEqual(harness.viewport.origin.y, viewportBefore.origin.y, accuracy: 0.75, "\(name): Page viewport y")

        harness.state.showsSource = true
        try await waitUntil("\(name): second Markdown mode update") {
            harness.textView.accessibilityLabel() == "Markdown source"
        }
        XCTAssertEqual(Data(harness.textView.string.utf8), Data(expected.source.utf8), "\(name): second Markdown bytes")
        XCTAssertEqual(Data(harness.state.markdown.utf8), Data(expected.source.utf8), "\(name): second binding bytes")
        XCTAssertEqual(harness.textView.selectedRange(), expected.selection, "\(name): second Markdown selection")
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 3,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw HostedRichMarkdownEditorHarnessError.timedOut(description)
    }

    private var commandFixtures: [RichEditorCommandFixture] {
        let inlineSelection = "selected cafe\u{301} 👩🏽‍💻 token"
        let plainLine = "Prefix words \(inlineSelection) suffix words"
        let multilineSelection = "selected α first 🐝\r\nselected β second 🐙"

        return [
            .init(name: "bold", command: .bold, targetBlock: plainLine, selectionText: inlineSelection),
            .init(name: "italic", command: .italic, targetBlock: plainLine, selectionText: inlineSelection),
            .init(name: "strikethrough", command: .strikethrough, targetBlock: plainLine, selectionText: inlineSelection),
            .init(
                name: "inline code",
                command: .inlineCode,
                targetBlock: "Prefix code ` sample 👩🏽‍💻 suffix",
                selectionText: "code ` sample 👩🏽‍💻"
            ),
            .init(
                name: "link",
                command: .link("https://example.com/a(test)"),
                targetBlock: plainLine,
                selectionText: inlineSelection
            ),
            .init(name: "heading 1", command: .heading1, targetBlock: plainLine, selectionText: inlineSelection),
            .init(name: "heading 2", command: .heading2, targetBlock: plainLine, selectionText: inlineSelection),
            .init(name: "heading 3", command: .heading3, targetBlock: plainLine, selectionText: inlineSelection),
            .init(name: "heading 4", command: .heading4, targetBlock: plainLine, selectionText: inlineSelection),
            .init(name: "heading 5", command: .heading5, targetBlock: plainLine, selectionText: inlineSelection),
            .init(name: "heading 6", command: .heading6, targetBlock: plainLine, selectionText: inlineSelection),
            .init(
                name: "body",
                command: .body,
                targetBlock: "### Prefix words \(inlineSelection) suffix words",
                selectionText: inlineSelection
            ),
            .init(name: "bullet list", command: .bulletList, targetBlock: multilineSelection, selectionText: multilineSelection),
            .init(name: "numbered list", command: .numberedList, targetBlock: plainLine, selectionText: inlineSelection),
            .init(name: "checklist", command: .checklist, targetBlock: plainLine, selectionText: inlineSelection),
            .init(name: "blockquote", command: .blockquote, targetBlock: multilineSelection, selectionText: multilineSelection),
            .init(name: "fenced code", command: .fencedCode, targetBlock: multilineSelection, selectionText: multilineSelection),
            .init(name: "horizontal rule", command: .horizontalRule, targetBlock: plainLine, selectionText: inlineSelection),
        ]
    }

    private func commandSource(for fixture: RichEditorCommandFixture) -> String {
        let prefix = (0..<18).map {
            String(format: "Prelude %02d — exact Unicode 😀 and stable surrounding words.", $0)
        }
        let suffix = (0..<18).map {
            String(format: "Epilogue %02d — unchanged bytes and stable surrounding words.", $0)
        }
        return (prefix + [upperAnchor, fixture.targetBlock, lowerAnchor] + suffix).joined(separator: "\r\n")
    }

    private func sourceModeReflowSource(target: String) -> String {
        let prefix = (0..<24).map { "Source prelude \($0) stable" }
        let suffix = (0..<24).map { "Source epilogue \($0) stable" }
        return (prefix + [upperAnchor, target, lowerAnchor] + suffix).joined(separator: "\r\n")
    }

    private func longSource(lineCount: Int, replacements: [Int: String]) -> String {
        (0..<lineCount).map { index in
            replacements[index] ?? String(
                format: "Paragraph %04d — stable viewport words with **existing Markdown**, Unicode café, and emoji 📝.",
                index
            )
        }.joined(separator: "\r\n")
    }

    private func offscreenControlSource(lineCount: Int, replacements: [Int: String]) -> String {
        (0..<lineCount).map { index in
            replacements[index] ?? String(
                format: "Paragraph %04d: Stable viewport text with **Markdown** and enough words to wrap predictably.",
                index
            )
        }.joined(separator: "\n")
    }

    private func range(of substring: String, in source: String) throws -> NSRange {
        let result = (source as NSString).range(of: substring)
        return try XCTUnwrap(
            result.location == NSNotFound ? nil : result,
            "Fixture must contain \(substring)"
        )
    }

    private func assertExactBytesOutsideEdit(
        original: String,
        actual: String,
        expected: String,
        message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(Data(actual.utf8), Data(expected.utf8), "\(message): complete source", file: file, line: line)
        guard let delta = MarkdownTextDelta.between(original, and: expected) else {
            XCTFail("\(message): fixture must have a minimal source delta", file: file, line: line)
            return
        }

        let originalString = original as NSString
        let actualString = actual as NSString
        let replacementLength = (delta.replacement as NSString).length
        let rebuilt = NSMutableString(string: original)
        rebuilt.replaceCharacters(in: delta.range, with: delta.replacement)
        XCTAssertEqual(
            Data((rebuilt as String).utf8),
            Data(expected.utf8),
            "\(message): computed delta must rebuild the expected source; range=\(delta.range), replacementUTF16=\(replacementLength)",
            file: file,
            line: line
        )
        let actualSuffixLocation = delta.range.location + replacementLength
        guard NSMaxRange(delta.range) <= originalString.length,
              actualSuffixLocation <= actualString.length else {
            XCTFail("\(message): delta must fit both UTF-16 buffers", file: file, line: line)
            return
        }

        let originalPrefix = originalString.substring(to: delta.range.location)
        let actualPrefix = actualString.substring(to: delta.range.location)
        let originalSuffix = originalString.substring(from: NSMaxRange(delta.range))
        let actualSuffix = actualString.substring(from: actualSuffixLocation)
        XCTAssertEqual(Data(actualPrefix.utf8), Data(originalPrefix.utf8), "\(message): bytes before intended edit", file: file, line: line)
        XCTAssertEqual(
            Data(actualSuffix.utf8),
            Data(originalSuffix.utf8),
            "\(message): bytes after intended edit; range=\(delta.range), replacementUTF16=\(replacementLength), originalUTF16=\(originalString.length), actualUTF16=\(actualString.length)",
            file: file,
            line: line
        )
    }

    private func assertRect(
        _ actual: NSRect,
        equals expected: NSRect,
        accuracy: CGFloat,
        message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: accuracy, "\(message): rect x", file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: accuracy, "\(message): rect y", file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: accuracy, "\(message): rect width", file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: accuracy, "\(message): rect height", file: file, line: line)
    }
}

private struct RichEditorCommandFixture {
    let name: String
    let command: RichEditorCommand
    let targetBlock: String
    let selectionText: String
}

private struct RichEditorLayoutSnapshot {
    let upperAnchor: NSRect
    let lowerAnchor: NSRect
    let usedRect: NSRect
    let textViewSize: NSSize
    let containerSize: NSSize
    let viewportSize: NSSize
}

@MainActor
private final class RichEditorMarkdownState {
    var markdown: String

    init(_ markdown: String) {
        self.markdown = markdown
    }
}

@MainActor
private final class HostedRichMarkdownEditorState: ObservableObject {
    @Published var markdown: String
    @Published var command: RichEditorCommandToken?
    @Published var showsSource = false
    @Published var isMounted = true

    init(markdown: String) {
        self.markdown = markdown
    }
}

private struct HostedRichMarkdownEditorRoot: View {
    @ObservedObject var state: HostedRichMarkdownEditorState

    var body: some View {
        if state.isMounted {
            RichMarkdownEditor(
                markdown: $state.markdown,
                command: state.command,
                style: .balanced,
                showsSource: state.showsSource
            )
        }
    }
}

private enum HostedRichMarkdownEditorHarnessError: LocalizedError {
    case editorNotMounted
    case timedOut(String)

    var errorDescription: String? {
        switch self {
        case .editorNotMounted:
            "The hosted RichMarkdownEditor did not mount its NSTextView."
        case .timedOut(let description):
            "Timed out waiting for \(description)."
        }
    }
}

@MainActor
private final class HostedRichMarkdownEditorHarness {
    let state: HostedRichMarkdownEditorState
    let hostingView: NSHostingView<HostedRichMarkdownEditorRoot>
    let window: RichEditorUndoWindow
    let textView: MarkdownPageTextView
    let scrollView: NSScrollView

    private var isClosed = false

    init(source: String, size: NSSize = NSSize(width: 680, height: 420)) throws {
        state = HostedRichMarkdownEditorState(markdown: source)
        hostingView = NSHostingView(rootView: HostedRichMarkdownEditorRoot(state: state))
        hostingView.frame = NSRect(origin: .zero, size: size)
        window = RichEditorUndoWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()

        var mountedTextView = Self.descendant(of: MarkdownPageTextView.self, in: hostingView)
        let deadline = Date().addingTimeInterval(1)
        while mountedTextView == nil, Date() < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
            hostingView.layoutSubtreeIfNeeded()
            mountedTextView = Self.descendant(of: MarkdownPageTextView.self, in: hostingView)
        }
        guard let mountedTextView,
              let mountedScrollView = mountedTextView.enclosingScrollView else {
            throw HostedRichMarkdownEditorHarnessError.editorNotMounted
        }
        textView = mountedTextView
        scrollView = mountedScrollView
        _ = window.makeFirstResponder(textView)
        settleLayoutKeepingCurrentViewport()
    }

    var viewport: NSRect { scrollView.contentView.bounds }

    func centerViewport(on selection: NSRange) {
        settleLayoutKeepingCurrentViewport()
        textView.scrollRangeToVisible(selection)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        state.isMounted = false
        hostingView.layoutSubtreeIfNeeded()
        window.makeFirstResponder(nil)
        window.contentView = nil
        window.close()
    }

    private func settleLayoutKeepingCurrentViewport() {
        let origin = scrollView.contentView.bounds.origin
        hostingView.layoutSubtreeIfNeeded()
        scrollView.layoutSubtreeIfNeeded()
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let requiredHeight = ceil(usedRect.maxY + textView.textContainerOrigin.y + textView.textContainerInset.height)
        textView.setFrameSize(NSSize(
            width: scrollView.contentSize.width,
            height: max(scrollView.contentSize.height, requiredHeight)
        ))
        layoutManager.ensureLayout(for: textContainer)
        scrollView.layoutSubtreeIfNeeded()
        let maximumY = max(0, textView.bounds.height - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(
            x: max(0, origin.x),
            y: min(max(0, origin.y), maximumY)
        ))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private static func descendant<ViewType: NSView>(
        of type: ViewType.Type,
        in root: NSView
    ) -> ViewType? {
        if let match = root as? ViewType { return match }
        for child in root.subviews {
            if let match = descendant(of: type, in: child) { return match }
        }
        return nil
    }
}

@MainActor
private final class RichEditorUndoWindow: NSWindow {
    private let ownedUndoManager = UndoManager()

    override var undoManager: UndoManager? { ownedUndoManager }
}

@MainActor
private final class RichEditorSelectionNotificationRecorder: NSObject {
    private(set) var changeCount = 0

    init(textView: NSTextView) {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(selectionDidChange(_:)),
            name: NSTextView.didChangeSelectionNotification,
            object: textView
        )
    }

    @objc private func selectionDidChange(_ notification: Notification) {
        changeCount += 1
    }

    func reset() {
        changeCount = 0
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

@MainActor
private final class RichEditorInteractionHarness {
    let state: RichEditorMarkdownState
    let coordinator: RichMarkdownEditor.Coordinator
    let scrollView: NSScrollView
    let textView: MarkdownPageTextView

    private let window: RichEditorUndoWindow?
    private let hostView: NSView
    private let style: DocumentStyle
    private var isClosed = false

    init(
        source: String,
        showsSource: Bool,
        style: DocumentStyle = .balanced,
        viewportSize: NSSize = NSSize(width: 500, height: 240),
        attachesToWindow: Bool = true
    ) {
        self.style = style
        state = RichEditorMarkdownState(source)
        let binding = Binding<String>(
            get: { [state] in state.markdown },
            set: { [state] in state.markdown = $0 }
        )
        coordinator = RichMarkdownEditor.Coordinator(
            markdown: binding,
            style: style,
            showsSource: showsSource
        )

        hostView = NSView(frame: NSRect(origin: .zero, size: viewportSize))
        if attachesToWindow {
            let interactionWindow = RichEditorUndoWindow(
                contentRect: NSRect(origin: .zero, size: viewportSize),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            interactionWindow.isReleasedWhenClosed = false
            interactionWindow.contentView = hostView
            window = interactionWindow
        } else {
            window = nil
        }

        scrollView = NSScrollView(frame: hostView.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        if attachesToWindow {
            hostView.addSubview(scrollView)
        }

        textView = MarkdownPageTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.drawsBackground = false
        textView.configurePage(style: style, showsSource: showsSource)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 0
        if !attachesToWindow {
            scrollView.documentView = textView
        }
        textView.string = source

        if attachesToWindow {
            scrollView.documentView = textView
        }
        coordinator.textView = textView
        coordinator.scrollView = scrollView
        coordinator.lastRenderedMarkdown = source
        coordinator.applyPresentation(to: textView, preservingViewport: false)
        settleLayoutKeepingCurrentViewport()
        textView.delegate = coordinator
        _ = window?.makeFirstResponder(textView)
        clearUndoHistory()
    }

    var viewport: NSRect { scrollView.contentView.bounds }
    var firstResponder: NSResponder? { window?.firstResponder }

    func focus(_ view: NSView) -> Bool {
        window?.makeFirstResponder(view) ?? false
    }

    func setMode(showsSource: Bool) {
        coordinator.cancelPendingPresentation()
        coordinator.showsSource = showsSource
        textView.configurePage(style: style, showsSource: showsSource)
        coordinator.applyPresentation(to: textView, preservingViewport: true)
    }

    func centerViewport(on range: NSRange) throws {
        let rect = try documentRect(for: range)
        let maximumY = max(0, textView.bounds.height - scrollView.contentView.bounds.height)
        let targetY = min(max(0, rect.midY - scrollView.contentView.bounds.height / 2), maximumY)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func documentRect(for characterRange: NSRange) throws -> NSRect {
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: characterRange,
            actualCharacterRange: nil
        )
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textView.textContainerOrigin.x
        rect.origin.y += textView.textContainerOrigin.y
        return rect
    }

    func lineFragmentWidth(at characterRange: NSRange) throws -> CGFloat {
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return textContainer.containerSize.width }
        return layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil).width
    }

    func layoutSnapshot(upperAnchor: String, lowerAnchor: String) throws -> RichEditorLayoutSnapshot {
        let upperRange = try requiredRange(of: upperAnchor)
        let lowerRange = try requiredRange(of: lowerAnchor)
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)
        return RichEditorLayoutSnapshot(
            upperAnchor: try documentRect(for: upperRange),
            lowerAnchor: try documentRect(for: lowerRange),
            usedRect: layoutManager.usedRect(for: textContainer),
            textViewSize: textView.frame.size,
            containerSize: textContainer.containerSize,
            viewportSize: scrollView.contentView.bounds.size
        )
    }

    func settleLayoutKeepingCurrentViewport() {
        let currentOrigin = scrollView.contentView.bounds.origin
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        hostView.layoutSubtreeIfNeeded()
        scrollView.layoutSubtreeIfNeeded()
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let requiredHeight = ceil(usedRect.maxY + textView.textContainerOrigin.y + textView.textContainerInset.height)
        textView.setFrameSize(NSSize(
            width: scrollView.contentSize.width,
            height: max(scrollView.contentSize.height, requiredHeight)
        ))
        layoutManager.ensureLayout(for: textContainer)
        scrollView.layoutSubtreeIfNeeded()

        let maximumY = max(0, textView.bounds.height - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(
            x: max(0, currentOrigin.x),
            y: min(max(0, currentOrigin.y), maximumY)
        ))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func clearUndoHistory() {
        textView.breakUndoCoalescing()
        textView.undoManager?.removeAllActions()
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        coordinator.cancelPendingPresentation()
        textView.delegate = nil
        coordinator.textView = nil
        coordinator.scrollView = nil
        window?.makeFirstResponder(nil)
        scrollView.documentView = nil
        window?.close()
    }

    private func requiredRange(of substring: String) throws -> NSRange {
        let result = (textView.string as NSString).range(of: substring)
        return try XCTUnwrap(result.location == NSNotFound ? nil : result, "Fixture must contain \(substring)")
    }
}
