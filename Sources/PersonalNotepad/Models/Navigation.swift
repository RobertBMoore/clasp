import Foundation

enum SidebarDestination: Hashable, Identifiable, Sendable {
    case inbox
    case allNotes
    case pinned
    case vault
    case trash
    case tag(String)

    var id: String {
        switch self {
        case .inbox: "inbox"
        case .allNotes: "all"
        case .pinned: "pinned"
        case .vault: "vault"
        case .trash: "trash"
        case .tag(let tag): "tag:\(tag)"
        }
    }

    var title: String {
        switch self {
        case .inbox: "Inbox"
        case .allNotes: "All Notes"
        case .pinned: "Pinned"
        case .vault: "Vault"
        case .trash: "Trash"
        case .tag(let tag): tag
        }
    }

    var systemImage: String {
        switch self {
        case .inbox: AppIcon.Navigation.inbox
        case .allNotes: AppIcon.Navigation.allNotes
        case .pinned: AppIcon.Navigation.pinned
        case .vault: AppIcon.Navigation.vault
        case .trash: AppIcon.Navigation.trash
        case .tag: AppIcon.Navigation.tag
        }
    }
}

enum CaptureDestination: Sendable {
    case inbox
    case vault
}
