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
}

enum GlobalHotKeyAction: UInt32, CaseIterable {
    case quickCapturePrimary = 1
    case captureSelectionToInbox = 2
    case lockVault = 3
    case quickCaptureFallback = 4
    case captureSelectionToVault = 5

    var notification: Notification.Name {
        switch self {
        case .quickCapturePrimary, .quickCaptureFallback: .openQuickCapture
        case .captureSelectionToInbox: .captureSelectionToInbox
        case .lockVault: .lockVault
        case .captureSelectionToVault: .captureSelectionToVault
        }
    }
}

struct GlobalHotKeyDefinition: Equatable {
    let action: GlobalHotKeyAction
    let keyCode: UInt32
    let modifiers: UInt32
    let displayName: String
}

struct GlobalHotKeyRegistrationResult {
    var registered: Set<GlobalHotKeyAction> = []
    var failed: Set<GlobalHotKeyAction> = []

    func contains(_ action: GlobalHotKeyAction) -> Bool {
        registered.contains(action)
    }
}

@MainActor
final class GlobalHotKeyManager {
    static let definitions: [GlobalHotKeyDefinition] = {
        var definitions = [
            GlobalHotKeyDefinition(
            action: .quickCapturePrimary,
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(optionKey),
            displayName: "Option-Space"
        ),
            GlobalHotKeyDefinition(
            action: .lockVault,
            keyCode: UInt32(kVK_ANSI_L),
            modifiers: UInt32(controlKey | optionKey | cmdKey),
            displayName: "Control-Option-Command-L"
        ),
            GlobalHotKeyDefinition(
            action: .quickCaptureFallback,
            keyCode: UInt32(kVK_ANSI_N),
            modifiers: UInt32(controlKey | optionKey | cmdKey),
            displayName: "Control-Option-Command-N"
            )
        ]
#if !CLASP_APP_STORE
        definitions.insert(
            GlobalHotKeyDefinition(
                action: .captureSelectionToInbox,
                keyCode: UInt32(kVK_ANSI_N),
                modifiers: UInt32(controlKey | optionKey),
                displayName: "Control-Option-N"
            ),
            at: 1
        )
        definitions.append(GlobalHotKeyDefinition(
            action: .captureSelectionToVault,
            keyCode: UInt32(kVK_ANSI_P),
            modifiers: UInt32(controlKey | optionKey),
            displayName: "Control-Option-P"
        ))
#endif
        return definitions
    }()

    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var result = GlobalHotKeyRegistrationResult()

    func register() -> GlobalHotKeyRegistrationResult {
        guard handler == nil else { return result }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr else { return noErr }
            guard let action = GlobalHotKeyAction(rawValue: id.id) else { return noErr }
            DispatchQueue.main.async { GlobalActionBus.post(action.notification) }
            return noErr
        }, 1, &eventType, nil, &handler)

        guard handlerStatus == noErr, handler != nil else {
            result.failed = Set(GlobalHotKeyAction.allCases)
            return result
        }
        for definition in Self.definitions {
            register(definition)
        }
        return result
    }

    private func register(_ definition: GlobalHotKeyDefinition) {
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x504E4F54), id: definition.action.rawValue)
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
}
