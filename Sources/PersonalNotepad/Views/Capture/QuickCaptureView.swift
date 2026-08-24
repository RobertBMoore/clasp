import SwiftUI

struct QuickCaptureView: View {
    let appState: AppState
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var text = ""
    @State private var destination: CaptureDestination = .inbox
    @FocusState private var editorFocused: Bool
    @State private var saving = false
    @State private var capturingClipboard = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Quick Capture", systemImage: destination == .vault ? AppIcon.Capture.clipboardToVault : AppIcon.Capture.quick)
                    .font(.headline)
                Spacer()
                Picker("Destination", selection: $destination) {
                    Text("Inbox").tag(CaptureDestination.inbox)
                    Text("Vault").tag(CaptureDestination.vault)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
                .accessibilityLabel("Capture destination")
            }

            TextEditor(text: $text)
                .font(.body)
                .focused($editorFocused)
                .frame(minHeight: 170)
                .padding(6)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Quick capture text")
                .accessibilityHint("Press Command-Return to save")

            if let status = appState.statusMessage {
                Label(status, systemImage: "info.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
                    .accessibilityLabel("Status: \(status)")
            }

            actionBar
        }
        .padding(18)
        .frame(minWidth: 440, idealWidth: 520, minHeight: 330, idealHeight: 360)
        .animation(.easeOut(duration: 0.18), value: appState.statusMessage)
        .onAppear {
            text = appState.quickCaptureSeed
            destination = appState.quickCaptureDestination
            DispatchQueue.main.async { editorFocused = true }
        }
        .onExitCommand { cancel() }
        .onReceive(NotificationCenter.default.publisher(for: .lockVault)) { _ in
            guard destination == .vault else { return }
            text = ""
            dismissWindow(id: "quick-capture")
        }
        .onChange(of: appState.isVaultUnlocked) { wasUnlocked, isUnlocked in
            guard wasUnlocked, !isUnlocked, destination == .vault else { return }
            text = ""
            dismissWindow(id: "quick-capture")
        }
        .appStateErrorAlert(appState)
    }

    private var actionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                captureClipboardButton
                Spacer()
                draftButtons
            }

            VStack(alignment: .leading, spacing: 10) {
                captureClipboardButton
                draftButtons
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var captureClipboardButton: some View {
        Button { captureClipboardToVault() } label: {
            if capturingClipboard {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Capturing…")
                }
            } else {
                Label("Capture Clipboard to Vault", systemImage: AppIcon.Capture.clipboardToVault)
            }
        }
        .disabled(saving || capturingClipboard)
        .help("Save the clipboard as a Vault note, then safely clear only the captured value when safe clearing is enabled in Settings.")
    }

    private var draftButtons: some View {
        HStack {
            Button("Cancel") { cancel() }
                .keyboardShortcut(.cancelAction)
            Button { save() } label: {
                if saving {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Saving…")
                    }
                } else {
                    Text("Save")
                }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(
                saving
                    || capturingClipboard
                    || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
    }

    private func captureClipboardToVault() {
        guard !saving, !capturingClipboard else { return }
        capturingClipboard = true
        Task {
            await appState.saveClipboardToVaultAndClear()
            capturingClipboard = false
        }
    }

    private func save() {
        guard !saving, !capturingClipboard else { return }
        saving = true
        Task {
            if await appState.saveQuickCapture(body: text, destination: destination) {
                text = ""
                dismissWindow(id: "quick-capture")
            }
            saving = false
        }
    }

    private func cancel() {
        text = ""
        dismissWindow(id: "quick-capture")
    }
}
