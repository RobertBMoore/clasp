# Mac App Store readiness and Guideline 2.1 response

Status: **rejected — Guideline 2.1 Information Needed**. App Review submission `4f60dde3-4ad3-4d0b-a21b-3cc63edd7453` concerns version/build `1.0.0 (8)`. The package was uploaded and processed, but processing is not App Review acceptance; the uploaded package SHA-256 remains `09dcc9361d7a95c5cb699507b7a5d381c3d925b88130c346aae2e3fe6d80ccb0`.

This is a custody and evidence-gating checklist, not proof that a physical TestFlight run, latest-OS run, recording attachment, or resubmission has occurred. The owned response pack is [`APP_REVIEW_RESPONSE.md`](APP_REVIEW_RESPONSE.md), with the exact one-take physical-Mac storyboard in [`APP_REVIEW_RECORDING.md`](APP_REVIEW_RECORDING.md).

## Current review state and live blockers

- Rejected submission: `4f60dde3-4ad3-4d0b-a21b-3cc63edd7453`
- Review reason: **Guideline 2.1 — Information Needed**
- Reviewed version/build: `1.0.0 (8)`
- Uploaded package SHA-256: `09dcc9361d7a95c5cb699507b7a5d381c3d925b88130c346aae2e3fe6d80ccb0`
- Physical hardware fact available for the gated run: MacBook Pro `Mac16,5`, M4 Max, `arm64`, macOS `26.5.2` build `25F84`
- Current latest macOS is `26.6.2`; no latest-OS run is claimed, and latest-OS proof remains gated.
- Functions are region-consistent; China mainland is intentionally excluded from availability.

Before resubmission, all of these remain explicit blockers:

- [ ] Run the exact TestFlight build on a physical Mac and record the observed device, OS/version/build, and TestFlight build identity.
- [ ] Capture and attach one privacy-safe, contiguous recording using [`APP_REVIEW_RECORDING.md`](APP_REVIEW_RECORDING.md); fill its attachment reference, size, duration, and SHA-256.
- [ ] Close the macOS `26.6.2` latest-OS gate with physical TestFlight evidence. If the physical Mac is still on `26.5.2`, do not record the final take or resubmit.
- [ ] Independently verify that the observed TestFlight build is `1.0.0 (8)` and that package custody still matches the full SHA-256 above.
- [ ] Recheck live App Store Connect territories and preserve intentional China mainland exclusion.
- [ ] Replace every `[PENDING ...]` field in the response pack only after evidence exists; perform final human/legal review.
- [ ] Build the structured evidence bundle from [`APP_REVIEW_EVIDENCE.env`](APP_REVIEW_EVIDENCE.env), keep the recording out of this public repository and ordinary CI artifacts, and require `script/validate_app_review_evidence.sh --final` to pass immediately before the live reply/upload.

## Exact complete App Review notes

These notes are the canonical copy-paste body for the Guideline 2.1 response. They remain evidence-gated: do not submit them while a `[PENDING ...]` field remains, and do not treat their presence as proof that the physical/TestFlight/latest-OS gates passed.

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

## Build and account gates

