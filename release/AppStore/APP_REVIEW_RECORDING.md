# Apple App Review physical recording — one-take storyboard

Status: **evidence plan only; no physical TestFlight run or recording is claimed**

This is the exact storyboard for the Guideline 2.1 response to submission `4f60dde3-4ad3-4d0b-a21b-3cc63edd7453`. It is scoped to the Mac App Store/TestFlight build `1.0.0 (8)` and the uploaded package SHA-256 `09dcc9361d7a95c5cb699507b7a5d381c3d925b88130c346aae2e3fe6d80ccb0`. It does not authorize a build, source, script, workflow, version, or build-number change.

The recording is not evidence until a real physical run fills every required field, passes every gate below, and the exact file is attached to App Store Connect. A placeholder, storyboard, screenshot, local build, or source test cannot substitute for that run.

## One-take and privacy rules

- Capture one contiguous take from the physical Mac. Do not splice, speed up, crop, blur, overlay, or replace any portion of the evidence.
- Use a clean, dedicated macOS review user or otherwise close every unrelated app and window. Enable Do Not Disturb and disable notification previews before recording.
- Use only the synthetic fixtures in this document. Do not use real notes, clipboard values, names, email addresses, phone numbers, URLs, passwords, recovery keys, customer data, confidential material, or copyrighted third-party content.
- Do not show an Apple ID, personal email, user name, home-directory path, computer name, serial number, hardware UUID, Wi-Fi/network name, notification, browser history, Messages, Mail, cloud storage, password manager, or other private surface. If any such value appears, discard the take and recapture from a clean state; post-capture redaction does not make a one-take record acceptable.
- Do not show or speak a macOS password, Touch ID secret, Keychain secret, recovery key, or TestFlight credential. It is acceptable to show the normal macOS user-presence prompt and the resulting app state; the credential itself must never be visible.
- Keep microphone audio off unless the exact narration below is recorded without personal information. The visual record is sufficient; system audio must not capture private notifications or other apps.
- Do not open a browser, Terminal, Mail, Messages, cloud drive, public UGC surface, payment surface, or external AI service. The only non-Clasp surfaces are TestFlight, a blank local text editor used for the Services fixture, and—only after the privacy preflight below—a safe About This Mac view.
- Do not claim that a test happened because the storyboard was followed. The evidence fields below are blank until the take actually occurs.

## Synthetic fixture ledger

Type each fixture exactly as shown, including capitalization and punctuation. These values are intentionally non-real and use the reserved `example.invalid` domain.

### Regular Markdown fixture

- Title: `Apple Review Fixture — Local Markdown`
- Body:

  ```text
  # Apple Review Fixture

  Purpose: verify a local note.
  Audience: an individual Mac user.
  Token: APPLE-REVIEW-SYNTHETIC-001
  URL: https://example.invalid/apple-review
  ```

### Encrypted Vault fixture

- Title: `Apple Review Fixture — Encrypted Vault`
- Body: `Synthetic secret: VAULT-SYNTHETIC-ONLY-002`

### Clipboard and Services fixture

- Text: `APPLE-REVIEW-CLIPBOARD-003 — synthetic text only`
- Optional selected-content source: a new blank local text-editor document containing exactly the Clipboard and Services fixture text.

### Fixture manifest fields

- Planned fixture manifest filename: **[PENDING — CREATE FROM THE EXACT FIXTURES USED IN THE TAKE]**
- Planned fixture manifest SHA-256: **[PENDING — COMPUTE AFTER FIXTURES ARE FROZEN]**
- Fixture-only confirmation: **[PENDING — OPERATOR CONFIRMS NO PRIVATE OR THIRD-PARTY DATA APPEARED]**

## Pre-capture gates

Complete these checks before pressing record. A failed check stops the take.

