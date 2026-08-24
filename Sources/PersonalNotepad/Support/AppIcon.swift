import Foundation

/// The single source of truth for Clasp's interactive icon language.
///
/// Navigation uses simple outline silhouettes that remain legible in a compact
/// macOS sidebar. Filled variants are reserved for actual states.
enum AppIcon {
    enum Navigation {
        static let inbox = "tray"
        static let allNotes = "rectangle.stack"
        static let pinned = "pin"
        static let vault = "shield"
        static let trash = "trash"
        static let tag = "tag"
    }

    enum Create {
        static let note = "square.and.pencil"
        static let secureNote = Navigation.vault
    }

    enum Capture {
        static let quick = "bolt.fill"
        static let clipboard = "clipboard"
        static let clipboardToVault = Navigation.vault
        static let clearClipboard = "xmark.bin"
    }

    enum Vault {
        static let destination = Navigation.vault
        static let secureNote = Create.secureNote
        static let secureDocument = "lock.doc.fill"
        static let noteBadge = "shield.fill"
        static let lockNow = "lock.fill"
        static let locked = "lock.shield"
        static let recoveryKey = "key.fill"
    }

    enum NoteAction {
        static let pin = "pin"
        static let pinned = "pin.fill"
        static let unpin = "pin.slash"
        static let more = "ellipsis.circle"
        static let archive = "archivebox"
        static let archived = "archivebox.fill"
        static let removeFromInbox = "tray.and.arrow.up"
        static let moveToTrash = "trash"
        static let restore = "arrow.uturn.backward"
        static let deletePermanently = "trash.slash"
    }

    enum Content {
        static let note = "doc.text"
        static let link = "link"
        static let image = "photo"
        static let code = "chevron.left.forwardslash.chevron.right"
        static let checklist = "checklist"
        static let contact = "person.text.rectangle"
    }

    enum Editing {
        static let textStyle = "textformat.size"
        static let bold = "bold"
        static let italic = "italic"
        static let underline = "underline"
        static let bulletedList = "list.bullet"
        static let numberedList = "list.number"
        static let link = Content.link
        static let tag = Navigation.tag
    }

    enum Utility {
        static let app = "paperclip"
        static let appearance = "circle.lefthalf.filled"
        static let search = "magnifyingglass"
    }

    /// Every core product symbol, exercised by a platform-availability test.
    static let allSystemNames: [String] = [
        Navigation.inbox,
        Navigation.allNotes,
        Navigation.pinned,
        Navigation.vault,
        Navigation.trash,
        Navigation.tag,
        Create.note,
        Create.secureNote,
        Capture.quick,
        Capture.clipboard,
        Capture.clearClipboard,
        Vault.lockNow,
        Vault.locked,
        Vault.noteBadge,
        Vault.secureDocument,
        Vault.recoveryKey,
        NoteAction.pin,
        NoteAction.pinned,
        NoteAction.unpin,
        NoteAction.more,
        NoteAction.archive,
        NoteAction.archived,
        NoteAction.removeFromInbox,
        NoteAction.restore,
        NoteAction.deletePermanently,
        Content.note,
        Content.link,
        Content.image,
        Content.code,
        Content.checklist,
        Content.contact,
        Editing.textStyle,
        Editing.bold,
        Editing.italic,
        Editing.underline,
        Editing.bulletedList,
        Editing.numberedList,
        Utility.appearance,
        Utility.app,
        Utility.search
    ]
}
