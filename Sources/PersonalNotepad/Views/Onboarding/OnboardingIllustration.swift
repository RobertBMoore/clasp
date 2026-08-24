import SwiftUI

struct OnboardingIllustration: View {
    let step: OnboardingStep
    @State private var shortcutPreferences = GlobalHotKeyPreferences.shared

    var body: some View {
        Group {
            switch step {
            case .welcome: welcome
            case .quickCapture: quickCapture
            case .clipboard: clipboard
            case .selection: selection
            case .organize: organize
            case .vault: vault
            case .backup: backup
            }
        }
        .frame(maxWidth: .infinity, minHeight: 188, maxHeight: 188)
        .padding(18)
        .background(.quaternary.opacity(0.30), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.separator.opacity(0.45))
        }
        .accessibilityHidden(true)
    }

    private var welcome: some View {
        HStack(spacing: 14) {
            FeatureTile(symbol: "doc.on.clipboard.fill", title: "Anything", detail: "Text, links & images", tint: .blue)
            FeatureTile(symbol: AppIcon.Capture.clipboard, title: "Add to Clasp", detail: "Everyday Inbox", tint: .teal)
            FeatureTile(symbol: AppIcon.Capture.clipboardToVault, title: "Add to Vault", detail: "Encrypted", tint: .green)
        }
    }

    private var quickCapture: some View {
        HStack(spacing: 18) {
            KeycapGroup(keys: quickCaptureKeycaps, label: "From anywhere")
            FlowArrow()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Quick Capture", systemImage: AppIcon.Capture.quick)
                        .font(.callout.bold())
                    Spacer()
                    Text("Inbox  |  Vault")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Capsule().fill(.secondary.opacity(0.30)).frame(width: 210, height: 7)
                    Capsule().fill(.secondary.opacity(0.18)).frame(width: 155, height: 7)
                }
                HStack {
                    Text("Esc cancels")
                    Spacer()
                    Text("⌘↩ saves")
                        .fontWeight(.semibold)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: 330)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
        }
    }

    private var clipboard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 11) {
                WalkthroughStage(number: 1, symbol: AppIcon.Capture.clipboard, title: "Copy anything", detail: "Text, link, or image", tint: .blue)
                FlowArrow()
                WalkthroughStage(number: 2, symbol: "arrow.triangle.branch", title: "Choose home", detail: "Inbox or Vault", tint: .orange)
                FlowArrow()
                WalkthroughStage(number: 3, symbol: "tag.fill", title: "Typed & tagged", detail: "Ready to search", tint: .green)
            }
            Label("One-time capture • No monitoring • Classification stays on this Mac", systemImage: "eye.slash.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var selection: some View {
        HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Select text, a link, or an image.")
                    .font(.callout)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.25))
                Text("Selected in Mail, Safari, Notes, or another Mac app")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            FlowArrow()
            VStack(alignment: .leading, spacing: 7) {
                MenuMockRow(title: "Copy", keys: "⌘C")
                Divider()
                MenuMockRow(title: "Services", keys: "›")
                MenuMockRow(
                    title: inboxService.title,
                    keys: "Default \(inboxService.defaultShortcut)"
                )
                    .foregroundStyle(.blue)
                MenuMockRow(
                    title: vaultService.title,
                    keys: "Default \(vaultService.defaultShortcut)"
                )
                    .foregroundStyle(.green)
                Text("Change Service shortcuts in System Settings")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(width: 260)
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
    }

    private var organize: some View {
        HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 9) {
                Label("Inbox", systemImage: AppIcon.Navigation.inbox)
                    .font(.headline)
                NoteRowMock(title: "Call notes", detail: "Follow up with…", pinned: true)
                NoteRowMock(title: "Useful link", detail: "https://…", pinned: false)
            }
            .padding(12)
            .frame(width: 250)
            .background(.background, in: RoundedRectangle(cornerRadius: 11))
            FlowArrow()
            VStack(alignment: .leading, spacing: 9) {
                OrganizeAction(symbol: AppIcon.Content.link, title: "Link + domain")
                OrganizeAction(symbol: AppIcon.Content.image, title: "Image + OCR")
                OrganizeAction(symbol: AppIcon.Content.checklist, title: "Checklist + task")
                OrganizeAction(symbol: AppIcon.Content.code, title: "Code + language")
            }
        }
    }

    private var vault: some View {
        HStack(spacing: 16) {
            SecurityCard(symbol: AppIcon.Content.note, title: "Inbox", detail: "Readable Markdown", tint: .blue)
            VStack(spacing: 8) {
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(.secondary)
                Text("Choose intentionally")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            SecurityCard(symbol: AppIcon.Vault.destination, title: "Vault", detail: "Encrypted at rest", tint: .green)
            VStack(spacing: 7) {
                Text(DistributionCapabilities.supportsAccessibilitySelectionCapture
                    ? shortcutSymbols(.captureSelectionToVault)
                    : vaultService.defaultShortcut)
                    .font(.callout.monospaced().bold())
                Label("Touch ID", systemImage: "touchid")
                Label("Auto-lock", systemImage: "timer")
                Label("Lock now", systemImage: AppIcon.Vault.lockNow)
            }
            .font(.caption.weight(.medium))
            .padding(11)
            .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var backup: some View {
        HStack(spacing: 18) {
            WalkthroughStage(number: 1, symbol: "folder.fill", title: "Regular notes", detail: "Back up Markdown", tint: .blue)
            FlowArrow()
            WalkthroughStage(number: 2, symbol: AppIcon.Vault.secureNote, title: "Vault export", detail: "Encrypted file", tint: .green)
            FlowArrow()
            WalkthroughStage(number: 3, symbol: AppIcon.Vault.recoveryKey, title: "Recovery key", detail: "Store separately", tint: .orange)
        }
    }

    private var inboxService: MacOSCaptureServiceDescriptor {
        MacOSCaptureServiceDescriptor.all[0]
    }

    private var vaultService: MacOSCaptureServiceDescriptor {
        MacOSCaptureServiceDescriptor.all[1]
    }

    private var quickCaptureKeycaps: [String] {
        shortcutPreferences.shortcut(for: .quickCapturePrimary)?.keycapLabels ?? ["Not set"]
    }

    private func shortcutSymbols(_ action: GlobalHotKeyAction) -> String {
        shortcutPreferences.shortcut(for: action)?.symbolDisplayName ?? "Not set"
    }
}

private struct FeatureTile: View {
    let symbol: String
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 28))
                .foregroundStyle(tint)
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct WalkthroughStage: View {
    let number: Int
    let symbol: String
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(spacing: 7) {
            ZStack(alignment: .topLeading) {
                Image(systemName: symbol)
                    .font(.system(size: 25))
                    .foregroundStyle(tint)
                    .frame(width: 54, height: 45)
                Text("\(number)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(tint, in: Circle())
                    .offset(x: -6, y: -5)
            }
            Text(title).font(.callout.bold())
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 115)
        .padding(8)
        .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 11))
    }
}

private struct FlowArrow: View {
    var body: some View {
        Image(systemName: "arrow.right")
            .font(.headline)
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}

private struct KeycapGroup: View {
    let keys: [String]
    let label: String

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 6) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 11)
                        .frame(height: 39)
                        .background(.background, in: RoundedRectangle(cornerRadius: 7))
                        .overlay { RoundedRectangle(cornerRadius: 7).stroke(.separator) }
                        .shadow(color: .black.opacity(0.10), radius: 1, y: 2)
                }
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct MenuMockRow: View {
    let title: String
    let keys: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(keys).foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}

private struct NoteRowMock: View {
    let title: String
    let detail: String
    let pinned: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: pinned ? AppIcon.Navigation.pinned : AppIcon.Content.note)
                .foregroundStyle(pinned ? .orange : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct OrganizeAction: View {
    let symbol: String
    let title: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.callout.weight(.medium))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SecurityCard: View {
    let symbol: String
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(tint)
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 140, height: 118)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }
}