1. Confirm the physical machine is the available MacBook Pro model `Mac16,5`, Apple M4 Max, `arm64`, currently observed on macOS `26.5.2` build `25F84`. Record the observation in the evidence fields; do not call it a completed TestFlight test.
2. Confirm the current latest macOS is `26.6.2`. If the machine remains on `26.5.2`, stop: do not make the final take and do not resubmit. This rejection-response gate closes only with a physical TestFlight run on `26.6.2` and an observed OS build recorded in the evidence manifest.
3. Confirm TestFlight shows the exact app and build `Clasp: Private Markdown Notes`, `1.0.0 (8)`. Do not use a local, ad-hoc, direct-download, or merely staged bundle for this recording.
4. Confirm the Mac App Store package custody reference is still SHA-256 `09dcc9361d7a95c5cb699507b7a5d381c3d925b88130c346aae2e3fe6d80ccb0`. This known package hash does not itself prove a physical run.
5. Close unrelated apps, clear the clipboard, enable Do Not Disturb, and prepare only the blank local text editor if the Services step will be recorded.
6. Confirm recording storage has enough space and that the capture format preserves the original file bytes. Do not export through a service that recompresses or changes the evidence without hashing the final attachment.

## Exact one-take storyboard

Use the following order without pauses that require editing. The time ranges are guidance for one continuous take; record the complete UI states and do not cut between them.

### 00:00–00:20 — clean starting state

1. Start the screen recording with microphone off.
2. Show the clean desktop and the macOS menu bar only long enough to establish that no private windows or notifications are present.
3. If a private value appears, stop, clean the environment, and restart the take. Do not rely on later redaction.

### 00:20–00:55 — physical Mac and OS identity

1. Before recording, inspect **About This Mac** and confirm the exact view can show the model/chip and macOS version without a serial number, hardware UUID, user name, computer name, Apple ID, or account detail.
2. During the take, open that About This Mac view only if the preflight proved it privacy-safe. If any private identifier appears, stop and discard the take; do not crop or blur it later.
3. Do **not** open System Information during the recording. Its standard hardware views can expose serial-number or hardware-UUID data. If About This Mac cannot be shown safely, omit this on-screen segment and provide the independently observed device/OS list in the App Review response instead; Apple does not need a private device identifier.
4. The spoken or on-screen statement, if used, is: `Physical test device: MacBook Pro Mac16,5, M4 Max, arm64, macOS [READ THE INDEPENDENTLY OBSERVED VERSION AND BUILD].`

### 00:55–01:25 — TestFlight build identity

1. Open TestFlight and show only the Clasp app row and its version/build.
2. The spoken or on-screen statement, if used, is: `TestFlight app under review: Clasp: Private Markdown Notes, version 1.0.0, build 8.`
3. Do not show an Apple ID, email address, account menu, personal profile, or unrelated app.
4. Launch Clasp from this TestFlight entry. If the displayed build is not exactly `1.0.0 (8)`, stop and mark the take failed.

### 01:25–02:05 — first launch and purpose

1. Complete only the local first-launch setup with default choices; do not enter an account or credentials because none are required.
2. Show the main Clasp window and the local Inbox/notes surface.
3. The spoken or on-screen statement, if used, is: `Clasp is for individual Mac users who want local, searchable capture without an account or cloud note service.`
4. Do not open a network panel or any external service. This step demonstrates the product purpose, not a claim that the app has network access.

### 02:05–02:55 — regular local Markdown note

1. Create a regular Inbox note titled exactly `Apple Review Fixture — Local Markdown`.
2. Enter the exact Regular Markdown fixture from this document.
3. Save it, show the Page view, then switch to Markdown view and show the exact source text.
4. Search for `APPLE-REVIEW-SYNTHETIC-001` and show the matching local note.
5. The spoken or on-screen statement, if used, is: `This regular note is synthetic data stored as local Markdown on this Mac.`

### 02:55–03:40 — Vault authentication and lock state

1. Choose the secure/Vault note action and create `Apple Review Fixture — Encrypted Vault`.
2. When macOS requests user presence, complete it without exposing a password or recovery key. Do not narrate or display any secret.
3. Enter exactly `Synthetic secret: VAULT-SYNTHETIC-ONLY-002`, save, and show the note while the Vault is unlocked.
4. Lock the Vault. Show that the Vault note is no longer visible in locked state, then unlock once more only if needed to show the same synthetic note and immediately lock it again.
5. The spoken or on-screen statement, if used, is: `Vault content is local encrypted data and requires normal macOS user presence before the Vault key is read.`

### 03:40–04:25 — Services/clipboard capture

