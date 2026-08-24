# Clasp Iconography

Clasp uses Apple SF Symbols so icons stay sharp, accessible, and visually
consistent with macOS. Compact navigation and actions use simple outline
silhouettes. Filled variants are reserved for actual states, such as a note
being pinned or archived.

In compact panes, formatting actions may collapse into labeled menus, but their
meaning and accessibility labels stay the same. Note-list rows show one content
icon and at most one trailing state icon so security, content type, and actions
do not become an undifferentiated strip of glyphs. Vault notes use the locked
document as their leading list icon; the filled shield remains the explicit
Vault badge in the editor.

The implementation source of truth is
`Sources/PersonalNotepad/Support/AppIcon.swift`. A unit test verifies that every
core symbol exists on Clasp's supported macOS version.

## Navigation

| UI | SF Symbol | Meaning |
| --- | --- | --- |
| Inbox | `tray` | Newly captured items waiting to be filed |
| All Notes | `rectangle.stack` | The complete regular-note collection |
| Pinned | `pin` | Notes intentionally kept close |
| Vault | `shield` | The protected note collection |
| Trash | `trash` | Recoverable deleted notes |
| Tag | `tag` | A user-created grouping |

## Create and capture

| UI | SF Symbol | Meaning |
| --- | --- | --- |
| New Note | `square.and.pencil` | Create a regular Inbox note, or a private note when the current destination is Vault |
| New Secure Note | `shield` | Create a note directly in Vault |
| Quick Capture | `bolt.fill` | Fast keyboard capture |
| Add Clipboard to Clasp | `clipboard` | Import the current clipboard |
| Add Clipboard to Vault | `shield` | Import the clipboard as a secure note |
| Clear Clipboard | `xmark.bin` | Remove the current clipboard value |
| Lock Vault | `lock.fill` | Lock the currently unlocked Vault now |
| Vault note badge | `shield.fill` | Marks a note as encrypted Vault content |
| Secure text note | `lock.doc.fill` | Replaces the ordinary document glyph inside Vault |

## Note actions and states

| UI | SF Symbol | Meaning |
| --- | --- | --- |
| Pin / Unpin | `pin` / `pin.slash` | Add to or remove from Pinned |
| More Note Actions | `ellipsis.circle` | Open labeled secondary note actions |
| Archive | `archivebox` | Keep the note but remove it from active views |
| Archived state | `archivebox.fill` | The note is archived |
| Move Out of Inbox | `tray.and.arrow.up` | File the note into All Notes |
| Move to Trash | `trash` | Soft-delete the note |
| Restore | `arrow.uturn.backward` | Return a trashed note |
| Delete Permanently | `trash.slash` | Irreversibly delete a trashed note |

## Content types

| Content | SF Symbol |
| --- | --- |
| Note | `doc.text` |
| Link | `link` |
| Image | `photo` |
| Code | `chevron.left.forwardslash.chevron.right` |
| Checklist | `checklist` |
| Contact | `person.text.rectangle` |

## Editor and settings

| UI | SF Symbol |
| --- | --- |
| Text style | `textformat.size` |
| Bold / Italic / Underline | `bold` / `italic` / `underline` |
| Bullets / Numbers | `list.bullet` / `list.number` |
| Add link | `link` |
| Appearance | `circle.lefthalf.filled` |
| Clipboard settings | `clipboard` |
| Search | `magnifyingglass` |
| Recovery key | `key.fill` |
| Clasp menu bar | `paperclip` |
