# Clasp release channels

Clasp has two deliberately separate distribution channels:

- **Direct / GitHub:** an exact-pinned Sparkle 2.9.6 build, Developer ID Application signing, hardened runtime, Apple notarization, a stapled ticket, an EdDSA-signed update archive/appcast, and a draft GitHub release. `Check for Updates…` exists only in this build.
- **Mac App Store:** a sandboxed, Sparkle-free build. Installation and every update are delivered by the App Store.

The normal `./script/build_and_run.sh` path remains offline, ad-hoc signed, and Sparkle-free. It is development evidence, not a distributable release.

Version 1.0 has an explicit Apple-silicon `arm64` release policy. Every channel builds and validates that architecture on an arm64 GitHub runner; Clasp does not silently change architecture with the build host. Intel support can be added only with a universal build and a real Intel acceptance pass.

SwiftPM dependency resolution is channel-isolated. The root has no `Package.resolved`, so local and App Store builds do not resolve or fetch Sparkle. A direct build temporarily installs the reviewed `release/Package.direct.resolved`, forces those exact resolved versions, and removes the temporary root lockfile on exit.

The direct bundle includes `Contents/Resources/Sparkle-LICENSE.txt`, copied byte-for-byte from the exact pinned Sparkle distribution and checksum-validated during staging and release acceptance. The Store and local channels remain Sparkle-free and omit that channel-specific notice.

## Direct release gate

Run the `Direct release draft` workflow manually after creating and pushing the exact `v<version>` tag. Configure a protected GitHub `release` environment with a required reviewer.

Protected `release` environment variables used by the draft workflow:

- `CLASP_UPDATE_FEED_URL`: `https://github.com/OWNER/REPOSITORY/releases/latest/download/appcast.xml`
- `CLASP_SPARKLE_PUBLIC_KEY`: public EdDSA key printed by Sparkle `generate_keys`
- `DEVELOPER_ID_APPLICATION_IDENTITY`: exact Keychain identity label
- `DEVELOPER_ID_APPLICATION_CERTIFICATE_SHA256`: exact 64-character SHA-256 fingerprint of the selected Developer ID Application certificate

The published-release event runs from a tag ref, while the protected `release` environment permits only protected branches. Therefore the same four non-secret values must also exist as repository Actions variables for `Published direct release acceptance`, using these deliberately distinct names:

- `CLASP_PUBLISHED_UPDATE_FEED_URL`
- `CLASP_PUBLISHED_SPARKLE_PUBLIC_KEY`
- `CLASP_PUBLISHED_DEVELOPER_ID_APPLICATION_IDENTITY`
- `CLASP_PUBLISHED_DEVELOPER_ID_APPLICATION_CERTIFICATE_SHA256`

Each repository value must exactly match its protected-environment counterpart. The distinct names prevent GitHub's repository-variable precedence from shadowing protected environment values during the draft job. Keep all private P12, notarization, and Sparkle signing credentials only in the protected environment; do not duplicate secrets as repository variables.

Environment secrets:

- `DEVELOPER_ID_APPLICATION_P12_BASE64`
- `DEVELOPER_ID_APPLICATION_P12_PASSWORD`
- `APP_STORE_CONNECT_API_KEY_P8_BASE64`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `SPARKLE_PRIVATE_ED_KEY`

The workflow fails closed when any input is absent, the repository is not public, the selected Developer ID identity and certificate fingerprint are not an exact match, or the build number is not greater than the latest published appcast build. Packaging resolves the pinned certificate to its SHA-1 Keychain identity selector, so multiple valid certificates may share the same display label without making `codesign` selection ambiguous; a missing or duplicate pinned certificate, or a pinned certificate without exactly one matching private-key identity, is rejected. The workflow creates a **draft**, never a published release. Review the notarization result, signature, checksum, appcast URLs/signature, and release notes before manually publishing.

