import Foundation
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum VaultAutoLockTimeout: String, CaseIterable, Identifiable, Sendable {
    case oneMinute
    case fiveMinutes
    case tenMinutes
    case thirtyMinutes
    case never

    var id: String { rawValue }
    var title: String {
        switch self {
        case .oneMinute: "1 minute"
        case .fiveMinutes: "5 minutes"
        case .tenMinutes: "10 minutes"
        case .thirtyMinutes: "30 minutes"
        case .never: "Never"
        }
    }
    var duration: TimeInterval? {
        switch self {
        case .oneMinute: 60
        case .fiveMinutes: 300
        case .tenMinutes: 600
        case .thirtyMinutes: 1_800
        case .never: nil
        }
    }
}

enum PreferenceKeys {
    static let onboardingComplete = "onboardingComplete"
    static let appAppearance = "appAppearance"
    static let autoLockTimeout = "vaultAutoLockTimeout"
    static let clipboardClearDelay = "clipboardClearDelay"
    static let documentStylePreset = "documentStylePreset"
    static let documentFontFamily = "documentFontFamily"
    static let documentBodyPointSize = "documentBodyPointSize"
    static let documentLineHeightMultiplier = "documentLineHeightMultiplier"
    static let documentParagraphSpacing = "documentParagraphSpacing"
    static let documentTargetCharactersPerLine = "documentTargetCharactersPerLine"
}

/// Loads and stores each presentation preference separately. This deliberately
/// avoids a style blob in note metadata or Markdown and lets `@AppStorage`
/// propagate a changed reading preference to every open editor immediately.
enum DocumentStylePreferences {
    static func load(from defaults: UserDefaults = .standard) -> DocumentStyle {
        let preset = defaults.string(forKey: PreferenceKeys.documentStylePreset)
            .flatMap(DocumentStylePreset.init(rawValue:)) ?? .balanced
        let base = preset.style
        let fontFamily = defaults.string(forKey: PreferenceKeys.documentFontFamily)
            .flatMap(DocumentFontFamily.init(rawValue:)) ?? base.fontFamily

        return DocumentStyle(
            preset: preset,
            fontFamily: fontFamily,
            bodyPointSize: storedDouble(
                PreferenceKeys.documentBodyPointSize,
                fallback: base.bodyPointSize,
                in: defaults
            ),
            lineHeightMultiplier: storedDouble(
                PreferenceKeys.documentLineHeightMultiplier,
                fallback: base.lineHeightMultiplier,
                in: defaults
            ),
            paragraphSpacing: storedDouble(
                PreferenceKeys.documentParagraphSpacing,
                fallback: base.paragraphSpacing,
                in: defaults
            ),
            targetCharactersPerLine: storedDouble(
                PreferenceKeys.documentTargetCharactersPerLine,
                fallback: base.targetCharactersPerLine,
                in: defaults
            )
        )
    }

    static func store(_ style: DocumentStyle, in defaults: UserDefaults = .standard) {
        defaults.set(style.preset.rawValue, forKey: PreferenceKeys.documentStylePreset)
        defaults.set(style.fontFamily.rawValue, forKey: PreferenceKeys.documentFontFamily)
        defaults.set(style.bodyPointSize, forKey: PreferenceKeys.documentBodyPointSize)
        defaults.set(style.lineHeightMultiplier, forKey: PreferenceKeys.documentLineHeightMultiplier)
        defaults.set(style.paragraphSpacing, forKey: PreferenceKeys.documentParagraphSpacing)
        defaults.set(style.targetCharactersPerLine, forKey: PreferenceKeys.documentTargetCharactersPerLine)
    }

    static func apply(_ preset: DocumentStylePreset, in defaults: UserDefaults = .standard) {
        store(preset.style, in: defaults)
    }

    static func reset(in defaults: UserDefaults = .standard) {
        store(.appDefault, in: defaults)
    }

    private static func storedDouble(_ key: String, fallback: Double, in defaults: UserDefaults) -> Double {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.double(forKey: key)
    }
}
