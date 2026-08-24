# Clasp

Clasp is a local-first macOS app for catching text, links, prompts, phone-call notes, journal entries, and clipboard snippets before they slip away. Regular notes are portable Markdown files. Sensitive notes can be placed in a separately encrypted Vault.

Clasp has no accounts, analytics, cloud sync, AI APIs, or content transmission. Ordinary local and Mac App Store builds have no third-party runtime dependency or network client. The separate direct-download release uses exact-pinned Sparkle only to retrieve signed software updates from its configured GitHub feed.

## Requirements

- macOS 14 or newer
- Xcode Command Line Tools or Xcode with Swift 6 support
- No Apple Developer account, Homebrew, CocoaPods, or external packages for ordinary local builds

## Build and run

From the repository root:

```bash
./script/build_and_run.sh
```

This stops a prior instance, runs the tests, builds the SwiftPM executable, stages `dist/Clasp.app`, includes the production icon, ad-hoc signs it, and launches the bundle. The Codex **Run** action executes the same command.

Additional modes:

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --debug
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
./script/build_and_run.sh --install
```

`--verify` confirms that the launched app process remains running. `--install` places the validated local build at `/Applications/Clasp.app`, which makes Clasp easy to keep in the Dock and lets macOS reliably discover its right-click Service. This local bundle is ad-hoc signed for this Mac; it is not a public release. `--debug` opens LLDB. The log modes stream local unified logs; Clasp deliberately does not log note or clipboard content.

Direct GitHub releases and Mac App Store builds use separate, credential-gated pipelines documented in [`release/README.md`](release/README.md). Direct builds can use Sparkle for signed in-app updates; App Store builds never include Sparkle and update through the App Store.

## The easy way to remember Clasp

- **Option-Space** opens Quick Capture from anywhere. This is the only shortcut most people need.
- If another app already owns **Option-Space**, **Control-Option-Command-Space** is the built-in Quick Capture fallback.
- After copying text, Markdown, a link, or an image, use **Control-Option-Command-C** for a normal Inbox note or **Control-Option-Command-V** for a secure Vault note. These shortcuts work without Accessibility access.
- In local and direct builds, selected content can use **Control-Option-Shift-N** for a normal Inbox note or **Control-Option-Shift-P** for a secure Vault note. The App Store build uses the two right-click Services instead and never requests Accessibility access.
- Click the **Clasp menu bar icon** to add the current text/image clipboard to Clasp or directly to Vault.
- **Right-click Clasp in the Dock** for both clipboard destinations, Quick Capture, Open Clasp, or Lock Vault.
- Right-click selected text, an image, or a link and choose **Services › Create Note in Clasp** or **Create Secure Note in Clasp**.
- Inside Clasp, right-click a note to pin, archive, trash, or restore it.

## Capture workflows

| Workflow | Default shortcut | Result |
| --- | --- | --- |
| New note | `Command-N` | Creates a secure Vault note while viewing Vault; otherwise creates a regular note in Inbox |
| New Vault note | `Shift-Command-N` | Authenticates if needed, then creates a Vault note |
| Quick Capture | `Option-Space` (fallback: `Control-Option-Command-Space`) | Opens a focused floating capture window; `Command-Return` saves and `Escape` cancels |
| Copied content to Inbox | `Control-Option-Command-C` | Saves copied text, Markdown, a link, or an image as a normal note |
| Copied content to Vault | `Control-Option-Command-V` | Saves copied text, Markdown, a link, or an image as a secure Vault note |
| Selected content to Inbox | Local/direct: `Control-Option-Shift-N`; Store: Services | Saves the selected text, link, or image as a normal note |
| Selected content to Vault | Local/direct: `Control-Option-Shift-P`; Store: Services | Saves the selected text, link, or image as a secure Vault note |
| Add Clipboard to Clasp | Menu bar or Dock | Saves the current text, link, or image to Inbox |
| Add Clipboard to Vault | Menu bar or Dock | Saves the current text, link, or image to Vault and, unless Settings is set to Never, safely clears the captured clipboard value |
| Lock Vault | `Control-Option-Command-L` | Immediately evicts decrypted Vault state and the in-memory key |

Quick Capture includes an Inbox/Vault toggle and **Capture Clipboard to Vault**. When safe clearing is enabled, the app waits for the configured delay and clears only if the clipboard still contains the exact captured content and change count. Choosing **Never** leaves the captured value on the clipboard. Newer clipboard content is never erased. The app does not keep clipboard history or automatically classify anything as secret.

### How clipboard capture works

1. Copy text, a link, or an image normally with `Command-C`.
2. Choose **Add Clipboard to Clasp** or **Add Clipboard to Vault** from the menu-bar or Dock menu.
3. Clasp reads the value once, identifies its content type, adds conservative local tags, and saves it without opening the main window.

Clasp does not watch clipboard changes and does not build a clipboard history. Each trigger is a one-time capture. Vault capture encrypts text, image bytes, tags, and locally recognized image text. When safe clearing is enabled, it then clears only the exact captured clipboard value after the configured delay.

The menu bar extra provides Quick Capture, both clipboard destinations, Open Clasp, Clear Clipboard, Lock Vault, and Quit.

## Automatic organization

Classification runs entirely on the Mac with no network access. Clasp recognizes high-confidence content types—notes, links, images, code, checklists, and contact-like text—and adds editable tags. Links receive their domain, checklists receive `task`, and recognizable code can receive a language tag. Apple Vision extracts searchable text from clipped images locally. Clasp deliberately avoids speculative topic tags it cannot justify.

Vault notes are isolated from Inbox, Pinned, and regular tag filters. While the Vault is unlocked, its active notes also appear in All Notes and All Notes search with a locked-document identity. Trashed Vault notes appear in Trash only while the Vault is unlocked so they can be restored or permanently deleted; locking immediately removes every decrypted Vault title, metadata record, body, and search result from shared views.

## Page editing and Markdown

The note editor opens in **Page** mode. **Page / Markdown** are two views of the same canonical Markdown source: Page applies readable typography in place, while Markdown exposes the exact portable source. Edits in either view update that source, with no hidden rich-text copy.

Page mode recognizes common AI-generated Markdown structures, including headings, bold, italic, strikethrough, links, bulleted and numbered lists, checklists, block quotes, inline and fenced code, and horizontal rules. Unknown Markdown syntax is preserved conservatively as source text instead of being discarded.

Exceptionally large notes remain fully editable and source-exact. Above Clasp's live semantic-styling limit, Page keeps the selected base typography while reducing semantic decoration so typing and mode changes remain responsive.

Choose **Clasp › Settings › Documents** for Balanced (the default), Compact, Spacious, or Technical presets, or fine-tune the typeface, text size, line height, paragraph gap, and target line length. These presentation preferences are stored outside note files and never add styling to the Markdown. Appearance remains adaptive; choose **Clasp › Settings › Appearance** to follow the Mac or keep Clasp in Light or Dark mode.

Copied RTF and HTML use a separate, local import path. Clasp keeps supported document structure and safe `http`, `https`, or `mailto` links, but sanitizes copied HTML by stripping active and resource-loading elements. The editor does not execute embedded HTML or load remote content.

## macOS Service

After installing or launching Clasp, enable its two actions once:

1. Open **System Settings › Keyboard › Keyboard Shortcuts… › Services › Text**.
2. Turn on **Create Note in Clasp** and **Create Secure Note in Clasp**.

In local and direct builds, **Control-Option-Shift-N** creates a normal Inbox note and **Control-Option-Shift-P** creates a secure Vault note from the current selection. The first shortcut use asks for one-time approval under **System Settings › Privacy & Security › Accessibility** so Clasp can issue one `Command-C`; it does not listen to or monitor keyboard input. The App Store build compiles this Accessibility path out and uses Services only.

You can also right-click selected styled text, an image, or a link and choose **Services › Create Note in Clasp** or **Create Secure Note in Clasp**. The standard `NSServices` mechanism accepts plain text, URLs, RTF, sanitized HTML, common image types, and image file URLs without Accessibility permission. Clasp's onboarding and Help provide buttons for both Accessibility and Service settings.

macOS and the source app decide which Services appear for an image or link. If a particular app does not expose the content to Services, copy it and use Clasp's clipboard shortcut, menu-bar action, or Dock action instead. To change either default Service shortcut, open **System Settings › Keyboard › Keyboard Shortcuts… › Services › Text** and find the two Clasp entries.

## Data locations

Clasp keeps the original bundle identifier and logical `Personal Notepad` data-directory name. Local and direct builds use the paths below. The App Store build resolves them inside its sandbox container and carries an Apple container-migration manifest for the legacy folder; existing-data and Keychain custody still require a controlled signed-sandbox acceptance run before release.

- Local/direct regular notes: `~/Library/Application Support/Personal Notepad/Notes/`
  - One UTF-8 Markdown file per note, named with a UUID.
  - Clipped images live in the `Notes/Attachments/` tree. They and locally recognized text are plaintext, just like regular notes.
  - A small atomic sidecar stores each note's non-body metadata. `index.json` provides fast loading and can be rebuilt from the Markdown files and sidecars if it is missing, damaged, or interrupted during a save.
- Local/direct Vault: `~/Library/Application Support/Personal Notepad/Vault/`
  - `vault.pnvault` is a versioned AES-GCM encrypted container.
  - `vault.previous.pnvault` is the recoverable copy made before an import replaces the current encrypted container.
  - Vault titles, tags, bodies, image bytes, recognized image text, and timestamps are all inside ciphertext.

Regular Markdown is plaintext and is not appropriate for secrets.

## Backup and restore

For local/direct builds, back up the complete `~/Library/Application Support/Personal Notepad/` directory. For an App Store build, use the sandbox-container path shown in Clasp Help. These backups contain plaintext Markdown and should be protected accordingly.

For Vault recovery, open **Help › Clasp Help**, then use **Export Encrypted Vault**. The exported file is encrypted with a random 256-bit recovery key, shown once. Store the file and key separately. A lost recovery key cannot be recovered.

To restore, choose **Import Encrypted Vault**, confirm replacement, and enter the recovery key. The app validates the export before accepting it, preserves any current encrypted container as `vault.previous.pnvault`, and re-encrypts imported notes under the local Keychain-protected Vault key. On a new installation, import creates a fresh random local Vault key protected by macOS user presence.

## Onboarding and Help

Onboarding appears on first launch and can be reopened from the Help menu or Help window. To reset it manually:

```bash
defaults write com.robertmoore.personalnotepad onboardingComplete -bool false
```

Help includes shortcuts, Service setup, data locations, backup/restore, and the security limitations.

## Known limitations

- The default local build is ad-hoc signed for development on this Mac; it is not a notarized direct release or a Mac App Store build.
- The first Vault setup/unlock produces a normal macOS Keychain user-presence prompt (Touch ID when available, otherwise the macOS login password).
- macOS assigns and arbitrates global shortcuts. A conflicting app may prevent a default shortcut from registering; the same actions remain available from menus and the menu bar extra.
- macOS controls discovery and shortcuts for Services; enabling the two actions is sometimes a one-time System Settings step, and their defaults can be changed there.
- Local/direct cross-app selection shortcuts require one-time Accessibility approval because Clasp issues a single Copy command to the active app. The App Store build excludes that code; right-click Services require no Accessibility approval.
- Image capture is limited to 25 MB per image. Source apps control whether their image context menus expose macOS Services; copying the image first is the reliable fallback.
- There is no sync, collaboration, iPhone/iPad client, full document-layout word processor, non-image attachment support, or secure-delete guarantee on APFS/SSD storage. Clasp does include a focused Page / Markdown editor.
- Vault encryption protects data at rest. It cannot protect an unlocked Vault from malware, screen capture, memory inspection by a sufficiently privileged process, or a person controlling an already-unlocked Mac.
- Clipboard managers may retain sensitive values before optional safe clearing occurs, and choosing **Never** leaves the captured value on the system clipboard. Credentials, API keys, and recovery codes are generally better kept in a dedicated password manager.
