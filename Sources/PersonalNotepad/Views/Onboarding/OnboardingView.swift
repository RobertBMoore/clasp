import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: OnboardingStep = .welcome
    @State private var capturingClipboard = false
    @State private var vaultWorking = false
    @State private var shortcutPreferences = GlobalHotKeyPreferences.shared

    var body: some View {
        HStack(spacing: 0) {
            OnboardingProgressRail(selection: $step)
                .frame(minWidth: 180, idealWidth: 200, maxWidth: 230)

            Divider()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("STEP \(step.rawValue + 1) OF \(OnboardingStep.allCases.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(step.tint)
                            .tracking(0.8)

                        VStack(alignment: .leading, spacing: 7) {
                            Text(step.title)
                                .font(.largeTitle.bold())
                            Text(step.message)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        OnboardingIllustration(step: step)
                            .id(step)
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))

                        Label(step.tip, systemImage: "lightbulb.fill")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.yellow.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))

                        stepAction
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()
                navigationBar
            }
        }
        .frame(minWidth: 720, idealWidth: 900, minHeight: 520, idealHeight: 640)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: step)
        .appStateErrorAlert(appState)
    }

    @ViewBuilder
    private var stepAction: some View {
        switch step {
        case .quickCapture:
            Button("Try Quick Capture") {
                openWindow(id: "quick-capture")
            }
            .buttonStyle(.borderedProminent)

        case .clipboard:
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    Button("Add Current Clipboard to Clasp") {
                        captureClipboardToInbox()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(capturingClipboard)
                    Button("Add to Vault") {
                        captureClipboardToVault()
                    }
                    .buttonStyle(.bordered)
                    .disabled(capturingClipboard)
                    if capturingClipboard {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Capturing clipboard")
                    }
                }
                Text("These buttons read the current text or image once. Vault capture unlocks when needed and follows your configured safe-clear setting, including Never.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let status = appState.statusMessage {
                Label(status, systemImage: "info.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }

        case .selection:
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    if DistributionCapabilities.supportsAccessibilitySelectionCapture {
                        Button("Open Accessibility Settings") {
                            KeyboardSettingsOpener.openAccessibility()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if DistributionCapabilities.supportsAccessibilitySelectionCapture {
                        Button("Open Service Settings") {
                            KeyboardSettingsOpener.open()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Open Service Settings") {
                            KeyboardSettingsOpener.open()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                Text(DistributionCapabilities.supportsAccessibilitySelectionCapture
                    ? "\(shortcutWords(.captureSelectionToInbox)) creates a normal Inbox note; \(shortcutWords(.captureSelectionToVault)) creates a secure Vault note. Accessibility lets Clasp issue one Copy command for the current selection. The right-click Services remain available without it."
                    : "Choose \(MacOSCaptureServiceDescriptor.all[0].title) or \(MacOSCaptureServiceDescriptor.all[1].title) from the source app’s Services menu. This build does not request Accessibility permission or simulate Copy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .vault:
            VStack(alignment: .leading, spacing: 7) {
                if appState.isVaultUnlocked {
                    Label("Vault Ready", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        guard !vaultWorking else { return }
                        vaultWorking = true
                        Task {
                            _ = await appState.unlockVault()
                            vaultWorking = false
                        }
                    } label: {
                        if vaultWorking {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Unlocking Vault…")
                            }
                        } else {
                            Text("Set Up or Unlock Vault")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vaultWorking)
                }
                Text("macOS asks for Touch ID or your login password. The device-only key stays in Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        default:
            EmptyView()
        }
    }

    private var navigationBar: some View {
        HStack {
            Button("Back") { move(by: -1) }
                .disabled(step == .welcome)

            Spacer()

            Text(step.shortTitle)
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()

            if step != .backup {
                Button("Continue") { move(by: 1) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Finish & Try Quick Capture") {
                    OnboardingPreferences().markComplete()
                    dismissWindow(id: "onboarding")
                    openWindow(id: "quick-capture")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }

    private func shortcutWords(_ action: GlobalHotKeyAction) -> String {
        shortcutPreferences.shortcut(for: action)?
            .displayName.replacingOccurrences(of: "-", with: "–") ?? "No shortcut"
    }

    private func move(by offset: Int) {
        let next = min(max(step.rawValue + offset, 0), OnboardingStep.allCases.count - 1)
        guard let destination = OnboardingStep(rawValue: next) else { return }
        step = destination
    }

    private func captureClipboardToInbox() {
        guard !capturingClipboard else { return }
        capturingClipboard = true
        appState.saveClipboardToInbox()
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            capturingClipboard = false
        }
    }

    private func captureClipboardToVault() {
        guard !capturingClipboard else { return }
        capturingClipboard = true
        Task {
            await appState.saveClipboardToVaultAndClear()
            capturingClipboard = false
        }
    }
}

private struct OnboardingProgressRail: View {
    @Binding var selection: OnboardingStep

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Label("Clasp", systemImage: AppIcon.Utility.app)
                    .font(.title2.bold())
                Text("A visual quick start")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(spacing: 5) {
                    ForEach(OnboardingStep.allCases) { step in
                        Button {
                            selection = step
                        } label: {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(selection == step ? step.tint : Color.secondary.opacity(0.12))
                                        .frame(width: 28, height: 28)
                                    Image(systemName: step.symbol)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(selection == step ? .white : .secondary)
                                }
                                Text(step.shortTitle)
                                    .font(.callout.weight(selection == step ? .semibold : .regular))
                                    .foregroundStyle(selection == step ? .primary : .secondary)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                            .background(
                                selection == step ? step.tint.opacity(0.10) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Step \(step.rawValue + 1), \(step.shortTitle)")
                        .accessibilityAddTraits(selection == step ? .isSelected : [])
                    }
                }
            }

            Text("You can reopen this guide anytime from Help.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(.regularMaterial)
    }
}
