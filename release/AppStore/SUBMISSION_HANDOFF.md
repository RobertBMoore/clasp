# App Store submission handoff

Complete this record from the exact successful package workflow and App Store Connect delivery. Blanks are not evidence; never upload a package whose checksum differs.

## Source and package

- Source commit SHA: `ab09cdaceac9d2c4dbf9e762e531daf6db40e4b8`
- Protected branch: `main`
- GitHub package workflow run URL: `https://github.com/RobertBMoore/clasp/actions/runs/32790427285`; both protected preflight and signed-package jobs passed against the exact source commit above. GitHub recorded archive digest `sha256:5795d154c7675bf5f22fa490632b88641ad8e3a1307bc375ba1d31411dd2381e`. This is the current upload candidate, but it has not been delivered to or accepted by Apple. Later merge `f62c246153469e2d4fcd97d13a342db8a81aaad8` changes only direct-release verification and does not alter this Store artifact.
- Registered explicit Bundle ID / Apple identifier record: `Clasp` / `com.robertmoore.personalnotepad`, Paper LLC team `R3Z7H2TRCB`, verified live 2026-08-24
- Expected Apple Developer Team ID from the account record (not artifact evidence): `R3Z7H2TRCB`
- App Store Connect app record: `Clasp: Private Markdown Notes`, macOS `1.0.0`, Apple app ID `6804786714`, `Prepare for Submission`, verified live 2026-08-24. Sign-in is not required and release is manual. The permanent SKU was verified in the authenticated account and is intentionally withheld from this public repository.
- Version (`CFBundleShortVersionString`): `1.0.0`; the authenticated App Store Connect record and protected review artifact are aligned.
- Build (`CFBundleVersion`): `8`
- Last accepted build-number assertion, App Store Connect source, and checked date/time: protected environment assertion `0`; the authenticated macOS `1.0.0` version page showed no uploaded or selectable build after final package generation on 2026-08-24. Revalidate immediately before upload because this live account state can change.
- Package filename: `Clasp-1.0.0-8-AppStore.pkg` (protected review-only workflow artifact; not uploaded)
- Package SHA-256: `09dcc9361d7a95c5cb699507b7a5d381c3d925b88130c346aae2e3fe6d80ccb0`
- Package-payload parity result: exact path/type/mode/symlink/hash/xattr parity and script-free, non-relocatable `/Applications` PackageInfo policy passed on GitHub's `macos-26` runner and again against the downloaded artifact on 2026-08-24. The corrected payload makes the embedded provisioning profile mode `0644`; the independent permission gate found no app-payload file without other-read and no directory without other-execute. The independent check also revalidated the exact application/installer certificate pins, provisioning profile, App Sandbox entitlements, migration manifest, Privacy manifest, absence of Sparkle and Accessibility selection capture, and `ITSAppUsesNonExemptEncryption=false`. The workflow removed its imported release credentials in the always-run cleanup step.
- Privacy policy URL embedded in the signed app: `https://robertbmoore.github.io/clasp/privacy.html`
- Signing Team ID observed from the exact packaged artifact: `R3Z7H2TRCB`
- Mac App Distribution identity and SHA-256 fingerprint: `3rd Party Mac Developer Application: Paper LLC (R3Z7H2TRCB)` / `C7:1E:DE:4E:76:1A:DB:6E:3B:1F:8C:B3:EB:2C:81:7D:0D:EC:3E:3C:03:18:EE:C5:EC:84:68:60:4B:B0:AB:D7`, verified locally 2026-08-24
- Mac Installer Distribution identity and SHA-256 fingerprint: `3rd Party Mac Developer Installer: Paper LLC (R3Z7H2TRCB)` / `D7:33:19:AA:7B:85:94:62:C3:B2:6E:6B:13:15:F8:D2:46:F6:FD:15:72:74:EC:CB:F8:C7:3A:02:93:F0:3D:9E`, verified locally 2026-08-24
- Provisioning profile UUID and expiry: `25535586-40DF-4EE1-AA8F-D57F2CFBD210` / 2027-08-24 18:42:28 UTC; `Clasp Mac App Store 2026`, exact certificate/bundle/team validation passed locally 2026-08-24

## Upload and processing

- Upload tool and version (Transporter, Xcode, or `altool`): corrected package not run. `xcrun altool --validate-app` rejected the superseded SHA-256 `6b9944b5...a8854c` with `ITMS-90255` because its embedded provisioning profile was mode `0600`; no upload occurred. PR #10 and protected run `32790427285` corrected and regression-tested that permission defect.
- Upload date/time and operator:
- Delivery/upload ID:
- App Store Connect app ID: `6804786714`
- Bundle ID: `com.robertmoore.personalnotepad`
- App version record: macOS `1.0.0`, `Prepare for Submission`; build 8 has not been uploaded or selected
- Build processing result and date/time:
- Apple validation tool/version and result before upload: corrected SHA-256 `09dcc936...ccb0` awaits exact upload authorization and live Apple validation
- Export-compliance result: Account Holder confirmed exempt operating-system encryption; `ITSAppUsesNonExemptEncryption=false` is present in the exact package and passed independent artifact validation. App Store Connect has not processed the package yet.
- Signed-sandbox acceptance evidence:
- Synthetic migration and Vault Keychain-custody record:
- App Review submission ID, submitted date/time, and current status:

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
- Agreement/trader/tax gates cleared by Account Holder:
- Final human approval and date/time:

Binary upload must use Xcode, Transporter, or Apple’s supported command-line upload path. Chrome is the handoff for the app record, metadata, compliance, processing, and review status; it is not the binary uploader.
