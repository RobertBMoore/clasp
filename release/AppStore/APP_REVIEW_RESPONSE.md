# Apple App Review response — Guideline 2.1 Information Needed

Status: **rejected; Information Needed under Guideline 2.1**

- App Review submission: `4f60dde3-4ad3-4d0b-a21b-3cc63edd7453`
- App/version/build: `Clasp: Private Markdown Notes` / `1.0.0 (8)`
- Uploaded package SHA-256: `09dcc9361d7a95c5cb699507b7a5d381c3d925b88130c346aae2e3fe6d80ccb0`
- Response scope: the Mac App Store build only; no source, script, workflow, version, or build-number changes are part of this pack.

## Submission safety

This document is a copy-paste-ready response template, but it is **not ready to send while any `[PENDING ...]` field remains**. A bracketed field is an evidence gate, not a claim that the physical run, TestFlight install, latest-OS check, recording, checksum, or App Store attachment exists. Replace a field only with a value from the corresponding evidence record; never replace it with an assumption.

The companion storyboard is [`APP_REVIEW_RECORDING.md`](APP_REVIEW_RECORDING.md). It specifies the one-take, privacy-safe physical-Mac recording Apple requested. No physical TestFlight run or recording is claimed by this repository state.

## Seven Apple-requested answers

### 1. Physical recording attachment reference

**Apple-facing answer:**

The requested physical-Mac recording is not attached yet. Before resubmission, attach exactly one contiguous, privacy-safe recording made on a physical Mac from the TestFlight build `1.0.0 (8)`, following [`APP_REVIEW_RECORDING.md`](APP_REVIEW_RECORDING.md). The attachment reference, filename, byte size, duration, and SHA-256 must replace the following explicit placeholders:

- App Store Connect attachment reference: **[PENDING — ATTACH ONE-TAKE RECORDING; DO NOT SUBMIT AS COMPLETE]**
- Attachment filename: **[PENDING — FILL FROM THE UPLOADED APP REVIEW ATTACHMENT]**
- Recording SHA-256: **[PENDING — COMPUTE SHA-256 OF THE EXACT UPLOADED FILE]**
- Recording byte size and duration: **[PENDING — FILL FROM THE EXACT UPLOADED FILE]**

Until those fields are filled and independently checked, there is no recording evidence to provide to Apple.

### 2. Tested physical device and operating system

**Apple-facing answer:**

No physical TestFlight run is claimed yet. The current physical Mac available for the gated run is a **MacBook Pro, model identifier `Mac16,5`, Apple M4 Max, `arm64`, running macOS `26.5.2` build `25F84`**. This is a current hardware/OS fact, not a record that the TestFlight build has been installed or exercised. The current latest macOS is **`26.6.2`**; final latest-OS proof remains gated, and this response must not describe `26.5.2` as the latest OS.

The recorder must re-observe and fill these evidence fields during the actual run:

- Physical device observed: **[PENDING — RECORD MODEL, CHIP, AND ARCHITECTURE DURING THE ONE-TAKE RUN]**
- OS/version/build observed: **[PENDING — RECORD DURING THE ONE-TAKE RUN; DO NOT INFER FROM THIS TEMPLATE]**
- TestFlight build/version observed: **[PENDING — RECORD `1.0.0 (8)` FROM TESTFLIGHT]**
- TestFlight install/run date and time: **[PENDING — FILL AFTER THE PHYSICAL RUN]**
- Latest-OS check: **[PENDING — macOS `26.6.2` PHYSICAL PROOF REQUIRED, OR MARK THE GATE OPEN]**

### 3. Purpose, audience, problem, and value

**Apple-facing answer:**

Clasp: Private Markdown Notes is a local-first notes and capture app for individual Mac users. It is for people who want to catch thoughts, links, selected text, images, clipboard snippets, call notes, and journal entries and then find them locally. The problem is that useful thoughts are often scattered across transient capture surfaces; Clasp provides a native Mac place to capture and search them without requiring an account or sending note content to a service. Regular notes remain portable local Markdown files. A separate local encrypted Vault provides a protected place for sensitive notes, with macOS user-presence authentication before the Vault key is read. The value is fast, private, portable capture that remains on the user's Mac.

### 4. Setup, access, and sample data

**Apple-facing answer:**

