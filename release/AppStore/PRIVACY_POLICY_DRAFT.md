# Clasp privacy policy draft

Effective date: **TBD**
Public contact: **TBD**

Clasp is designed to keep note content on the user's Mac. Clasp does not require an account and does not intentionally collect, transmit, sell, or share note bodies, titles, tags, clipboard content, Vault content, identifiers, analytics, diagnostics, or advertising data.

Regular notes are stored as local Markdown. Vault content is encrypted locally using Apple CryptoKit; Clasp requires macOS authentication before reading its key from Keychain. The app's import, export, clipboard, selected-content, and image-recognition features run locally. The Mac App Store build receives updates through Apple. The separate direct-download build contacts the configured GitHub-hosted Sparkle feed only for software updates; it does not send note content.

Apple and GitHub may process download, update, store, or infrastructure data under their own terms when a person uses those distribution services. This draft must be reviewed, given an actual contact and effective date, hosted at a public HTTPS URL, and checked against the exact shipping binaries before use.
