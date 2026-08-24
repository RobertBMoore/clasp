import AppKit
import Foundation

@MainActor
protocol AppAppearanceApplying: AnyObject {
    var appearance: NSAppearance? { get set }
}

extension NSApplication: AppAppearanceApplying {}

/// Owns Clasp's one application-wide appearance boundary.
///
/// SwiftUI's `preferredColorScheme` only overrides the view subtree where it is
/// attached. Clasp also contains AppKit-backed windows, lists, materials, and
/// text views, so forcing individual SwiftUI scene roots can temporarily leave
/// one window in two appearances. Applying the preference to `NSApplication`
/// lets every SwiftUI and AppKit surface inherit the same effective appearance.
@MainActor
enum AppAppearanceController {
    static func storedPreference(in defaults: UserDefaults = .standard) -> AppAppearance {
        defaults.string(forKey: PreferenceKeys.appAppearance)
            .flatMap(AppAppearance.init(rawValue:)) ?? .system
    }

    static func appearanceName(for preference: AppAppearance) -> NSAppearance.Name? {
        switch preference {
        case .system:
            nil
        case .light:
            .aqua
        case .dark:
            .darkAqua
        }
    }

    static func applyStoredPreference(defaults: UserDefaults = .standard) {
        applyStoredPreference(defaults: defaults, to: NSApplication.shared)
    }

    static func applyStoredPreference(
        defaults: UserDefaults = .standard,
        to application: any AppAppearanceApplying
    ) {
        apply(storedPreference(in: defaults), to: application)
    }

    static func apply(_ preference: AppAppearance) {
        apply(preference, to: NSApplication.shared)
    }

    static func apply(_ preference: AppAppearance, to application: any AppAppearanceApplying) {
        application.appearance = appearanceName(for: preference).flatMap(NSAppearance.init(named:))
    }
}
