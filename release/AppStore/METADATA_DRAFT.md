# App Store metadata draft

This copy is a draft for Robert's final approval and the Guideline 2.1 response follow-up. The related App Review submission `4f60dde3-4ad3-4d0b-a21b-3cc63edd7453` was **rejected — Guideline 2.1 Information Needed** for version/build `1.0.0 (8)`. The uploaded package SHA-256 is `09dcc9361d7a95c5cb699507b7a5d381c3d925b88130c346aae2e3fe6d80ccb0`; package processing is not App Review acceptance.

Response pack: [`APP_REVIEW_RESPONSE.md`](APP_REVIEW_RESPONSE.md) · physical one-take storyboard: [`APP_REVIEW_RECORDING.md`](APP_REVIEW_RECORDING.md)

The current physical Mac fact is MacBook Pro `Mac16,5`, M4 Max, `arm64`, macOS `26.5.2` build `25F84`. No physical TestFlight/latest-OS run is claimed. Current latest macOS is `26.6.2`, so latest-OS proof remains gated. Functions are region-consistent, and China mainland is intentionally excluded from availability.

- App Store product name: **Clasp: Private Markdown Notes**
- Installed app name: **Clasp**
- Publisher: **Paper LLC**
- Subtitle (30-character limit): **Catch notes. Keep them close.**
- Primary category: **Productivity**
- Support URL: **https://robertbmoore.github.io/clasp/**
- Support contact: **hello@paper.ai**
- Privacy Policy URL: **https://robertbmoore.github.io/clasp/privacy.html**
- Marketing URL: **TBD — optional**
- Review submission: **Rejected — Guideline 2.1 Information Needed** (`4f60dde3-4ad3-4d0b-a21b-3cc63edd7453`)
- Review build: **`1.0.0 (8)`**
- Uploaded package SHA-256: **`09dcc9361d7a95c5cb699507b7a5d381c3d925b88130c346aae2e3fe6d80ccb0`**
- Availability: **Functions are region-consistent; China mainland is intentionally excluded. Recheck live territories before resubmission.**

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

## Exact complete App Review notes

This is the canonical copy-paste body for the Guideline 2.1 response. It is intentionally evidence-gated; do not paste it while any `[PENDING ...]` field remains, and do not treat this text as proof that a physical/TestFlight/latest-OS run occurred.

```text
Clasp: Private Markdown Notes — Guideline 2.1 Information Needed response

App Review submission: 4f60dde3-4ad3-4d0b-a21b-3cc63edd7453
Version/build: 1.0.0 (8)
Uploaded package SHA-256: 09dcc9361d7a95c5cb699507b7a5d381c3d925b88130c346aae2e3fe6d80ccb0
Region recheck: [PENDING — REPLACE WITH `PASS_CHINA_MAINLAND_EXCLUDED` ONLY AFTER THE LIVE RECHECK]
Trader recheck: [PENDING — REPLACE WITH `PASS_NOT_TRADER` ONLY AFTER THE LIVE RECHECK]

Physical recording attachment:
The requested recording is [PENDING — ATTACH ONE-TAKE RECORDING; DO NOT TREAT THIS AS COMPLETED PROOF]. Exact App Store Connect attachment reference: [PENDING]. Exact filename: [PENDING]. SHA-256: [PENDING]. Byte size and duration: [PENDING]. The recording must follow APP_REVIEW_RECORDING.md and show the TestFlight build on a physical Mac using synthetic fixtures only.

Tested physical device and OS:
No physical TestFlight run is claimed yet. The current physical Mac available for the gated run is MacBook Pro Mac16,5, M4 Max, arm64, macOS 26.5.2 build 25F84. This is inventory, not run evidence. The current latest macOS is 26.6.2, so final latest-OS proof remains gated. The actual recording fields are [PENDING — FILL FROM THE PHYSICAL TESTFLIGHT RUN].

Purpose, audience, problem, and value:
Clasp is a local-first notes and capture app for individual Mac users. It catches thoughts, links, selected text, images, clipboard snippets, call notes, and journal entries, then keeps them searchable on the Mac. It solves transient, scattered capture without requiring an account or sending note content to a service. Regular notes remain portable local Markdown files; a separate local encrypted Vault protects sensitive notes with macOS user-presence authentication before the Vault key is read.

Setup, access, and sample data:
No login, account, invitation, demo credential, or special server access is required. Open the TestFlight/Mac App Store build, complete local first-launch setup, create a regular Inbox note, inspect Page and exact Markdown views, search for APPLE-REVIEW-SYNTHETIC-001, and close/reopen to verify local persistence. Create a Vault note using the synthetic body VAULT-SYNTHETIC-ONLY-002, complete the normal macOS user-presence prompt without recording a password, lock the Vault, and verify locked content is not shown. For Store selected-content capture through macOS Services, use macOS Services > Create Note in Clasp or Create Secure Note in Clasp; otherwise use the synthetic clipboard fixture APPLE-REVIEW-CLIPBOARD-003. The Store build omits Accessibility-assisted selection shortcuts and does not request Accessibility access. Use synthetic data only, including https://example.invalid/apple-review; never enter private material.

External services, data, authentication, payment, and AI:
There is no login/account system, purchase, IAP, subscription, payment flow, backend, cloud sync, analytics, tracking, external AI, or note-content transmission. There is no public/cloud UGC hosting or moderation service. Regular notes are local Markdown; Vault data is local encrypted data protected by macOS Keychain and LocalAuthentication. Apple Vision performs image-text recognition locally. The Store build uses Apple frameworks/platform facilities only, including SwiftUI, AppKit, Vision, CryptoKit, LocalAuthentication, Keychain, NSServices, and App Sandbox. Mac App Store builds update only through the Mac App Store and contain no third-party updater.

Regional consistency and China exclusion:
The functions and behavior are region-consistent wherever the app is available, with no region-specific feature, backend, data, payment, or content path. China mainland is intentionally excluded from availability. Recheck the live territory selection before resubmission and preserve that exclusion.

Regulated/protected-material applicability:
The developer is not a trader for the applicable App Store Connect declaration. Clasp is not a regulated product or service and does not provide regulated decisioning. The recording, screenshots, and fixtures contain no protected third-party material; they use only the developer's app UI and synthetic review data.

Evidence gate:
The physical TestFlight run, latest-OS check, one-take recording, attachment reference, and recording checksum remain [PENDING]. Do not interpret this response as claiming that any of those gates has passed.
```

## Explicit evidence blockers

- [ ] Capture and attach the one-take physical TestFlight recording; fill the attachment reference, filename, size, duration, and SHA-256.
- [ ] Record the physical device/OS during the run; no TestFlight run is currently claimed.
- [ ] Close the macOS `26.6.2` latest-OS gate with physical TestFlight evidence; if the Mac remains on `26.5.2`, do not record the final take or resubmit.
- [ ] Verify exact build `1.0.0 (8)` and package SHA-256 before resubmission.
- [ ] Recheck region availability and preserve China mainland exclusion.
- [ ] Keep the claims above: no login/account, purchase/IAP/subscription, public/cloud UGC/moderation, analytics/tracking, cloud sync, external AI/backend/content transmission; Apple frameworks only; Mac App Store updates only; local Markdown and local encrypted Vault; not a trader, not regulated, no protected third-party material.