1. Open a new blank local text-editor document containing exactly `APPLE-REVIEW-CLIPBOARD-003 — synthetic text only`.
2. Select that text and choose **Services › Create Note in Clasp**. If the Service is not available, stop this branch and use the Clasp menu-bar/Dock clipboard action with the same synthetic text; do not enable or demonstrate Accessibility capture for the Store build.
3. Show the resulting local Inbox note and its synthetic body. Do not expose any other text-editor document or recent-document list.
4. The spoken or on-screen statement, if used, is: `The Store build uses macOS Services or a one-time synthetic clipboard capture; it does not use Accessibility-assisted selection capture.`

### 04:25–05:00 — persistence and limits

1. Close and relaunch Clasp from the same TestFlight-installed app while the recording continues.
2. Show the regular synthetic note after relaunch. Do not show any private file path or unrelated recent item.
3. Do not open Help or another optional surface; keep the evidence focused on the tested core flow.
4. The spoken or on-screen statement, if used, is: `There is no account, purchase, subscription, analytics, cloud sync, external AI, backend, or note-content transmission in this Store build.`

### 05:00–05:20 — final locked state and end

1. Lock the Vault if it is unlocked.
2. Return to the Clasp main window with only synthetic local content visible.
3. Quit Clasp and stop the recording. Do not open another app after stopping.

## Evidence fields

Fill these from the original capture and the exact App Store Connect attachment. Do not copy values from an earlier run.

The Markdown fields below are the human-readable storyboard. The machine gate is [`APP_REVIEW_EVIDENCE.env`](APP_REVIEW_EVIDENCE.env): copy that file, this recording plan, the final response, exact protected package, original recording, exact file selected for upload, and [`APP_REVIEW_FIXTURES.txt`](APP_REVIEW_FIXTURES.txt) into one dedicated evidence directory. Fill every manifest value from observed evidence. The final response and completed recording record must be separate files with `FINAL` statuses; never pass or overwrite the checked-in drafts merely to make them appear complete.

Immediately before the App Store Connect reply or upload, run:

```bash
./script/validate_app_review_evidence.sh --final \
  --response /absolute/evidence/APP_REVIEW_RESPONSE_FINAL.md \
  --recording-plan /absolute/evidence/APP_REVIEW_RECORDING_FINAL.md \
  --manifest /absolute/evidence/APP_REVIEW_EVIDENCE.env \
  --package /absolute/evidence/Clasp-1.0.0-8-AppStore.pkg \
  --video /absolute/evidence/clasp-apple-review.mov \
  --attachment /absolute/evidence/clasp-apple-review-upload.mov \
  --fixtures /absolute/evidence/APP_REVIEW_FIXTURES.txt
```

The validator hashes the actual package, video, upload file, and fixture ledger; decodes the recording to measure duration and resolution; rejects draft contradictions; binds privacy and independent reviews to the exact recording SHA-256; and requires fresh region/China and trader-declaration checks. Do not upload the private review recording to this public repository or to ordinary CI artifacts.

- App Review submission ID: `4f60dde3-4ad3-4d0b-a21b-3cc63edd7453`
- App/version/build: `Clasp: Private Markdown Notes` / `1.0.0 (8)`
- Uploaded package SHA-256: `09dcc9361d7a95c5cb699507b7a5d381c3d925b88130c346aae2e3fe6d80ccb0`
- TestFlight app/build identifier: **[PENDING — RECORD FROM TESTFLIGHT]**
- TestFlight installation source: **[PENDING — CONFIRM TESTFLIGHT, NOT LOCAL/AD-HOC/DIRECT]**
- Physical device model: **[PENDING — RECORD DURING TAKE]**
- Chip and architecture: **[PENDING — RECORD DURING TAKE]**
- macOS version and build: **[PENDING — RECORD DURING TAKE]**
- Latest-OS proof (`26.6.2`): **[PENDING — PHYSICAL TESTFLIGHT PROOF REQUIRED BEFORE RESUBMISSION]**
- Recording start date/time and timezone: **[PENDING — FILL FROM CAPTURE RECORD]**
- Recording duration: **[PENDING — FILL FROM ORIGINAL FILE]**
- Recording format/container and resolution: **[PENDING — FILL FROM ORIGINAL FILE]**
- Original recording filename: **[PENDING — FILL BEFORE UPLOAD]**
- Original recording byte size: **[PENDING — FILL FROM ORIGINAL FILE]**
- Original recording SHA-256: **[PENDING — COMPUTE FROM ORIGINAL FILE]**
- Uploaded attachment filename: **[PENDING — FILL FROM APP STORE CONNECT ATTACHMENT]**
- Uploaded attachment byte size: **[PENDING — VERIFY EXACT MATCH TO ORIGINAL]**
- Uploaded attachment SHA-256: **[PENDING — VERIFY EXACT MATCH TO ORIGINAL]**
- App Store Connect attachment reference: **[PENDING — FILL AFTER UPLOAD]**
- Fixture manifest filename: **[PENDING — FILL AFTER FIXTURES ARE FROZEN]**
- Fixture manifest SHA-256: **[PENDING — COMPUTE AND RECORD]**
- Capture operator: **[PENDING — FILL WITH APPROVED OPERATOR IDENTIFIER]**
- Privacy review result: **[PENDING — PASS ONLY AFTER FULL TAKE REVIEW]**
- Evidence reviewer and review date: **[PENDING — FILL AFTER INDEPENDENT CHECK]**

