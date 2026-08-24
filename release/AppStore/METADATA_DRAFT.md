# App Store metadata draft

This copy is a draft for Robert's final approval.

- App Store product name: **Clasp: Private Markdown Notes**
- Installed app name: **Clasp**
- Publisher: **Paper LLC**
- Subtitle (30-character limit): **Catch notes. Keep them close.**
- Primary category: **Productivity**
- Support URL: **https://robertbmoore.github.io/clasp/**
- Support contact: **hello@paper.ai**
- Privacy Policy URL: **https://robertbmoore.github.io/clasp/privacy.html**
- Marketing URL: **TBD — optional**

## Screenshot candidates

Five synthetic-data candidates are stored in [`Screenshots/`](Screenshots/). They are non-transparent 2560×1600 JPEGs and cover the light editor, exact Markdown source, document-style controls, dark mode, and the bounded rich-formatting menu. They pass the repository screenshot validator, but must be compared with the exact final signed Store build and approved before upload.

## Promotional text

Catch the thought before it slips away—then find it when you need it.

## Description

Clasp is a private, local-first notes app for the Mac. Save quick thoughts, selected text, links, images, clipboard snippets, call notes, and journal entries without creating an account.

Regular notes stay as portable Markdown files on your Mac. Sensitive notes can live in a separate encrypted Vault; Clasp requires macOS authentication before reading its Keychain key. Quick Capture, keyboard shortcuts, Services, and menu-bar actions keep capture close without turning your notes into a cloud service.

Highlights:

- Fast Quick Capture from anywhere
- Portable local Markdown notes
- Encrypted Vault for sensitive notes
- Full-text search over unlocked content
- Clipboard and selected-content capture
- Native Mac menus, shortcuts, Services, and appearance
- No accounts, ads, analytics, cloud sync, or external AI services; image text recognition uses Apple Vision locally

Clasp cannot protect an already-unlocked Mac from malware or someone controlling the session. Credentials and recovery codes are still best kept in a dedicated password manager.

## Keywords draft

notes,notepad,markdown,capture,clipboard,journal,private,vault

## Review notes draft

Clasp is local-first and has no account. The Mac App Store build contains no Sparkle updater and updates only through the App Store. Regular notes are plaintext Markdown; Vault notes are AES-GCM encrypted, and Clasp authenticates the user before reading its Keychain key. Review instructions for Vault setup, selected-content capture through macOS Services, clipboard capture, import/export, and sandbox data migration must be completed against the final signed TestFlight build. The Store build omits Accessibility-assisted selection shortcuts and does not request Accessibility access.
