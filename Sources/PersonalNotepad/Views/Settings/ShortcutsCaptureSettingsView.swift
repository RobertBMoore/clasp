import AppKit
import Carbon
import SwiftUI

struct ShortcutsCaptureSettingsView: View {
    @State private var shortcuts = GlobalHotKeyPreferences.shared
    @State private var recordingAction: GlobalHotKeyAction?
    @State private var recordingError: String?
    @State private var feedback = ShortcutSettingsFeedback.instruction

    private var recommendedAssignments: [GlobalHotKeyAssignment] {
        shortcuts.assignments.filter {
            $0.action.inputSource == .quickCapture || $0.action.inputSource == .clipboard
        }
    }

    private var selectionAssignments: [GlobalHotKeyAssignment] {
        shortcuts.assignments.filter { $0.action.inputSource == .selectedContent }
    }

    private var vaultAssignments: [GlobalHotKeyAssignment] {
        shortcuts.assignments.filter { $0.action.inputSource == .vaultControl }
    }

    var body: some View {
        SettingsTabPage(pane: .shortcuts) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ShortcutFeedbackSlot(feedback: feedback)
                    CaptureOverviewCard(
                        inboxShortcut: shortcuts.shortcut(for: .saveClipboardToInbox),
                        vaultShortcut: shortcuts.shortcut(for: .saveClipboardToVault)
                    )

                    ShortcutAssignmentsCard(
                        title: "Recommended shortcuts",
                        detail: "Open Quick Capture or save the clipboard to a normal or secure note.",
                        assignments: recommendedAssignments,
                        resetAll: restoreAllShortcuts,
                        registrationState: shortcuts.registrationState(for:),
                        replace: beginReplacing,
                        clear: clear,
                        restore: restore
                    )

                    if selectionAssignments.isEmpty {
                        SelectionShortcutAvailabilityCard()
                    } else {
                        ShortcutAssignmentsCard(
                            title: "One-step selection",
                            detail: "The direct-download build can copy the current selection and route it in one step.",
                            assignments: selectionAssignments,
                            registrationState: shortcuts.registrationState(for:),
                            replace: beginReplacing,
                            clear: clear,
                            restore: restore
                        )
                    }

                    if !vaultAssignments.isEmpty {
                        ShortcutAssignmentsCard(
                            title: "Vault safety",
                            detail: "Lock secure Vault notes immediately whenever you step away.",
                            assignments: vaultAssignments,
                            registrationState: shortcuts.registrationState(for:),
                            replace: beginReplacing,
                            clear: clear,
                            restore: restore
                        )
                    }

                    MacOSServicesCard()
                }
                .padding(.horizontal, 1)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.automatic)
        }
        .sheet(item: $recordingAction, onDismiss: { recordingError = nil }) { action in
            ShortcutRecorderSheet(
                action: action,
                currentShortcut: shortcuts.shortcut(for: action),
                errorMessage: recordingError,
                capture: { accept($0, for: action) },
                cancel: { recordingAction = nil }
            )
        }
    }

    private func beginReplacing(_ action: GlobalHotKeyAction) {
        recordingError = nil
        recordingAction = action
        feedback = .instruction
    }

    private func accept(_ shortcut: GlobalHotKeyShortcut, for action: GlobalHotKeyAction) -> Bool {
        do {
            try shortcuts.replace(shortcut, for: action)
            recordingError = nil
            recordingAction = nil
            feedback = feedbackAfterRegistration(
                for: action,
                success: "\(action.title) now uses \(shortcut.displayName)."
            )
            return true
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? "Clasp could not use that shortcut. Try a different combination."
            recordingError = message
            feedback = .error(message)
            return false
        }
    }

    private func clear(_ action: GlobalHotKeyAction) {
        shortcuts.clear(action)
        feedback = .success("\(action.title) no longer has a global shortcut.")
    }

    private func restore(_ action: GlobalHotKeyAction) {
        shortcuts.reset(action)
        feedback = feedbackAfterRegistration(
            for: action,
            success: "\(action.title) was restored to its Clasp default."
        )
    }

    private func restoreAllShortcuts() {
        shortcuts.resetAll()
        if let failedAction = shortcuts.assignments.first(where: {
            shortcuts.registrationState(for: $0.action) == .unavailable
        })?.action {
            feedback = .error(registrationUnavailableMessage(for: failedAction))
        } else {
            feedback = .success("All editable shortcuts were restored to their Clasp defaults.")
        }
    }

    private func feedbackAfterRegistration(
        for action: GlobalHotKeyAction,
        success: String
    ) -> ShortcutSettingsFeedback {
        if shortcuts.registrationState(for: action) == .unavailable {
            return .error(registrationUnavailableMessage(for: action))
        }
        return .success(success)
    }

    private func registrationUnavailableMessage(for action: GlobalHotKeyAction) -> String {
        "\(action.title) could not activate because another app or macOS is already using that shortcut. Choose Replace to try another."
    }
}