No login, account, invitation, demo credential, or special server access is required. Install the Mac App Store/TestFlight build, open Clasp, complete the local first-launch setup, and choose the regular Inbox for the first note. The review flow uses synthetic fixtures only:

- Regular-note title: `Apple Review Fixture — Local Markdown`
- Regular-note body: `Purpose: verify a local note.` / `Token: APPLE-REVIEW-SYNTHETIC-001` / `URL: https://example.invalid/apple-review`
- Vault-note title: `Apple Review Fixture — Encrypted Vault`
- Vault-note body: `Synthetic secret: VAULT-SYNTHETIC-ONLY-002`
- Selected-content/clipboard fixture: `APPLE-REVIEW-CLIPBOARD-003 — synthetic text only`

The reviewer can create the regular fixture, view its Page and exact Markdown representations, search for `APPLE-REVIEW-SYNTHETIC-001`, and close/reopen the app to verify local persistence. The reviewer can then create the Vault fixture, complete the normal macOS user-presence prompt without exposing a password, lock the Vault, and verify that locked Vault content is not shown. For selected-content capture in the Store build, use the macOS Services actions **Create Note in Clasp** or **Create Secure Note in Clasp**; the Store build does not use Accessibility-assisted selection capture. If a Service is unavailable in the source app, use the synthetic clipboard fixture through the Clasp menu-bar or Dock action.

Do not enter a real name, email address, phone number, URL, note, clipboard value, password, recovery key, or other private material during review or recording. The fixtures are deliberately synthetic and use the reserved `example.invalid` domain.

### 5. External services, data, authentication, payment, and AI

**Apple-facing answer:**

The Store build has no login or account system, purchases, in-app purchases, subscriptions, payment flow, backend, cloud sync, analytics, tracking, external AI, or note-content transmission. It has no public or cloud user-generated-content service and therefore no public-content hosting or moderation system. It does not call an external service to save, search, classify, or transmit notes. Regular notes are local Markdown files; Vault content is local encrypted data protected by the macOS Keychain and LocalAuthentication user-presence flow. Apple Vision performs image-text recognition locally when used. App Store builds update only through the Mac App Store and do not include a third-party updater.

The Store build uses Apple frameworks and platform facilities only, including **SwiftUI, AppKit, Vision, CryptoKit, LocalAuthentication, Keychain, NSServices, and App Sandbox**. No third-party runtime service or external AI provider is required.

### 6. Regional consistency and China exclusion

**Apple-facing answer:**

The functions and behavior described above are consistent in every territory in which the app is made available. There is no region-specific feature, backend, data-processing path, payment path, or content variation. **China mainland is intentionally excluded from availability** as a release-availability decision; it is not a hidden feature difference or a claim that the app has been tested there. Recheck the live territory selection before resubmission and preserve the exclusion.

### 7. Regulated or protected-material applicability

**Apple-facing answer:**

Clasp is **not a trader** for the applicable App Store Connect declaration, and it is **not a regulated product or service**. It does not provide medical, financial, legal, identity, employment, safety-critical, or other regulated decisioning. The response, recording, screenshots, and synthetic fixtures contain **no protected third-party material**. They use only the developer's app UI and synthetic review data; no copyrighted third-party article, customer data, confidential material, or protected content is included.

## Exact complete App Review notes

The following is the canonical complete notes body for the rejected submission follow-up. It is intentionally evidence-gated. Do not paste it into App Store Connect until every `[PENDING ...]` field is replaced by checked evidence; submitting the placeholders as if they were proof would be inaccurate.

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

## Evidence blockers before resubmission

- [ ] Complete one privacy-safe one-take run from the physical TestFlight build and attach it in App Store Connect.
- [ ] Record the physical Mac and OS/build during that run; do not call macOS `26.5.2` the latest OS.
- [ ] Close or explicitly accept the macOS `26.6.2` latest-OS gate with evidence; until then, latest-OS proof is absent.
- [ ] Compute and independently verify the exact recording SHA-256, size, duration, and attachment reference.
- [ ] Recheck that the observed TestFlight build is exactly `1.0.0 (8)` and that the package custody remains SHA-256 `09dcc9361d7a95c5cb699507b7a5d381c3d925b88130c346aae2e3fe6d80ccb0`.
- [ ] Recheck live App Store Connect availability and preserve the intentional China mainland exclusion.
- [ ] Replace every `[PENDING ...]` field in this response, the storyboard, and the handoff only after the evidence exists; then perform final human/legal review.
