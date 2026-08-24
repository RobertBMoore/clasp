# Clasp external release handoff

Observed: **2026-08-24**
Status: **local product ready; Bundle ID, public GitHub repository, protected `main`, and protected release environments created; remaining external identities, app record, compliance, and release publication remain fail-closed**

This guide starts where the verified local build and repository release scaffolding stop. It does not authorize accepting agreements, choosing legal/compliance answers, generating credentials, publishing source, uploading binaries, or submitting for review without Robert at the relevant gate.

## Live Apple state

- **App Store Connect → Apps** is authenticated as Robert Moore for Paper LLC and still shows **No Apps**. The exact New App form is prepared for Clasp, but the create action is waiting for action-time confirmation because the company name will be public and the app record is persistent.
- **Apple Developer → Identifiers** lists `Clasp` / `com.robertmoore.personalnotepad` under Paper LLC team `R3Z7H2TRCB`; this identifier was registered on 2026-08-24 with no optional capability selected. Apple's default In-App Purchase capability remains present.
- **Apple Developer → Certificates** lists two valid Developer ID Application certificates for direct distribution and one development certificate. It does not list an Apple Distribution / Mac App Distribution or Mac Installer Distribution certificate. The local keychain has zero valid code-signing identities, so the server-side certificate rows do not prove private-key custody.
- **Apple Developer → Profiles** lists only DRG Agent Relay / Bridge profiles; no Clasp App Store profile exists.
- **App Store Connect → Business** shows the Free Apps Agreement active. EU trader compliance is incomplete. The Paid Apps Agreement is new and unsigned; do not accept it unless the product will offer paid apps or in-app purchases and Robert approves the legal action.
- **GitHub** has the approved public repository `https://github.com/RobertBMoore/clasp` with no license file. The local checkout uses it as `origin`, and commit `71c7ae55ef50e8908ce72bdb57ac2ebb862b08f0` is public with no untracked `artifacts/` data. Public CI run `https://github.com/RobertBMoore/clasp/actions/runs/32755060746` passed the local, App Store, direct-download, and release-contract boundaries in 5m 11s.
- **GitHub branch protection** applies to `main`: pull requests are required, approvals are deliberately not required for the solo maintainer, branches must be current, `test-and-package-local` from GitHub Actions must pass, conversations must be resolved, and linear history is required. Force pushes and deletions remain disabled.
- **GitHub release environments** `release` and `app-store-release` require reviewer `RobertBMoore`, disallow administrator bypass, allow self-review for the solo maintainer, and accept deployments only from protected branches. The direct environment has the public `CLASP_UPDATE_FEED_URL`; the Store environment has the non-secret protection acknowledgement, team/application-prefix assertions, and initial accepted-build assertion. Credential-backed identities, public keys, privacy URL, and secrets remain intentionally unset.

The unauthenticated Sparkle feed requires this public repository. Do not generate Apple/Sparkle keys, accept legal agreements, choose trader/export-compliance answers, or submit the app for review without action-time confirmation.

## Required order of operations

1. **Create the App Store Connect macOS app record** from the already-registered exact Bundle ID after Robert confirms the public company name and persistent record fields. Record the Apple app ID and SKU privately.
2. **Establish the required Apple identities and profile** after action-time approval for credential generation or import:
   - For direct distribution, first recover/import the private key for one exact existing Developer ID Application certificate and bind the selected fingerprint to its custodian. If neither existing private key can be recovered, obtain explicit approval before attempting a new certificate; do not revoke or replace either existing identity implicitly.
   - Apple Distribution / Mac App Distribution for the Store application.
   - Mac Installer Distribution for the Store package.
   - App Store provisioning profile for the exact Bundle ID and team.
3. **Resolve Account Holder gates**: EU trader status, tax/banking if applicable, encryption export compliance for CryptoKit AES-GCM Vault data, age rating, content rights, and App Privacy. The Free Apps Agreement is already active.
4. **Approve and publish real HTTPS pages** for Support, Privacy Policy, and monitored security contact. Replace every `TBD` and prove anonymous HTTPS reachability.
5. **Maintain the protected GitHub boundary** already configured at `https://github.com/RobertBMoore/clasp`: every follow-up must use a pull request, pass `test-and-package-local`, remain current with `main`, resolve conversations, and preserve linear history. Never publish untracked `artifacts/` data or credentials. The repository intentionally has no license until Robert chooses one.
6. **Complete the two protected GitHub environments** from `release/README.md` after the external credentials and URLs exist. Required reviewers, protected-branch-only deployment, the public direct feed URL, and the known Store account assertions are configured. Add the remaining identity/public-key/privacy variables and secrets only from exact approved custody; never paste private keys or P12 contents into source, issues, logs, screenshots, or this handoff.
7. **Produce the signed Store package** with the manual `Mac App Store package` workflow and complete `AppStore/SUBMISSION_HANDOFF.md` from its exact run and checksum.
8. **Upload the finished package** using Xcode, Transporter, or Apple’s supported command-line uploader. Chrome is for the app record, metadata, compliance, processed-build selection, and review submission—not binary transport.
9. **Run signed-sandbox acceptance** on a disposable environment with synthetic data, then complete `AppStore/MIGRATION_ACCEPTANCE.md`.
10. **Compare the screenshot candidates** in `AppStore/Screenshots/` with the exact signed Store build, recapture any drift, validate them, and have Robert approve their ordering and copy.
11. **Submit only after every readiness and custody field is complete** and Robert gives final human approval at the review action.

## Direct-update publication order

1. Preserve the configured `main` protection and `release` environment gates in the approved public GitHub repository.
2. Recover/import the private key for one exact existing Developer ID certificate, or explicitly authorize a new identity if Apple permits it; record the selected fingerprint and custodian before adding protected secrets.
3. Generate a separate Sparkle EdDSA keypair; never reuse an Apple certificate key.
4. Publish a real signed/notarized baseline N release and complete its acceptance.
5. Build N+1 through `Direct release draft`, review the notarized draft and appcast, then publish manually.
6. Require the post-publication acceptance workflow to pass and complete `DIRECT_UPDATE_ACCEPTANCE.md` on a clean Mac before directing users to the release.

Until the Apple and GitHub authority gates above are complete, `/Applications/Clasp.app` remains the correct local installation, but it is not a distributable or App Store-submittable artifact.
