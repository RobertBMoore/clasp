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
}
