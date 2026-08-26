# App Store submission handoff and Guideline 2.1 response

This record binds the exact package workflow and App Store Connect delivery to the rejected review submission. Current review state: **rejected — Guideline 2.1 Information Needed** for submission `4f60dde3-4ad3-4d0b-a21b-3cc63edd7453`, version/build `1.0.0 (8)`. Blanks and `[PENDING ...]` fields are not evidence; never upload or describe a physical run that has not occurred, and never use a package whose checksum differs.

The response pack is [`APP_REVIEW_RESPONSE.md`](APP_REVIEW_RESPONSE.md), and the exact privacy-safe physical TestFlight storyboard is [`APP_REVIEW_RECORDING.md`](APP_REVIEW_RECORDING.md). This handoff is scoped to `release/AppStore/**`; it does not authorize source, script, workflow, version, or build-number changes.

## Review disposition and response gates

- App Review submission ID: `4f60dde3-4ad3-4d0b-a21b-3cc63edd7453`
- Review reason: **Guideline 2.1 — Information Needed**
- Reviewed build: `1.0.0 (8)`
- Uploaded package SHA-256: `09dcc9361d7a95c5cb699507b7a5d381c3d925b88130c346aae2e3fe6d80ccb0`
- Current physical Mac fact: MacBook Pro `Mac16,5`, M4 Max, `arm64`, macOS `26.5.2` build `25F84`
- Current latest macOS is `26.6.2`; latest-OS physical proof remains gated and is not claimed.
- Physical TestFlight run and one-take recording: **[PENDING — NO RUN/ATTACHMENT CLAIMED]**
- Recording attachment reference, filename, size, duration, and SHA-256: **[PENDING — FILL ONLY AFTER UPLOAD AND VERIFICATION]**
- Regional consistency: functions are region-consistent; China mainland is intentionally excluded from availability and must be rechecked before resubmission.

Unresolved live gates are listed in [`APP_REVIEW_RESPONSE.md`](APP_REVIEW_RESPONSE.md) and [`APP_REVIEW_RECORDING.md`](APP_REVIEW_RECORDING.md). The package's processed/eligible state is delivery evidence only; it is not App Review acceptance or physical/TestFlight evidence.

## Source and package

- Source commit SHA: `ab09cdaceac9d2c4dbf9e762e531daf6db40e4b8`
- Protected branch: `main`
- GitHub package workflow run URL: `https://github.com/RobertBMoore/clasp/actions/runs/32790427285`; both protected preflight and signed-package jobs passed against the exact source commit above. GitHub recorded archive digest `sha256:5795d154c7675bf5f22fa490632b88641ad8e3a1307bc375ba1d31411dd2381e`. This exact artifact was delivered to Apple under delivery UUID `2d7fac89-473a-46a2-818c-c7cd530ef0b0` and processed as `VALID` / `APP_STORE_ELIGIBLE`. Later merge `f62c246153469e2d4fcd97d13a342db8a81aaad8` changes only direct-release verification and does not alter this Store artifact.
- Registered explicit Bundle ID / Apple identifier record: `Clasp` / `com.robertmoore.personalnotepad`, Paper LLC team `R3Z7H2TRCB`, verified live 2026-08-24
- Expected Apple Developer Team ID from the account record (not artifact evidence): `R3Z7H2TRCB`
- App Store Connect app record: `Clasp: Private Markdown Notes`, macOS `1.0.0`, Apple app ID `6804786714`; the related submission `4f60dde3-4ad3-4d0b-a21b-3cc63edd7453` was rejected for Guideline 2.1 Information Needed. Sign-in is not required for the app, and the permanent SKU is intentionally withheld from this public repository.
- Version (`CFBundleShortVersionString`): `1.0.0`; the authenticated App Store Connect record and protected review artifact are aligned.
- Build (`CFBundleVersion`): `8`
- Last accepted build-number assertion, App Store Connect source, and checked date/time: protected `app-store-release` environment assertion `8`; Apple's terminal uploader result and the authenticated macOS `1.0.0` version page both showed processed build `1.0.0 (8)` on 2026-08-24. Build 8 was attached to the version and saved at approximately 7:39 PM CDT.
- Package filename: `Clasp-1.0.0-8-AppStore.pkg` (exact protected workflow artifact uploaded and processed)
- Package SHA-256: `09dcc9361d7a95c5cb699507b7a5d381c3d925b88130c346aae2e3fe6d80ccb0`
- Package-payload parity result: exact path/type/mode/symlink/hash/xattr parity and script-free, non-relocatable `/Applications` PackageInfo policy passed on GitHub's `macos-26` runner and again against the downloaded artifact on 2026-08-24. The corrected payload makes the embedded provisioning profile mode `0644`; the independent permission gate found no app-payload file without other-read and no directory without other-execute. The independent check also revalidated the exact application/installer certificate pins, provisioning profile, App Sandbox entitlements, migration manifest, Privacy manifest, absence of Sparkle and Accessibility selection capture, and `ITSAppUsesNonExemptEncryption=false`. The workflow removed its imported release credentials in the always-run cleanup step.
- Privacy policy URL embedded in the signed app: `https://robertbmoore.github.io/clasp/privacy.html`
- Signing Team ID observed from the exact packaged artifact: `R3Z7H2TRCB`
- Mac App Distribution identity and SHA-256 fingerprint: `3rd Party Mac Developer Application: Paper LLC (R3Z7H2TRCB)` / `C7:1E:DE:4E:76:1A:DB:6E:3B:1F:8C:B3:EB:2C:81:7D:0D:EC:3E:3C:03:18:EE:C5:EC:84:68:60:4B:B0:AB:D7`, verified locally 2026-08-24
- Mac Installer Distribution identity and SHA-256 fingerprint: `3rd Party Mac Developer Installer: Paper LLC (R3Z7H2TRCB)` / `D7:33:19:AA:7B:85:94:62:C3:B2:6E:6B:13:15:F8:D2:46:F6:FD:15:72:74:EC:CB:F8:C7:3A:02:93:F0:3D:9E`, verified locally 2026-08-24
- Provisioning profile UUID and expiry: `25535586-40DF-4EE1-AA8F-D57F2CFBD210` / 2027-08-24 18:42:28 UTC; `Clasp Mac App Store 2026`, exact certificate/bundle/team validation passed locally 2026-08-24

