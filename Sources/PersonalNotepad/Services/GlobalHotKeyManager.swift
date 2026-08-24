import AppKit
import Carbon
import Foundation

extension Notification.Name {
    static let openQuickCapture = Notification.Name("PersonalNotepad.openQuickCapture")
    static let openMainWindow = Notification.Name("PersonalNotepad.openMainWindow")
    static let saveClipboard = Notification.Name("PersonalNotepad.saveClipboard")
    static let saveClipboardToVault = Notification.Name("PersonalNotepad.saveClipboardToVault")
    static let clearClipboard = Notification.Name("PersonalNotepad.clearClipboard")
    static let captureSelectionToInbox = Notification.Name("PersonalNotepad.captureSelectionToInbox")
    static let captureSelectionToVault = Notification.Name("PersonalNotepad.captureSelectionToVault")
    static let lockVault = Notification.Name("PersonalNotepad.lockVault")
    static let showOnboarding = Notification.Name("PersonalNotepad.showOnboarding")
    static let globalHotKeyPreferencesDidChange = Notification.Name(
        "PersonalNotepad.globalHotKeyPreferencesDidChange"
    )
}

enum CaptureShortcutInputSource: String, Sendable {
    case quickCapture
    case selectedContent
    case clipboard
    case vaultControl
}

enum CaptureShortcutContentKind: String, CaseIterable, Sendable {
    case plainText
    case markdown
    case richText
    case link
    case image

    var title: String {
        switch self {
        case .plainText: "Text"
        case .markdown: "Markdown"
        case .richText: "Styled text"
        case .link: "Links"
        case .image: "Images"
        }
    }
}

enum GlobalHotKeyAvailability: Sendable {
    case everyDistribution
    case directDistributionOnly

    var isAvailable: Bool {
        switch self {
        case .everyDistribution: true
        case .directDistributionOnly:
            DistributionCapabilities.supportsAccessibilitySelectionCapture
        }
    }
}

enum GlobalHotKeyAction: UInt32, CaseIterable, Identifiable, Sendable {
    case quickCapturePrimary = 1
    case quickCaptureFallback = 4
    case captureSelectionToInbox = 2
    case captureSelectionToVault = 5
    case saveClipboardToInbox = 6
    case saveClipboardToVault = 7
    case lockVault = 3

    var id: UInt32 { rawValue }

    var storageID: String {
        switch self {
        case .quickCapturePrimary: "quickCapturePrimary"
        case .captureSelectionToInbox: "captureSelectionToInbox"
        case .lockVault: "lockVault"
        case .quickCaptureFallback: "quickCaptureFallback"
        case .captureSelectionToVault: "captureSelectionToVault"
        case .saveClipboardToInbox: "saveClipboardToInbox"
        case .saveClipboardToVault: "saveClipboardToVault"
        }
    }

    var title: String {
        switch self {
        case .quickCapturePrimary: "Quick Capture"
        case .quickCaptureFallback: "Quick Capture Backup"
        case .captureSelectionToInbox: "Selected Content to Inbox"
        case .captureSelectionToVault: "Selected Content to Vault"
        case .saveClipboardToInbox: "Clipboard to Inbox"
        case .saveClipboardToVault: "Clipboard to Vault"
        case .lockVault: "Lock Vault"
        }
    }

    var detail: String {
        switch self {
        case .quickCapturePrimary:
            "Open a small writing window from anywhere."
        case .quickCaptureFallback:
            "A second way to open Quick Capture if another app uses the main shortcut."
        case .captureSelectionToInbox:
            "Copy the current selection automatically and create a normal note."
        case .captureSelectionToVault:
            "Copy the current selection automatically and create a secure Vault note."
        case .saveClipboardToInbox:
            "Create a normal note from the text, Markdown, link, or image you copied."
        case .saveClipboardToVault:
            "Create a secure Vault note from the text, Markdown, link, or image you copied."
        case .lockVault:
            "Immediately close access to secure Vault notes."
        }
    }

