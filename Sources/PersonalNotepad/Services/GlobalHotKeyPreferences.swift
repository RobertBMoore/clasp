import Foundation
import Observation

struct GlobalHotKeyAssignment: Identifiable, Equatable, Sendable {
    let action: GlobalHotKeyAction
    let shortcut: GlobalHotKeyShortcut?
    let isCustomized: Bool

    var id: GlobalHotKeyAction { action }
    var isEnabled: Bool { shortcut != nil }
}

enum GlobalHotKeyRegistrationState: Equatable, Sendable {
    case disabled
    case notRegisteredYet
    case registered
    case unavailable
}

enum GlobalHotKeyPreferenceError: LocalizedError, Equatable {
    case conflict(existingAction: GlobalHotKeyAction)
    case unsafeShortcut
    case unsupportedAction

    var errorDescription: String? {
        switch self {
        case .conflict(let action):
            "That shortcut is already used for \(action.title). Choose a different one first."
        case .unsafeShortcut:
            "Use Control, Option, or Command with another key so normal typing stays safe."
        case .unsupportedAction:
            "That shortcut is not available in this version of Clasp."
        }
    }
}

@MainActor
@Observable
final class GlobalHotKeyPreferences {
    static let shared = GlobalHotKeyPreferences()
    static let storagePrefix = "globalHotKey.v1."

    private struct StoredAssignment: Codable {
        let isEnabled: Bool
        let shortcut: GlobalHotKeyShortcut?
    }

    private(set) var revision = 0
    private(set) var registrationResult: GlobalHotKeyRegistrationResult?
    @ObservationIgnored
    private let defaults: UserDefaults
    @ObservationIgnored
    private let notificationCenter: NotificationCenter

    init(
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
    }

    var assignments: [GlobalHotKeyAssignment] {
        _ = revision
        return GlobalHotKeyAction.allCases
            .filter(\.isAvailable)
            .map { action in
                GlobalHotKeyAssignment(
                    action: action,
                    shortcut: shortcut(for: action),
                    isCustomized: defaults.object(forKey: storageKey(for: action)) != nil
                )
            }
    }

    var definitions: [GlobalHotKeyDefinition] {
        assignments.compactMap { assignment in
            assignment.shortcut.map {
                GlobalHotKeyDefinition(action: assignment.action, shortcut: $0)
            }
        }
    }

    func definition(for action: GlobalHotKeyAction) -> GlobalHotKeyDefinition? {
        guard action.isAvailable, let shortcut = shortcut(for: action) else { return nil }
        return GlobalHotKeyDefinition(action: action, shortcut: shortcut)
    }

    func shortcut(for action: GlobalHotKeyAction) -> GlobalHotKeyShortcut? {
        _ = revision
        guard action.isAvailable else { return nil }
        let key = storageKey(for: action)
        guard let storedData = defaults.data(forKey: key) else {
            return defaultShortcut(for: action)
        }
        guard let stored = try? JSONDecoder().decode(StoredAssignment.self, from: storedData) else {
            return defaultShortcut(for: action)
        }
        guard stored.isEnabled, let shortcut = stored.shortcut?.normalized,
              shortcut.isSafeForGlobalUse else {
            return stored.isEnabled ? defaultShortcut(for: action) : nil
        }
        return shortcut
    }

    func conflict(
        for shortcut: GlobalHotKeyShortcut,
        excluding action: GlobalHotKeyAction? = nil
    ) -> GlobalHotKeyAction? {
        let candidate = shortcut.normalized
        return definitions.first { definition in
            definition.action != action && definition.shortcut.normalized == candidate
        }?.action
    }

    func registrationState(for action: GlobalHotKeyAction) -> GlobalHotKeyRegistrationState {
        guard shortcut(for: action) != nil else { return .disabled }
        guard let registrationResult else { return .notRegisteredYet }
        if registrationResult.registered.contains(action) { return .registered }
        if registrationResult.failed.contains(action) { return .unavailable }
        return .notRegisteredYet
    }

    func recordRegistrationResult(_ result: GlobalHotKeyRegistrationResult) {
        registrationResult = result
        revision &+= 1
    }

    func replace(
        _ shortcut: GlobalHotKeyShortcut,
        for action: GlobalHotKeyAction
    ) throws {
        guard action.isAvailable else { throw GlobalHotKeyPreferenceError.unsupportedAction }
        let candidate = shortcut.normalized
        guard candidate.isSafeForGlobalUse else {
            throw GlobalHotKeyPreferenceError.unsafeShortcut
        }
        if let existingAction = conflict(for: candidate, excluding: action) {
            throw GlobalHotKeyPreferenceError.conflict(existingAction: existingAction)
        }
        persist(StoredAssignment(isEnabled: true, shortcut: candidate), for: action)
    }

    func clear(_ action: GlobalHotKeyAction) {
        guard action.isAvailable else { return }
        persist(StoredAssignment(isEnabled: false, shortcut: nil), for: action)
    }

    func reset(_ action: GlobalHotKeyAction) {
        defaults.removeObject(forKey: storageKey(for: action))
        publishChange()
    }

    func resetAll() {
        GlobalHotKeyAction.allCases.forEach {
            defaults.removeObject(forKey: storageKey(for: $0))
        }
        publishChange()
    }

    private func persist(_ assignment: StoredAssignment, for action: GlobalHotKeyAction) {
        guard let data = try? JSONEncoder().encode(assignment) else { return }
        defaults.set(data, forKey: storageKey(for: action))
        publishChange()
    }

    private func publishChange() {
        revision &+= 1
        notificationCenter.post(name: .globalHotKeyPreferencesDidChange, object: self)
    }

    private func defaultShortcut(for action: GlobalHotKeyAction) -> GlobalHotKeyShortcut? {
        GlobalHotKeyManager.defaultDefinitions
            .first(where: { $0.action == action })?
            .shortcut
    }

    private func storageKey(for action: GlobalHotKeyAction) -> String {
        Self.storagePrefix + action.storageID
    }
}

/// macOS owns Service shortcuts. Clasp can explain and link to them, but it
/// must not pretend an in-app key recorder can rewrite Keyboard Settings.
struct MacOSCaptureServiceDescriptor: Identifiable, Sendable {
    static let all = [
        Self(
            id: "serviceInbox",
            title: "Create Note in Clasp",
            serviceDescription: "Creates a normal Clasp Inbox note from selected text, a link, or an image.",
            destination: .inbox,
            defaultShortcut: "⌃⌥N",
            systemKeyEquivalent: "^~n"
        ),
        Self(
            id: "serviceVault",
            title: "Create Secure Note in Clasp",
            serviceDescription: "Creates a secure encrypted Clasp Vault note from selected text, a link, or an image.",
            destination: .vault,
            defaultShortcut: "⌃⌥P",
            systemKeyEquivalent: "^~p"
        )
    ]

    let id: String
    let title: String
    let serviceDescription: String
    let destination: CaptureDestination
    let defaultShortcut: String
    let systemKeyEquivalent: String
    let contentKinds = CaptureShortcutContentKind.allCases
    let isManagedBySystem = true
}