- [x] Verify live access to the Apple Developer Program team and the App Store Connect account. On 2026-08-24, Chrome showed Paper LLC team `R3Z7H2TRCB` and an active Free Apps Agreement. Robert, acting as Account Holder, explicitly confirmed that Paper LLC is **not a trader** for this app; the live App Store Connect declaration still must be rechecked immediately before resubmission. The Paid Apps Agreement remains unsigned and is not required for a free app with no paid content.
- [ ] Revalidate active membership, Account Holder/Admin authority, current agreements, and exact team immediately before generating credentials, packaging, or uploading; the dated browser observation above is not standing authorization or fresh release evidence.
- [x] Register the explicit App ID / Bundle ID `com.robertmoore.personalnotepad` in the correct Apple Developer team; Apple Developer now lists it as `Clasp` under Paper LLC team `R3Z7H2TRCB`.
- [x] Create the App Store Connect macOS app record using that exact registered Bundle ID. On 2026-08-24, Apple created `Clasp: Private Markdown Notes` for macOS under Paper LLC team `R3Z7H2TRCB`, Apple app ID `6804786714`, now aligned to version `1.0.0` in `Prepare for Submission`; sign-in is not required and release is manual. The permanent SKU was verified in the authenticated account and is intentionally withheld from this public repository.
- [x] Install valid Mac App Distribution and Mac Installer Distribution identities and a Clasp-only App Store provisioning profile. On 2026-08-24, Apple issued both Paper LLC identities through 2027-08-24; the login Keychain holds their matching private keys, and profile `Clasp Mac App Store 2026` binds `R3Z7H2TRCB.com.robertmoore.personalnotepad` to the exact application certificate through 2027-08-24. No private key, CSR, certificate export, or profile is stored in this repository.
- [x] Enforce the deliberate Apple-silicon `arm64` architecture policy in local, direct, Store, CI, and artifact validation paths. Intel support is outside 1.0 until a universal build receives real Intel acceptance testing.
- [x] Compile and test every production source boundary from clean isolated scratch paths: 185/185 local tests, 179/179 Store tests, and 185/185 direct-distribution tests pass with zero failures. Public GitHub CI run `https://github.com/RobertBMoore/clasp/actions/runs/32755060746` independently passed the local, Store, direct-download, and release-contract boundaries from published commit `71c7ae55ef50e8908ce72bdb57ac2ebb862b08f0` in 5m 11s. Permission repair PR #10 passed CI run `32789879116` and merged as `ab09cdaceac9d2c4dbf9e762e531daf6db40e4b8`; macOS 26 direct-verifier repair PR #11 passed CI run `32792418524` and merged as `f62c246153469e2d4fcd97d13a342db8a81aaad8`. The Store binary is `arm64`; Sparkle, Accessibility/CGEvent capture symbols, and external Store dependencies are absent. These are source/product proofs only, not evidence of App Store Connect upload, processing, or acceptance.
- [x] Protect public `main` with pull requests, current-branch enforcement, required GitHub Actions check `test-and-package-local`, conversation resolution, and linear history. Configure `release` and `app-store-release` as reviewer-gated, protected-branch-only environments with administrator bypass disabled. The Store environment holds the exact Application/Installer P12s, passwords, provisioning profile, identities, certificate pins, and account assertions needed for review-only packaging. The direct environment holds the dedicated Sparkle private key and Apple notarization API credentials plus the exact public key, update-feed URL, Developer ID identity, and certificate pin; repository mirrors support the tag-triggered published-acceptance workflow. Protected run `32792893098` proved this custody by producing a notarized, Sparkle-signed private draft and cleaning its ephemeral credentials.
- [x] Produce a local review Store app from merged `main` commit `8f4dbc3dc32f500a766ecd421d06a26c9d81c2fe`, sign it with the exact Paper LLC Mac App Distribution certificate, and prove `com.apple.security.app-sandbox=true` plus the reviewed file-access entitlements. This is local artifact evidence, not App Store Connect delivery or Apple acceptance.
- [ ] Validate that the Vault Keychain item, local Markdown/Vault paths, Services-based selected-content capture, clipboard capture, global hotkeys, import/export panels, onboarding, and relaunch all work inside App Sandbox. The Store build intentionally excludes direct-channel Accessibility capture.
- [x] Embed a byte-locked Apple container-migration manifest for the complete legacy Application Support folder and validate its exact source/destination paths in the artifact gate.
- [x] Make Store packaging require a non-reserved public HTTPS privacy-policy host, require anonymous reachability in the protected workflow, embed that exact value into the signed app, and expose valid HTTPS URLs from Help.
- [x] Publish and review the final policy from [`docs/privacy.md`](../../docs/privacy.md), then prove `https://robertbmoore.github.io/clasp/privacy.html` is anonymously reachable. GitHub Pages build `1172738403` published merge commit `09033781b131fad5812034132cb50d3214f436d1` on 2026-08-24, and anonymous HTTPS requests returned `200` for both the Support and Privacy URLs.
- [ ] Prove the exact Privacy URL matches both the signed app and the App Store listing. The merged-source local signed app embeds `https://robertbmoore.github.io/clasp/privacy.html` and the protected `app-store-release` environment holds the same value; the listing has not been completed, so this gate remains open. Source review and anonymous reachability do not certify Apple's acceptance or every legal conclusion.
- [x] Add a fail-closed finished-installer validator that expands the package, verifies its code signature and exact `/Applications` non-relocatable/script-free `PackageInfo` policy, and compares path/type/mode/symlink/hash/xattr manifests with the validated staged app. Synthetic fixtures and the merged-source local signed package both pass; the validator pins the exact application and installer certificate SHA-256 fingerprints and rejects ambiguous PackageKit transcripts.
- [ ] Complete [`MIGRATION_ACCEPTANCE.md`](MIGRATION_ACCEPTANCE.md) on a disposable macOS user/VM with synthetic data before any controlled copy of real data. Do not ship until one-way path migration, note counts/checksums, Vault Keychain custody, Trash recovery, export, and fallback recovery are proven without making real notes the first test.
- [x] Upload a signed installer through Apple's supported delivery path and review every App Store Connect processing result. Protected run `https://github.com/RobertBMoore/clasp/actions/runs/32790427285` produced the exact artifact from protected `main` commit `ab09cdaceac9d2c4dbf9e762e531daf6db40e4b8`: `Clasp-1.0.0-8-AppStore.pkg`, SHA-256 `09dcc9361d7a95c5cb699507b7a5d381c3d925b88130c346aae2e3fe6d80ccb0`. Exact Application/Installer pins, provisioning profile, App Sandbox entitlements, migration and Privacy manifests, PackageKit policy, checksum, payload parity, root-readable/traversable payload permissions, absence of Sparkle/Accessibility capture, and exempt-encryption declaration passed in protected CI and independent downloaded-artifact validation. `xcrun altool` ContentDelivery `26.40.1 (174001)` validated and uploaded this exact package with no errors; Apple delivery `2d7fac89-473a-46a2-818c-c7cd530ef0b0` reached terminal `VALID` / `APP_STORE_ELIGIBLE`, reported no non-exempt encryption, and build `1.0.0 (8)` was attached and saved to the manual-release version. The protected accepted-build assertion is now `8`. This is processing evidence, not App Review or Store publication acceptance.
- [x] Have the Account Holder determine encryption export compliance and add the truthful declaration. On 2026-08-24, Robert confirmed `ITSAppUsesNonExemptEncryption=NO` after review established that the Store channel uses Apple CryptoKit AES-GCM for local Vault storage and contains no Sparkle or third-party cryptographic implementation. Apple documents operating-system-only crypto as not requiring export-compliance documentation. The declaration is present in corrected package SHA-256 `09dcc936...ccb0` and passed independent artifact validation.

