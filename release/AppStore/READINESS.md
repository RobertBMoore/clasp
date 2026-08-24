# Mac App Store readiness (not submitted)

Status: **not ready to upload or submit**. This is a custody checklist, not Apple acceptance evidence.

## Build and account gates

- [ ] Robert confirms active Apple Developer Program membership and accepts current agreements.
- [ ] Register the explicit App ID / Bundle ID `com.robertmoore.personalnotepad` in the correct Apple Developer team; do not select an unrelated existing identifier.
- [ ] Create the App Store Connect macOS app record using that exact registered Bundle ID; record the real Team ID, Apple app ID, and SKU privately.
- [ ] Install valid Mac App Distribution and Mac Installer Distribution identities and an App Store provisioning profile.
- [x] Enforce the deliberate Apple-silicon `arm64` architecture policy in local, direct, Store, CI, and artifact validation paths. Intel support is outside 1.0 until a universal build receives real Intel acceptance testing.
- [x] Compile and test the production Store boundary from a clean scratch path: 118/118 Store tests and 124/124 full local tests pass with zero failures; the Store binary is `arm64`, Sparkle is absent, Accessibility/CGEvent capture symbols are absent, and SwiftPM reports no external Store dependencies.
- [ ] Sign the final Store app with `release/Clasp.app-store.entitlements` and prove `com.apple.security.app-sandbox=true` on the distribution artifact.
- [ ] Validate that the Vault Keychain item, local Markdown/Vault paths, Services-based selected-content capture, clipboard capture, global hotkeys, import/export panels, onboarding, and relaunch all work inside App Sandbox. The Store build intentionally excludes direct-channel Accessibility capture.
- [x] Embed a byte-locked Apple container-migration manifest for the complete legacy Application Support folder and validate its exact source/destination paths in the artifact gate.
- [x] Make Store packaging require a non-reserved public HTTPS privacy-policy host, require anonymous reachability in the protected workflow, embed that exact value into the signed app, and expose valid HTTPS URLs from Help.
- [ ] Publish and review the final policy, then prove the exact embedded URL matches the App Store listing. The source validator and workflow reachability gate do not certify the page's legal/content accuracy.
- [x] Add a fail-closed finished-installer validator that expands the package, verifies its code signature and exact `/Applications` non-relocatable/script-free `PackageInfo` policy, and compares path/type/mode/symlink/hash/xattr manifests with the validated staged app. Synthetic package fixtures pass; the first real signed package remains an external gate below.
- [ ] Complete [`MIGRATION_ACCEPTANCE.md`](MIGRATION_ACCEPTANCE.md) on a disposable macOS user/VM with synthetic data before any controlled copy of real data. Do not ship until one-way path migration, note counts/checksums, Vault Keychain custody, Trash recovery, export, and fallback recovery are proven without making real notes the first test.
- [ ] Produce a signed installer package, run Apple's current validation, upload to TestFlight/App Store Connect, and review all processing warnings. None of those actions has been performed here.
- [ ] Have the Account Holder determine encryption export compliance; Clasp uses CryptoKit AES-GCM for user Vault data. Then add the truthful `ITSAppUsesNonExemptEncryption` declaration and any required documentation to the exact final build. The answer must not be guessed.

## Listing gates

- [ ] Confirm final name (`Clasp`, max 30 characters), subtitle, description, keywords, category, pricing/availability, copyright, and support contact.
- [ ] Publish real HTTPS Support and Privacy Policy URLs; placeholders are not acceptable.
- [ ] Make the hosted Support route expose a monitored public security-reporting contact, verify that it receives reports, and reflect the exact route in `SECURITY.md` before public distribution.
- [ ] Complete Apple's age-rating questionnaire; an unrated app cannot be published.
- [ ] Answer App Privacy from the exact Store binary, including every third-party component. The Store build is designed to contain no Sparkle and Clasp currently claims no collection.
- [ ] Capture 1–10 final Mac screenshots, all one accepted 16:10 size: 1280×800, 1440×900, 2560×1600, or 2880×1800, without transparency.
- [ ] Complete accessibility labels only for behaviors verified in the final Store build.
- [ ] Add review contact, notes, and any sandbox/permission instructions; perform final human/legal/product review.
- [x] Provide `SUBMISSION_HANDOFF.md` to bind the source SHA, workflow run, package checksum, Apple delivery/processing IDs, listing state, and final human approval.

Apple references: [app information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information), [privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/), [age rating](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/), [screenshots](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/), and [upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/).