## Upload and processing

- Upload tool and version (Transporter, Xcode, or `altool`): `xcrun altool` / ContentDelivery `26.40.1 (174001)` on macOS `26.5.2 (25F84)`. The superseded SHA-256 `6b9944b5...a8854c` had failed `--validate-app` with `ITMS-90255`; PR #10 and protected run `32790427285` corrected and regression-tested that permission defect before this successful delivery.
- Upload date/time and operator: 2026-08-24 7:37:11 PM CDT; Robert-approved local Codex release session using the Paper LLC team API key
- Delivery/upload ID: `2d7fac89-473a-46a2-818c-c7cd530ef0b0`
- App Store Connect app ID: `6804786714`
- Bundle ID: `com.robertmoore.personalnotepad`
- App version/review record: macOS `1.0.0`; build `1.0.0 (8)` is the reviewed build, and submission `4f60dde3-4ad3-4d0b-a21b-3cc63edd7453` is rejected for Guideline 2.1 Information Needed. Recheck the live version state before resubmission.
- Build processing result and date/time: terminal `VALID`, `APP_STORE_ELIGIBLE`, `is-on-app-store-connect=true`; uploaded 2026-08-24 7:37:11 PM CDT and attached to version at approximately 7:39 PM CDT
- Apple validation tool/version and result before upload: `xcrun altool --validate-app` using ContentDelivery `26.40.1 (174001)` completed successfully with no validation errors against exact SHA-256 `09dcc936...ccb0`
- Export-compliance result: Account Holder confirmed exempt operating-system encryption; `ITSAppUsesNonExemptEncryption=false` is present in the exact package, passed independent artifact validation, and Apple processing returned `usesNonExemptEncryption=false`.
- Signed-sandbox acceptance evidence:
- Synthetic migration and Vault Keychain-custody record:
- App Review submission ID, submitted date/time, and current status: `4f60dde3-4ad3-4d0b-a21b-3cc63edd7453`; submitted date/time: **[PENDING — RECONCILE FROM APP STORE CONNECT HISTORY]**; current disposition: **Rejected — Guideline 2.1 Information Needed**. The physical TestFlight run, recording attachment, latest-OS proof, and final resubmission remain open.

## Listing and review

- Support URL: `https://robertbmoore.github.io/clasp/`
- Monitored support/security contact tested successfully: pending end-to-end test of `hello@paper.ai` and GitHub private vulnerability reporting
- Privacy policy URL: `https://robertbmoore.github.io/clasp/privacy.html`
- Screenshot set, dimensions, and source build:
- Primary/secondary category:
- Price, availability, and territories:
- Copyright:
- Content-rights answer:
- Age rating completed:
- App Privacy completed from final binary:
- Review notes finalized:
- Review contact and demo instructions finalized:
- Agreement/trader/tax gates cleared by Account Holder: Robert explicitly confirmed that Paper LLC is **not a trader** for this app. Recheck the live App Store Connect declaration and current agreements immediately before resubmission; this recorded instruction is not a substitute for fresh live-state evidence.
- Final human approval and date/time:

## Exact complete App Review notes

This is the canonical notes body for the Guideline 2.1 response. It is intentionally evidence-gated; do not paste it while any `[PENDING ...]` field remains.

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

Binary upload must use Xcode, Transporter, or Apple’s supported command-line upload path. Chrome is the handoff for the app record, metadata, compliance, processing, and review status; it is not the binary uploader.