private enum ShortcutSettingsFeedback: Equatable {
    case instruction
    case success(String)
    case error(String)

    var message: String {
        switch self {
        case .instruction:
            "Choose Replace, then press a shortcut that includes Control, Option, or Command."
        case .success(let message), .error(let message):
            message
        }
    }

    var systemImage: String {
        switch self {
        case .instruction: "keyboard"
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .instruction: .secondary
        case .success: .green
        case .error: .orange
        }
    }
}

private struct ShortcutFeedbackSlot: View {
    let feedback: ShortcutSettingsFeedback

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: feedback.systemImage)
                .foregroundStyle(feedback.tint)
                .frame(width: 18)
                .accessibilityHidden(true)
            ScrollView(.vertical) {
                Text(feedback.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
            .scrollIndicators(.automatic)
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.horizontal, 14)
        .frame(
            maxWidth: .infinity,
            minHeight: SettingsLayoutMetrics.shortcutFeedbackHeight,
            maxHeight: SettingsLayoutMetrics.shortcutFeedbackHeight,
            alignment: .leading
        )
        .background(feedback.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(feedback.tint.opacity(0.22), lineWidth: 1)
        }
    }
}

private struct CaptureOverviewCard: View {
    let inboxShortcut: GlobalHotKeyShortcut?
    let vaultShortcut: GlobalHotKeyShortcut?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label("Where captures go", systemImage: "arrow.triangle.branch")
                    .font(.headline)
                Spacer()
                Text("You choose on every route")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                CaptureDestinationSummary(
                    title: "Normal note",
                    destination: "Inbox",
                    detail: "A searchable Markdown note stored with the rest of your regular notes.",
                    systemImage: AppIcon.Navigation.inbox,
                    tint: .blue
                )
                CaptureDestinationSummary(
                    title: "Secure note",
                    destination: "Vault",
                    detail: "An encrypted note that disappears from memory when the secure Vault locks.",
                    systemImage: AppIcon.Navigation.vault,
                    tint: .purple
                )
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Clipboard shortcuts are copy-first")
                    .font(.callout.weight(.medium))

                HStack(alignment: .top, spacing: 12) {
                    ClipboardFlowStep(number: 1, title: "Select", detail: "Choose content in any app.")
                    ClipboardFlowStep(number: 2, title: "Copy", detail: "Press Command-C.")
                    ClipboardShortcutFlowStep(
                        inboxShortcut: inboxShortcut,
                        vaultShortcut: vaultShortcut
                    )
                }
            }

            Divider()

            HStack(spacing: 8) {
                Text("Supported")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                ForEach(CaptureShortcutContentKind.allCases, id: \.self) { kind in
                    Text(kind.title)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary.opacity(0.26), in: Capsule())
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .settingsCardSurface()
    }
}

private struct ClipboardFlowStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tint)
                .frame(width: 20, height: 20)
                .background(.tint.opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct ClipboardShortcutFlowStep: View {
    let inboxShortcut: GlobalHotKeyShortcut?
    let vaultShortcut: GlobalHotKeyShortcut?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("3")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tint)
                .frame(width: 20, height: 20)
                .background(.tint.opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("Press a Clasp shortcut")
                    .font(.caption.weight(.semibold))
                HStack(spacing: 6) {
                    ClipboardFlowKeycap(label: "Inbox", shortcut: inboxShortcut)
                    ClipboardFlowKeycap(label: "Vault", shortcut: vaultShortcut)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct ClipboardFlowKeycap: View {
    let label: String
    let shortcut: GlobalHotKeyShortcut?

    var body: some View {
        Text("\(label) \(shortcut?.symbolDisplayName ?? "Not set")")
            .font(.caption2.weight(.medium).monospaced())
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.background, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(.separator.opacity(0.65), lineWidth: 1)
            }
    }
}

private struct CaptureDestinationSummary: View {
    let title: String
    let destination: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.body.weight(.medium))
                    Text(destination)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(tint)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct ShortcutAssignmentsCard: View {
    let title: String
    let detail: String
    let assignments: [GlobalHotKeyAssignment]
    var resetAll: (() -> Void)?
    let registrationState: (GlobalHotKeyAction) -> GlobalHotKeyRegistrationState
    let replace: (GlobalHotKeyAction) -> Void
    let clear: (GlobalHotKeyAction) -> Void
    let restore: (GlobalHotKeyAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if let resetAll {
                    Button("Restore All", action: resetAll)
                        .controlSize(.small)
                        .help("Restore every editable shortcut to its Clasp default")
                }
            }
            .padding(16)

            ForEach(Array(assignments.enumerated()), id: \.element.id) { index, assignment in
                if index > 0 { Divider().padding(.leading, 58) }
                ShortcutAssignmentRow(
                    assignment: assignment,
                    registrationState: registrationState(assignment.action),
                    replace: { replace(assignment.action) },
                    clear: { clear(assignment.action) },
                    restore: { restore(assignment.action) }
                )
            }
        }
        .settingsCardSurface()
    }
}

