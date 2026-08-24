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

    var message: String {
        switch self {
        case .welcome:
            "Capture text, links, code, checklists, contacts, and images. Send ordinary material to Clasp or sensitive material directly to the encrypted Vault."
        case .quickCapture:
            "Press Option–Space from any app, type, then press Command–Return. New captures go to Inbox unless you choose Vault."
        case .clipboard:
            "Copy text, a link, or an image. Choose Add Clipboard to Clasp for Inbox, or Add Clipboard to Vault for encrypted storage and optional safe clipboard clearing."
        case .selection:
            if DistributionCapabilities.supportsAccessibilitySelectionCapture {
                "Select text, an image, or a link. Press Control–Option–N for a normal Inbox note or Control–Option–P for a private Vault note. You can also use either action from the source app’s Services menu."
            } else {
                "Select text, an image, or a link, then choose Create Note in Clasp or Create Private Note in Clasp from the source app’s Services menu."
            }
        case .organize:
            "Clasp identifies and tags incoming content locally. Copied bold, italic, underline, headings, lists, and links carry into the formatted editor while Markdown stays underneath."
        case .vault:
            if DistributionCapabilities.supportsAccessibilitySelectionCapture {
                "Press Control–Option–P to add selected content directly to Vault. Titles, tags, image bytes, recognized text, and bodies are encrypted at rest."
            } else {
                "Use Create Private Note in Clasp from the source app’s Services menu to send selected content to Vault. Titles, tags, image bytes, recognized text, and bodies are encrypted at rest."
            }
        case .backup:
            "Regular notes are portable Markdown files. Vault backups are encrypted exports with a recovery key shown only once."
        }
    }

    var tip: String {
        switch self {
        case .welcome:
            "Two destinations, everywhere: Add to Clasp for everyday material; Add to Clasp Vault when it is sensitive."
        case .quickCapture:
            "If another app owns Option–Space, use Control–Option–Command–N. You can always click Clasp in the menu bar or right-click its Dock icon."
        case .clipboard:
            "Clasp reads once when triggered. It never watches the clipboard or keeps history, and it accepts images up to 25 MB."
        case .selection:
            if DistributionCapabilities.supportsAccessibilitySelectionCapture {
                "The paired shortcuts use N for Normal and P for Private. Approve Clasp once in Privacy & Security › Accessibility so the shortcut can issue one Copy command; Clasp never monitors your keyboard."
            } else {
                "Services receive only the selection you explicitly send. Clasp never requests Accessibility permission or monitors your keyboard."
            }
        case .organize:
            "Use the Formatted / Markdown switch above any note. Formatting controls edit the same portable Markdown—there is never a separate hidden rich-text copy."
        case .vault:
            if DistributionCapabilities.supportsAccessibilitySelectionCapture {
                "Use ⌃⌥P for a selected private note. For clipboard capture, use the shield menu item; when safe clearing is enabled, Clasp clears only the exact value it captured, never anything copied afterward."
            } else {
                "Use Create Private Note in Clasp in Services for a selected private note. For clipboard capture, use the shield menu item; when safe clearing is enabled, Clasp clears only the exact value it captured, never anything copied afterward."
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
}
