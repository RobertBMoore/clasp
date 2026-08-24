import AppKit
import Foundation

@MainActor
enum KeyboardSettingsOpener {
    static let keyboardSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
    )!
    static let accessibilitySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    static func open() {
#if !CLASP_VISUAL_QA
        NSWorkspace.shared.open(keyboardSettingsURL)
#endif
    }

    static func openAccessibility() {
#if !CLASP_VISUAL_QA
        NSWorkspace.shared.open(accessibilitySettingsURL)
#endif
    }
}