## Redaction and checksum record

The accepted record must be privacy-safe before upload. Use the original unedited one-take file for all hashes. If the attachment service changes the bytes, treat it as a different artifact and record both hashes; do not silently substitute one for the other.

| Artifact | Required value | Gate |
| --- | --- | --- |
| Original one-take recording | SHA-256, bytes, duration, container, resolution | Must be computed from the exact original file |
| Uploaded App Store attachment | SHA-256, bytes, attachment reference | Must match the reviewed original or explain a service-preserving byte change |
| Fixture manifest | SHA-256 and exact fixture text | Must contain synthetic values only |
| Store package | `09dcc9361d7a95c5cb699507b7a5d381c3d925b88130c346aae2e3fe6d80ccb0` | Must remain the known uploaded package custody value |

Required privacy review statements:

- [ ] No personal, account, credential, payment, private-note, cloud, browser, notification, or third-party content is visible or audible.
- [ ] No password, Touch ID secret, Keychain value, recovery key, or TestFlight credential is visible or audible.
- [ ] No post-capture blur, crop, splice, overlay, speed change, or content replacement was used.
- [ ] All visible note, clipboard, Services, and Vault content matches the synthetic fixture ledger.
- [ ] The exact uploaded attachment bytes were hashed after upload or the attachment service's byte-preservation behavior was independently recorded.

## Acceptance gates

Every gate must be checked before the response is represented as complete. An unchecked gate is an explicit blocker, not an invitation to infer success.

- [ ] Physical Mac identity and observed OS/build are recorded during the one-take.
- [ ] The app was installed and launched from TestFlight, and the visible build is exactly `1.0.0 (8)`.
- [ ] The latest-OS gate is closed with physical TestFlight evidence on macOS `26.6.2`; otherwise resubmission remains blocked.
- [ ] The recording is one contiguous take with no post-capture edits.
- [ ] The recording shows only synthetic fixtures and passes the privacy review.
- [ ] Regular local Markdown persistence and exact Markdown view are shown.
- [ ] Vault local encryption/user-presence and locked state are shown without exposing a secret.
- [ ] Store Services/clipboard behavior is shown without Accessibility-assisted selection capture.
- [ ] No login/account, purchase/IAP/subscription, public/cloud UGC/moderation, analytics/tracking, cloud sync, external AI, backend, or content transmission is introduced by the flow.
- [ ] Original and uploaded recording checksums, byte sizes, duration, and attachment reference are filled and verified.
- [ ] The package custody hash remains `09dcc9361d7a95c5cb699507b7a5d381c3d925b88130c346aae2e3fe6d80ccb0`.
- [ ] Regional behavior is stated as consistent, China mainland remains intentionally excluded, and live availability is rechecked before resubmission.
- [ ] The exact notes in [`APP_REVIEW_RESPONSE.md`](APP_REVIEW_RESPONSE.md), [`READINESS.md`](READINESS.md), [`SUBMISSION_HANDOFF.md`](SUBMISSION_HANDOFF.md), and [`METADATA_DRAFT.md`](METADATA_DRAFT.md) match the final evidence.
- [ ] An independent reviewer confirms the recording and all fields before App Store Connect attachment.
- [ ] The structured final evidence bundle passes `script/validate_app_review_evidence.sh --final` immediately before the live reply/upload.