private struct ShortcutAssignmentRow: View {
    let assignment: GlobalHotKeyAssignment
    let registrationState: GlobalHotKeyRegistrationState
    let replace: () -> Void
    let clear: () -> Void
    let restore: () -> Void

    private var action: GlobalHotKeyAction { assignment.action }

    private var supportedContent: String? {
        guard !action.contentKinds.isEmpty else { return nil }
        return action.contentKinds.map(\.title).joined(separator: ", ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: action.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(action.tint)
                .frame(width: 30, height: 30)
                .background(action.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(action.title)
                        .font(.body.weight(.medium))
                    if let destination = action.destination {
                        Text(destination.shortTitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(destination.tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(destination.tint.opacity(0.09), in: Capsule())
                    }
                }
                Text(action.settingsDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(minHeight: 30, alignment: .topLeading)
                if let supportedContent {
                    Text(supportedContent)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 9) {
                ShortcutKeycap(shortcut: assignment.shortcut)

                ShortcutRegistrationStatus(state: registrationState)

                HStack(spacing: 6) {
                    Button("Replace", action: replace)
                    Button("Clear", action: clear)
                        .disabled(!assignment.isEnabled)
                    Button("Restore", action: restore)
                        .disabled(!assignment.isCustomized)
                }
                .controlSize(.small)
            }
            .frame(width: 218, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(
            minHeight: SettingsLayoutMetrics.shortcutRowMinimumHeight,
            alignment: .leading
        )
    }
}

private struct ShortcutRegistrationStatus: View {
    let state: GlobalHotKeyRegistrationState

    private var presentation: (text: String, systemImage: String, tint: Color) {
        switch state {
        case .disabled:
            ("Shortcut off", "minus.circle", .secondary)
        case .notRegisteredYet:
            ("Checking availability…", "clock", .secondary)
        case .registered:
            ("Active", "checkmark.circle.fill", .green)
        case .unavailable:
            ("In use by another app", "exclamationmark.triangle.fill", .orange)
        }
    }

    var body: some View {
        Label(presentation.text, systemImage: presentation.systemImage)
            .font(.caption2.weight(.medium))
            .foregroundStyle(presentation.tint)
            .lineLimit(1)
            .frame(height: 14, alignment: .trailing)
            .accessibilityLabel("Shortcut status")
            .accessibilityValue(presentation.text)
    }
}

private struct ShortcutKeycap: View {
    let shortcut: GlobalHotKeyShortcut?

    var body: some View {
        Text(shortcut?.symbolDisplayName ?? "Not set")
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(shortcut == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
            .frame(minWidth: SettingsLayoutMetrics.shortcutKeycapMinimumWidth, minHeight: 34)
            .background(.background, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(.separator.opacity(0.72), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
            .accessibilityLabel("Current shortcut")
            .accessibilityValue(shortcut?.displayName ?? "Not set")
    }
}

private struct SelectionShortcutAvailabilityCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "selection.pin.in.out")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("One-step selection")
                    .font(.headline)
                Text("This build uses macOS Services for selected content. The direct-download build can also offer editable one-step selection shortcuts after Accessibility approval.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .settingsCardSurface()
    }
}

private struct MacOSServicesCard: View {
    private var serviceChoiceDetail: String {
        MacOSCaptureServiceDescriptor.all.map(\.title).joined(separator: " or ") + "."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Label("Right-click Services", systemImage: "cursorarrow.click.2")
                    .font(.headline)
                Text("Managed by macOS")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary.opacity(0.25), in: Capsule())
                Spacer()
            }

            Text("In an app that exposes Services for the selected content:")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 16) {
                ServiceStep(number: 1, title: "Select", detail: "Highlight text, a link, or an image.")
                ServiceStep(number: 2, title: "Right-click", detail: "Open Services in the contextual menu.")
                ServiceStep(number: 3, title: "Choose", detail: serviceChoiceDetail)
            }

            VStack(spacing: 8) {
                ForEach(MacOSCaptureServiceDescriptor.all) { service in
                    HStack(spacing: 10) {
                        Image(systemName: service.destination.systemImage)
                            .foregroundStyle(service.destination.tint)
                            .frame(width: 18)
                        Text(service.title)
                            .font(.callout.weight(.medium))
                        Spacer()
                        Text("Default \(service.defaultShortcut)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            Text("macOS decides whether Services appear and where they are placed. In many apps these actions remain inside the Services submenu rather than at the top level.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Open Keyboard Settings") {
                    KeyboardSettingsOpener.open()
                }
                .help("Open macOS Keyboard Settings to review Services shortcuts")

                if DistributionCapabilities.supportsAccessibilitySelectionCapture {
                    Button("Open Accessibility Settings") {
                        KeyboardSettingsOpener.openAccessibility()
                    }
                    .help("Allow one-step selected-content capture in the direct-download build")
                }

                Spacer()

                Text("Text, Markdown, styled text, links, and images")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .settingsCardSurface()
    }
}

private struct ServiceStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tint)
                .frame(width: 24, height: 24)
                .background(.tint.opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct ShortcutRecorderSheet: View {
    let action: GlobalHotKeyAction
    let currentShortcut: GlobalHotKeyShortcut?
    let errorMessage: String?
    let capture: (GlobalHotKeyShortcut) -> Bool
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "keyboard.badge.ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 38, height: 38)
                    .background(.tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Replace \(action.title)")
                        .font(.headline)
                    Text("Press the complete shortcut now")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary.opacity(0.20))
                VStack(spacing: 6) {
                    Text("Waiting for keys…")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("Current: \(currentShortcut?.displayName ?? "Not set")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ShortcutKeyCaptureView(capture: capture, cancel: cancel)
                    .accessibilityLabel("Shortcut recorder")
                    .accessibilityHint("Press a shortcut using Control, Option, or Command. Press Escape to cancel.")
            }
            .frame(minHeight: 82)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: errorMessage == nil ? "info.circle" : "exclamationmark.triangle.fill")
                    .foregroundStyle(errorMessage == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text(errorMessage ?? "Use Control, Option, or Command with another key. Escape cancels without changing anything.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: SettingsLayoutMetrics.shortcutRecorderMessageMinimumHeight,
                alignment: .topLeading
            )

            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(
            width: SettingsLayoutMetrics.shortcutRecorderDefaultSize.width,
            alignment: .topLeading
        )
        .frame(
            minHeight: SettingsLayoutMetrics.shortcutRecorderDefaultSize.height,
            alignment: .topLeading
        )
    }
}

private struct ShortcutKeyCaptureView: NSViewRepresentable {
    let capture: (GlobalHotKeyShortcut) -> Bool
    let cancel: () -> Void

    func makeNSView(context: Context) -> ShortcutKeyCaptureNSView {
        let view = ShortcutKeyCaptureNSView()
        view.capture = capture
        view.cancel = cancel
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel("Shortcut recorder")
        view.setAccessibilityHelp(
            "Press a shortcut using Control, Option, or Command. Press Escape to cancel."
        )
        return view
    }

    func updateNSView(_ nsView: ShortcutKeyCaptureNSView, context: Context) {
        nsView.capture = capture
        nsView.cancel = cancel
        nsView.requestFocus()
    }
}

@MainActor
private final class ShortcutKeyCaptureNSView: NSView {
    var capture: ((GlobalHotKeyShortcut) -> Bool)?
    var cancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        requestFocus()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        handle(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handle(event)
        return true
    }

    func requestFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window?.firstResponder !== self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    private func handle(_ event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape {
            cancel?()
            return
        }
        guard let shortcut = GlobalHotKeyShortcut(event: event) else {
            NSSound.beep()
            requestFocus()
            return
        }
        if capture?(shortcut) == false {
            requestFocus()
        }
    }
}

private extension GlobalHotKeyAction {
    var settingsDetail: String {
        if self == .lockVault {
            return "Immediately lock and hide secure Vault notes."
        }
        return detail
    }

    var systemImage: String {
        switch inputSource {
        case .quickCapture: "square.and.pencil"
        case .selectedContent: "selection.pin.in.out"
        case .clipboard: "doc.on.clipboard"
        case .vaultControl: "lock.fill"
        }
    }

    var tint: Color {
        destination?.tint ?? (inputSource == .vaultControl ? .purple : .blue)
    }
}

private extension CaptureDestination {
    var shortTitle: String {
        switch self {
        case .inbox: "Inbox"
        case .vault: "Vault"
        }
    }

    var systemImage: String {
        switch self {
        case .inbox: AppIcon.Navigation.inbox
        case .vault: AppIcon.Navigation.vault
        }
    }

    var tint: Color {
        switch self {
        case .inbox: .blue
        case .vault: .purple
        }
    }
}