GitHub does not expose draft assets through the public `releases/latest/download` feed, so an exact production-feed update test is impossible while the candidate remains a draft. Immediately after a human publishes the release, the `Published direct release acceptance` workflow runs the verifier from the immutable workflow commit on the protected default branch—not from the release tag—binds the release tag to protected default-branch history, and compares anonymous downloads of the public `latest` appcast, release archive, and checksum byte-for-byte with the tagged assets. In archive-only mode, the verifier checks release names, checksum, appcast, and signatures before extracting the public archive into a private temporary directory, then validates the extracted app's Developer ID signature, notarization ticket, Gatekeeper result, bundle metadata, and Sparkle boundary. The acceptance receipt records both the release source SHA and trusted verifier SHA. This is post-publication detection and rollback evidence, not a pre-publication gate: an existing Sparkle client could poll during the acceptance window. Do not announce or intentionally distribute the release until that workflow passes and a clean Mac completes [`DIRECT_UPDATE_ACCEPTANCE.md`](DIRECT_UPDATE_ACCEPTANCE.md) for the real N→N+1 in-app update. If either check fails, immediately unpublish the release and investigate.

The GitHub/Sparkle source pipeline is **pipeline-ready, not end-to-end update certified**. Certification requires real Developer ID credentials, a notarized published N and N+1, the public-release acceptance receipt, and a completed clean-Mac record. Source tests, a draft release, or offline signature verification cannot substitute for that evidence.

The direct feed intentionally requires a **public** GitHub repository. A private repository cannot serve unauthenticated Sparkle clients and is rejected by both direct workflows.

Never reuse the Developer ID certificate as the Sparkle signing key. Keep both private keys outside the repository. Sparkle documents passing the private key through standard input; the workflow never writes it to disk.

### Offline artifact acceptance

Before creating the draft, the workflow runs `script/verify_direct_release.sh` against the finished `release-output` directory. The verifier does not publish, make a network request, or accept a Developer ID or Sparkle private key. It requires only the expected Developer ID identity label and certificate SHA-256 fingerprint, feed URL, and Sparkle **public** key.

For an equivalent local check:

```bash
CLASP_DEVELOPER_ID_APPLICATION='Developer ID Application: Example Name (TEAMID1234)' \
CLASP_DEVELOPER_ID_APPLICATION_CERTIFICATE_SHA256='0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF' \
CLASP_UPDATE_FEED_URL='https://github.com/OWNER/REPOSITORY/releases/latest/download/appcast.xml' \
CLASP_SPARKLE_PUBLIC_KEY='BASE64_PUBLIC_KEY' \
./script/verify_direct_release.sh \
  release-output 1.0.0 8 \
  'https://github.com/OWNER/REPOSITORY/releases/download/v1.0.0/' \
  --require-notarization
```

The gate rejects inexact archive/checksum names, stale parallel archives, checksum or archive-content mismatches, unsafe archive paths, unexpected bundle/feed/key metadata, missing hardened runtime or nested Developer ID signatures, any signing leaf certificate that differs from the exact SHA-256 pin, any App Sandbox entitlement, and malformed or inconsistent appcast data. Sparkle is signed inside-out in its documented component order, with Downloader entitlements preserved and compared before/after signing; forced deep signing is never used. The gate compiles a dependency-free CryptoKit helper and cryptographically verifies both the update archive and signed feed against the configured Ed25519 public key, so signature-shaped text is never treated as proof. `--require-notarization` additionally requires a valid stapled ticket and Gatekeeper acceptance as `Notarized Developer ID`. The offline draft gate requires both the staged app and the byte-identical app extracted from its archive to pass. Public acceptance uses `--archive-only`, refuses a caller-supplied staged app, validates only the app extracted from the downloaded public archive with the trusted default-branch verifier, and records the expected Developer ID certificate fingerprint in its receipt.

Run the deterministic no-key fixture checks with:

```bash
./script/verify_direct_release.sh --self-test
```

## Local installation

`./script/build_and_run.sh --install` builds and validates the ordinary local app, then installs it at `/Applications/Clasp.app`. This is still ad-hoc signed and is only for this Mac. A public download must be Developer ID signed and notarized.

## Mac App Store package gate

The manual `Mac App Store package` workflow runs only from the protected default branch and a protected `app-store-release` environment. Configure that environment with required reviewers and these variables:

- `CLASP_APP_STORE_ENVIRONMENT_PROTECTED`: the literal `required-reviewers-configured` acknowledgement used by the workflow preflight.
- `CLASP_APP_STORE_TEAM_ID`: the 10-character Apple Developer Team ID.
- `CLASP_APP_STORE_APP_ID_PREFIX`: the 10-character application-identifier prefix from the exact provisioning profile.
- `CLASP_APP_STORE_APPLICATION_IDENTITY`: the exact Mac App Store application-signing identity label available in the imported P12.
- `CLASP_APP_STORE_INSTALLER_IDENTITY`: the exact Mac App Store installer-signing identity label available in the imported P12.
- `CLASP_APP_STORE_APPLICATION_CERTIFICATE_SHA256`: the exact 64-character SHA-256 fingerprint for the application certificate in the profile and signed app.
- `CLASP_APP_STORE_INSTALLER_CERTIFICATE_SHA256`: the exact 64-character SHA-256 fingerprint for the installer certificate embedded in the package signature.
- `CLASP_PRIVACY_POLICY_URL`: the final public HTTPS policy URL embedded into the signed app and exposed in Help. The protected workflow rejects reserved/local hosts and requires an anonymous successful HTTPS response before packaging.
- `CLASP_APP_STORE_LAST_ACCEPTED_BUILD_NUMBER`: `0` before the first accepted build, then the highest build processed by App Store Connect. The requested build must be greater. This is an operator-maintained assertion, not a live App Store Connect query; reconcile it with the processed-build record and submission handoff before every run.

Environment secrets:

- `CLASP_APP_STORE_APPLICATION_P12_BASE64`
- `CLASP_APP_STORE_APPLICATION_P12_PASSWORD`
- `CLASP_APP_STORE_INSTALLER_P12_BASE64`
- `CLASP_APP_STORE_INSTALLER_P12_PASSWORD`
- `CLASP_APP_STORE_PROVISIONING_PROFILE_BASE64`

The profile must be an unexpired App Store distribution profile for `com.robertmoore.personalnotepad`, the configured Team ID and application-identifier prefix, and the exact application certificate imported from the P12. The workflow rejects device-bound profiles, mismatched identities, debugger entitlement, or unreviewed source entitlements.

The workflow validates the staged app, byte-locks the privacy and migration manifests, signs the app and installer with the exact requested identities, expands the finished package, validates the exact `/Applications` non-relocatable and script-free `PackageInfo` policy, and compares every app path, filesystem type, permission mode, symlink target, regular-file SHA-256, and extended attribute with the validated staged app. It uploads only the package and checksum for human review and deliberately never uploads to Apple or submits for review.

After packaging, complete [`AppStore/SUBMISSION_HANDOFF.md`](AppStore/SUBMISSION_HANDOFF.md) from the exact workflow run, checksum, Apple delivery, processing result, listing, and final approval. Binary upload uses Xcode, Transporter, or Apple’s supported command-line upload path; Chrome is used for the App Store Connect record, metadata, compliance, processing, and review handoff.

## Apple prerequisites

The live account and publication sequence is captured in [`EXTERNAL_RELEASE_HANDOFF.md`](EXTERNAL_RELEASE_HANDOFF.md). It records the prepared Chrome gates and the decisions that must remain with Robert.

Direct distribution needs Apple Developer Program membership, a Developer ID Application certificate, and notarization credentials. Mac App Store distribution separately needs an App Store Connect app record, registered bundle ID, Mac App Distribution and Mac Installer Distribution certificates, a provisioning profile, App Sandbox acceptance testing, export-compliance answers, agreements, tax/banking as applicable, metadata, privacy policy URL, age rating, screenshots, and final human review.

Primary references: [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [Apple certificates](https://developer.apple.com/help/account/create-certificates/certificates-overview), [App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox), [Sparkle setup](https://sparkle-project.org/documentation/), [Sparkle publishing](https://sparkle-project.org/documentation/publishing/), and [GitHub deployment environments](https://docs.github.com/en/actions/concepts/workflows-and-actions/deployment-environments).

The bundled privacy manifest declares `NSPrivacyAccessedAPICategoryUserDefaults` with Apple's app-only `CA92.1` reason because Clasp uses `UserDefaults`/`@AppStorage` only for its own preferences. It also declares `NSPrivacyAccessedAPICategoryFileTimestamp` with `DDA9.1` because Clasp reads creation/modification times from its own Markdown note files when rebuilding recoverable metadata. See [Apple TN3183](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest).