## Listing gates

- [ ] Confirm the remaining listing metadata. Robert approved the 29-character App Store product name `Clasp: Private Markdown Notes`; the installed app remains `Clasp`, the publisher is Paper LLC, and `hello@paper.ai` is the public monitored support contact. Subtitle, description, keywords, category, pricing/availability, and copyright still require final review.
- [x] Publish [`docs/index.md`](../../docs/index.md) and [`docs/privacy.md`](../../docs/privacy.md) from `main/docs` through HTTPS-enforced public GitHub Pages. On 2026-08-24, Pages reported build `1172738403` built from merge commit `09033781b131fad5812034132cb50d3214f436d1`, and anonymous requests to `https://robertbmoore.github.io/clasp/` and `https://robertbmoore.github.io/clasp/privacy.html` both returned `200`.
- [x] Enable GitHub private vulnerability reporting and make the Support source and `SECURITY.md` expose that private form plus the confirmed monitored `hello@paper.ai` fallback. GitHub's API reported private vulnerability reporting enabled on 2026-08-24.
- [ ] After Pages deployment, verify the live private form, `hello@paper.ai` intake, and hosted Support page work together before public distribution.
- [ ] Complete Apple's age-rating questionnaire; an unrated app cannot be published.
- [ ] Answer App Privacy from the exact Store binary, including every third-party component. The Store build is designed to contain no Sparkle and Clasp currently claims no collection.
- [ ] Approve or recapture the five synthetic-data candidates in `Screenshots/` against the exact final signed Store build. The candidates are validated non-transparent 2560×1600 JPEGs, but are not signed-build submission evidence.
- [ ] Complete accessibility labels only for behaviors verified in the final Store build.
- [ ] Add review contact, notes, and any sandbox/permission instructions; perform final human/legal/product review.
- [x] Provide `SUBMISSION_HANDOFF.md` to bind the source SHA, workflow run, package checksum, Apple delivery/processing IDs, listing state, and final human approval.

Apple references: [app information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information), [privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/), [age rating](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/), [screenshots](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/), and [upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/).
