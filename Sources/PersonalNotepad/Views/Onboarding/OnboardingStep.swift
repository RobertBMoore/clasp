import SwiftUI

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case quickCapture
    case clipboard
    case selection
    case organize
    case vault
    case backup

    var id: Int { rawValue }

    var shortTitle: String {
        switch self {
        case .welcome: "Welcome"
        case .quickCapture: "Quick Capture"
        case .clipboard: "Clipboard"
        case .selection: "Right-Click"
        case .organize: "Organize"
        case .vault: "Vault"
        case .backup: "Back Up"
        }
    }

    var title: String {
        switch self {
        case .welcome: "Clasp Anything in Two Clicks"
        case .quickCapture: "One Shortcut Opens Clasp"
        case .clipboard: "Copy Anything, Choose Its Home"
        case .selection: "Right-Click Text, Images, or Links"
        case .organize: "Clasp Organizes as It Captures"
        case .vault: "Use the Vault for Sensitive Notes"
        case .backup: "Keep Your Notes Recoverable"
        }
    }

    @MainActor
    var message: String {
        switch self {
        case .welcome:
            "Capture text, links, code, checklists, contacts, and images. Send ordinary material to Clasp or sensitive material directly to the encrypted Vault."
        case .quickCapture:
            "Press \(shortcutWords(.quickCapturePrimary)) from any app, type, then press Command–Return. New captures go to Inbox unless you choose Vault."
        case .clipboard:
            "Copy text, Markdown, a link, or an image. Press \(shortcutWords(.saveClipboardToInbox)) for Inbox or \(shortcutWords(.saveClipboardToVault)) for a secure Vault note. Menu-bar and Dock actions offer the same choices."
        case .selection:
            if DistributionCapabilities.supportsAccessibilitySelectionCapture {
                "Select text, an image, or a link. Press \(shortcutWords(.captureSelectionToInbox)) for a normal Inbox note or \(shortcutWords(.captureSelectionToVault)) for a secure Vault note. You can also use either action from the source app’s Services menu."
            } else {
                "Select text, an image, or a link, then choose \(inboxService.title) or \(vaultService.title) from the source app’s Services menu."
            }
        case .organize:
            "Clasp identifies and tags incoming content locally. Page mode styles common AI-generated headings, emphasis, links, lists, checklists, quotes, and code while portable Markdown remains the canonical source."
        case .vault:
            if DistributionCapabilities.supportsAccessibilitySelectionCapture {
                "Press \(shortcutWords(.captureSelectionToVault)) to add selected content directly to Vault. Titles, tags, image bytes, recognized text, and bodies are encrypted at rest."
            } else {
                "Use \(vaultService.title) from the source app’s Services menu to send selected content to Vault. Titles, tags, image bytes, recognized text, and bodies are encrypted at rest."
            }
        case .backup:
            "Regular notes are portable Markdown files. Vault backups are encrypted exports with a recovery key shown only once."
        }
    }

    @MainActor
    var tip: String {
        switch self {
        case .welcome:
            "Two destinations, everywhere: Add to Clasp for everyday material; Add to Clasp Vault when it is sensitive."
        case .quickCapture:
            "If another app owns \(shortcutWords(.quickCapturePrimary)), use \(shortcutWords(.quickCaptureFallback)). You can always click Clasp in the menu bar or right-click its Dock icon."
        case .clipboard:
            "Clasp reads once when triggered. It never watches the clipboard or keeps history, and it accepts images up to 25 MB."
        case .selection:
            if DistributionCapabilities.supportsAccessibilitySelectionCapture {
                "Choose the paired Normal and Protected selection shortcuts that fit your Mac in Settings. Approve Clasp once in Privacy & Security › Accessibility so a shortcut can issue one Copy command; Clasp never monitors your keyboard."
            } else {
                "Services receive only the selection you explicitly send. Clasp never requests Accessibility permission or monitors your keyboard."
            }
        case .organize:
            "Use the Page / Markdown switch above any note. Both views edit the same source, and Documents settings change its presentation without adding style data to the file."
        case .vault:
            if DistributionCapabilities.supportsAccessibilitySelectionCapture {
                "Use \(shortcutSymbols(.captureSelectionToVault)) for a selected secure Vault note, or \(shortcutSymbols(.saveClipboardToVault)) after copying. Safe clearing removes only the exact value Clasp captured, never anything copied afterward."
            } else {
                "Use \(vaultService.title) in Services for selected content, or \(shortcutSymbols(.saveClipboardToVault)) after copying. Safe clearing removes only the exact value Clasp captured, never anything copied afterward."
            }
        case .backup:
            "Store the Vault recovery key separately. Clasp cannot recover a lost key; password managers remain best for credentials and recovery codes."
        }
    }

    var symbol: String {
        switch self {
        case .welcome: "sparkles"
        case .quickCapture: "command"
        case .clipboard: AppIcon.Capture.clipboard
        case .selection: "cursorarrow.click.2"
        case .organize: AppIcon.Navigation.inbox
        case .vault: AppIcon.Vault.destination
        case .backup: "externaldrive.badge.checkmark"
        }
    }

    var tint: Color {
        switch self {
        case .welcome: .indigo
        case .quickCapture: .blue
        case .clipboard: .orange
        case .selection: .purple
        case .organize: .teal
        case .vault: .green
        case .backup: .cyan
        }
    }

    @MainActor
    private var inboxService: MacOSCaptureServiceDescriptor {
        MacOSCaptureServiceDescriptor.all[0]
    }

    @MainActor
    private var vaultService: MacOSCaptureServiceDescriptor {
        MacOSCaptureServiceDescriptor.all[1]
    }

    @MainActor
    private func shortcutSymbols(_ action: GlobalHotKeyAction) -> String {
        GlobalHotKeyPreferences.shared.shortcut(for: action)?.symbolDisplayName ?? "Not set"
    }

    @MainActor
    private func shortcutWords(_ action: GlobalHotKeyAction) -> String {
        GlobalHotKeyPreferences.shared.shortcut(for: action)?
            .displayName.replacingOccurrences(of: "-", with: "–") ?? "no shortcut"
    }
}