    var inputSource: CaptureShortcutInputSource {
        switch self {
        case .quickCapturePrimary, .quickCaptureFallback: .quickCapture
        case .captureSelectionToInbox, .captureSelectionToVault: .selectedContent
        case .saveClipboardToInbox, .saveClipboardToVault: .clipboard
        case .lockVault: .vaultControl
        }
    }

    var destination: CaptureDestination? {
        switch self {
        case .captureSelectionToInbox, .saveClipboardToInbox: .inbox
        case .captureSelectionToVault, .saveClipboardToVault: .vault
        case .quickCapturePrimary, .quickCaptureFallback, .lockVault: nil
        }
    }

    var contentKinds: [CaptureShortcutContentKind] {
        switch inputSource {
        case .selectedContent, .clipboard: CaptureShortcutContentKind.allCases
        case .quickCapture: [.plainText, .markdown]
        case .vaultControl: []
        }
    }

    var availability: GlobalHotKeyAvailability {
        switch self {
        case .captureSelectionToInbox, .captureSelectionToVault: .directDistributionOnly
        default: .everyDistribution
        }
    }

    var isAvailable: Bool { availability.isAvailable }

    var notification: Notification.Name {
        switch self {
        case .quickCapturePrimary, .quickCaptureFallback: .openQuickCapture
        case .captureSelectionToInbox: .captureSelectionToInbox
        case .captureSelectionToVault: .captureSelectionToVault
        case .saveClipboardToInbox: .saveClipboard
        case .saveClipboardToVault: .saveClipboardToVault
        case .lockVault: .lockVault
        }
    }
}

struct GlobalHotKeyShortcut: Codable, Equatable, Hashable, Sendable {
    static let allowedModifiers = UInt32(controlKey | optionKey | shiftKey | cmdKey)

    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    init?(event: NSEvent) {
        guard !event.isARepeat else { return nil }
        let label = Self.keyLabel(for: event)
        guard !label.isEmpty else { return nil }
        self.init(
            keyCode: UInt32(event.keyCode),
            modifiers: Self.carbonModifiers(from: event.modifierFlags),
            keyLabel: label
        )
    }

    var normalized: Self {
        let trimmed = keyLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmed.count == 1 ? trimmed.uppercased() : trimmed
        return Self(
            keyCode: keyCode,
            modifiers: modifiers & Self.allowedModifiers,
            keyLabel: label
        )
    }

    var isSafeForGlobalUse: Bool {
        let value = normalized
        let protectiveModifiers = UInt32(controlKey | optionKey | cmdKey)
        return value.keyCode <= UInt32(UInt16.max)
            && !value.keyLabel.isEmpty
            && value.keyLabel.count <= 16
            && value.modifiers & protectiveModifiers != 0
    }

    var displayName: String {
        let value = normalized
        var components: [String] = []
        if value.modifiers & UInt32(controlKey) != 0 { components.append("Control") }
        if value.modifiers & UInt32(optionKey) != 0 { components.append("Option") }
        if value.modifiers & UInt32(shiftKey) != 0 { components.append("Shift") }
        if value.modifiers & UInt32(cmdKey) != 0 { components.append("Command") }
        components.append(value.keyLabel)
        return components.joined(separator: "-")
    }

    var symbolDisplayName: String {
        keycapLabels.joined()
    }

    var keycapLabels: [String] {
        let value = normalized
        var labels: [String] = []
        if value.modifiers & UInt32(controlKey) != 0 { labels.append("⌃") }
        if value.modifiers & UInt32(optionKey) != 0 { labels.append("⌥") }
        if value.modifiers & UInt32(shiftKey) != 0 { labels.append("⇧") }
        if value.modifiers & UInt32(cmdKey) != 0 { labels.append("⌘") }
        labels.append(value.keyLabel)
        return labels
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        return modifiers
    }

    private static func keyLabel(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Delete: return "Delete"
        case kVK_ForwardDelete: return "Forward Delete"
        case kVK_Escape: return "Escape"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "Page Up"
        case kVK_PageDown: return "Page Down"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default:
            if let functionKey = functionKeyLabel(for: Int(event.keyCode)) {
                return functionKey
            }
            return event.charactersIgnoringModifiers?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased() ?? ""
        }
    }

    private static func functionKeyLabel(for keyCode: Int) -> String? {
        let codes = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7,
            kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14,
            kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
        ]
        guard let index = codes.firstIndex(of: keyCode) else { return nil }
        return "F\(index + 1)"
    }
}

struct GlobalHotKeyDefinition: Equatable, Sendable {
    let action: GlobalHotKeyAction
    let shortcut: GlobalHotKeyShortcut

    var keyCode: UInt32 { shortcut.keyCode }
    var modifiers: UInt32 { shortcut.modifiers }
    var displayName: String { shortcut.displayName }
}

struct GlobalHotKeyRegistrationResult: Equatable, Sendable {
    var registered: Set<GlobalHotKeyAction> = []
    var failed: Set<GlobalHotKeyAction> = []

    func contains(_ action: GlobalHotKeyAction) -> Bool {
        registered.contains(action)
    }
}

enum GlobalHotKeyMessageFormatter {
    static func quickCaptureFailureMessage(
        result: GlobalHotKeyRegistrationResult,
        definitions: [GlobalHotKeyDefinition]
    ) -> String? {
        let quickCapture = definitions.filter {
            $0.action == .quickCapturePrimary || $0.action == .quickCaptureFallback
        }
        let failed = quickCapture.filter { result.failed.contains($0.action) }
        guard !failed.isEmpty else { return nil }
        let failedNames = failed.map(\.displayName).joined(separator: " and ")
        let workingNames = quickCapture
            .filter { result.registered.contains($0.action) }
            .map(\.displayName)
            .joined(separator: " and ")
        if workingNames.isEmpty {
            return "\(failedNames) could not be registered. Use the Clasp menu bar icon or choose another shortcut in Settings."
        }
        let verb = failed.count == 1 ? "is" : "are"
        return "\(failedNames) \(verb) already in use. Quick Capture: \(workingNames)"
    }

    /// Produces one startup warning for the supporting shortcuts instead of
    /// interrupting the user once per failed registration. Definitions come
    /// from preferences, so cleared shortcuts stay silent and customized key
    /// combinations are reported exactly as configured.
    static func supportingActionFailureMessage(
        result: GlobalHotKeyRegistrationResult,
        definitions: [GlobalHotKeyDefinition]
    ) -> String? {
        let supportedActions: Set<GlobalHotKeyAction> = [
            .saveClipboardToInbox,
            .saveClipboardToVault,
            .lockVault
        ]
        let failed = definitions.filter {
            supportedActions.contains($0.action) && result.failed.contains($0.action)
        }
        guard !failed.isEmpty else { return nil }

        let failedNames = naturalLanguageList(
            failed.map { "\($0.action.title) (\($0.displayName))" }
        )
        var recovery: [String] = []
        if failed.contains(where: { $0.action.inputSource == .clipboard }) {
            recovery.append("Clipboard capture remains available from the Clasp menu bar or Dock menu.")
        }
        if failed.contains(where: { $0.action == .lockVault }) {
            recovery.append("Lock the Vault from either menu until you choose a replacement.")
        }
        recovery.append("Choose replacements in Settings › Shortcuts & Capture.")

        let verb = failed.count == 1 ? "is" : "are"
        return "\(failedNames) \(verb) already in use by another app or macOS. \(recovery.joined(separator: " "))"
    }

    private static func naturalLanguageList(_ values: [String]) -> String {
        switch values.count {
        case 0: ""
        case 1: values[0]
        case 2: values.joined(separator: " and ")
        default:
            values.dropLast().joined(separator: ", ") + ", and " + values[values.count - 1]
        }
    }
}

@MainActor
final class GlobalHotKeyManager: NSObject {
    static let defaultDefinitions: [GlobalHotKeyDefinition] = [
        definition(.quickCapturePrimary, kVK_Space, optionKey, "Space"),
        definition(.quickCaptureFallback, kVK_Space, controlKey | optionKey | cmdKey, "Space"),
        definition(.captureSelectionToInbox, kVK_ANSI_N, controlKey | optionKey | shiftKey, "N"),
        definition(.captureSelectionToVault, kVK_ANSI_P, controlKey | optionKey | shiftKey, "P"),
        definition(.saveClipboardToInbox, kVK_ANSI_C, controlKey | optionKey | cmdKey, "C"),
        definition(.saveClipboardToVault, kVK_ANSI_V, controlKey | optionKey | cmdKey, "V"),
        definition(.lockVault, kVK_ANSI_L, controlKey | optionKey | cmdKey, "L")
    ]

    /// Shipping defaults for this distribution. User customizations are read
    /// from `GlobalHotKeyPreferences` by an instance of the manager.
    static var definitions: [GlobalHotKeyDefinition] {
        defaultDefinitions.filter(\.action.isAvailable)
    }

    private let preferences: GlobalHotKeyPreferences
    private let testRegistration: ((GlobalHotKeyDefinition) -> Bool)?
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private(set) var result = GlobalHotKeyRegistrationResult()
    private var isObservingPreferences = false

    override convenience init() {
        self.init(preferences: .shared, testRegistration: nil)
    }

    init(
        preferences: GlobalHotKeyPreferences,
        testRegistration: ((GlobalHotKeyDefinition) -> Bool)? = nil
    ) {
        self.preferences = preferences
        self.testRegistration = testRegistration
        super.init()
    }

    func definition(for action: GlobalHotKeyAction) -> GlobalHotKeyDefinition? {
        preferences.definition(for: action)
    }

    func register() -> GlobalHotKeyRegistrationResult {
        beginObservingPreferencesIfNeeded()
        guard installHandlerIfNeeded() else {
            result = GlobalHotKeyRegistrationResult(
                failed: Set(preferences.definitions.map(\.action))
            )
            preferences.recordRegistrationResult(result)
            return result
        }
        reloadRegistrations()
        return result
    }

    @discardableResult
    func reloadRegistrations() -> GlobalHotKeyRegistrationResult {
        unregisterAllReferences()
        result = GlobalHotKeyRegistrationResult()
        guard handler != nil || testRegistration != nil else {
            preferences.recordRegistrationResult(result)
            return result
        }
        for definition in preferences.definitions {
            register(definition)
        }
        preferences.recordRegistrationResult(result)
        return result
    }

    private func installHandlerIfNeeded() -> Bool {
        if testRegistration != nil { return true }
        guard handler == nil else { return true }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            guard GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &id
            ) == noErr else { return noErr }
            guard let action = GlobalHotKeyAction(rawValue: id.id) else { return noErr }
            DispatchQueue.main.async { GlobalActionBus.post(action.notification) }
            return noErr
        }, 1, &eventType, nil, &handler)
        return status == noErr && handler != nil
    }

    private func register(_ definition: GlobalHotKeyDefinition) {
        if let testRegistration {
            if testRegistration(definition) {
                result.registered.insert(definition.action)
            } else {
                result.failed.insert(definition.action)
            }
            return
        }
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(
            signature: OSType(0x504E4F54),
            id: definition.action.rawValue
        )
        let status = RegisterEventHotKey(
            definition.keyCode,
            definition.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status == noErr, let reference {
            references.append(reference)
            result.registered.insert(definition.action)
        } else {
            result.failed.insert(definition.action)
        }
    }

    private func unregisterAllReferences() {
        references.forEach { UnregisterEventHotKey($0) }
        references.removeAll(keepingCapacity: true)
    }

    private func beginObservingPreferencesIfNeeded() {
        guard !isObservingPreferences else { return }
        isObservingPreferences = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange(_:)),
            name: .globalHotKeyPreferencesDidChange,
            object: preferences
        )
    }

    @objc private func preferencesDidChange(_ notification: Notification) {
        _ = reloadRegistrations()
    }

    private static func definition(
        _ action: GlobalHotKeyAction,
        _ keyCode: Int,
        _ modifiers: Int,
        _ keyLabel: String
    ) -> GlobalHotKeyDefinition {
        GlobalHotKeyDefinition(
            action: action,
            shortcut: GlobalHotKeyShortcut(
                keyCode: UInt32(keyCode),
                modifiers: UInt32(modifiers),
                keyLabel: keyLabel
            )
        )
    }
}
