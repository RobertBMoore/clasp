# Clasp external release handoff

Observed: **2026-08-24**
Status: **local product ready; external identities, records, and publication remain fail-closed**

This guide starts where the verified local build and repository release scaffolding stop. It does not authorize accepting agreements, choosing legal/compliance answers, generating credentials, publishing source, uploading binaries, or submitting for review without Robert at the relevant gate.

## Chrome is staged at the live gates

- **App Store Connect → Apps** is authenticated and currently shows **No Apps**. Apple also displays the EU trader-status requirement.
- **Apple Developer → Identifiers** is open at the Apple sign-in screen for the exact Bundle ID registration step.
- **Apple Developer → Certificates** is open at the Apple sign-in screen for the distribution-identity step.
- **GitHub → New repository** is authenticated as Robert’s GitHub account. The form currently defaults to a public repository, but no repository name, description, license, visibility choice, or create action has been entered.

The Apple Developer session must be completed by Robert. Do not use App Store Connect’s **New App** action until `com.robertmoore.personalnotepad` exists in the intended Apple Developer team. Do not click GitHub’s **Create repository** action until Robert explicitly approves making this source public, chooses the repository name, and chooses a license policy. The unauthenticated Sparkle feed requires a public repository.

## Required order of operations

1. **Authenticate Apple Developer** in the two prepared Chrome tabs.
2. **Verify the intended team and authority** before creating anything. Record the Team ID privately.
3. **Register the explicit Bundle ID** `com.robertmoore.personalnotepad`. Do not select or repurpose an unrelated identifier.
4. **Create the required Apple identities and profile**:
   - Developer ID Application for the direct-download channel.
   - Apple Distribution / Mac App Distribution for the Store application.
   - Mac Installer Distribution for the Store package.
   - App Store provisioning profile for the exact Bundle ID and team.
5. **Return to App Store Connect** and create the macOS app record only after the Bundle ID is selectable. Record the Apple app ID and SKU privately.
6. **Resolve Account Holder gates**: current agreements, EU trader status, tax/banking if applicable, encryption export compliance for CryptoKit AES-GCM Vault data, age rating, content rights, and App Privacy.
7. **Approve and publish real HTTPS pages** for Support, Privacy Policy, and monitored security contact. Replace every `TBD` and prove anonymous HTTPS reachability.
8. **Decide GitHub publication**: public-source approval, repository name, description, and license. Then create the repository, add its exact URL as `origin`, and push protected `main`.
9. **Configure protected GitHub environments** from `release/README.md`, including required reviewers, release variables, and secrets. Never paste private keys or P12 contents into source, issues, logs, screenshots, or this handoff.
10. **Produce the signed Store package** with the manual `Mac App Store package` workflow and complete `AppStore/SUBMISSION_HANDOFF.md` from its exact run and checksum.
11. **Upload the finished package** using Xcode, Transporter, or Apple’s supported command-line uploader. Chrome is for the app record, metadata, compliance, processed-build selection, and review submission—not binary transport.
12. **Run signed-sandbox acceptance** on a disposable environment with synthetic data, then complete `AppStore/MIGRATION_ACCEPTANCE.md`.
13. **Compare the screenshot candidates** in `AppStore/Screenshots/` with the exact signed Store build, recapture any drift, validate them, and have Robert approve their ordering and copy.
14. **Submit only after every readiness and custody field is complete** and Robert gives final human approval at the review action.

## Direct-update publication order

1. Create and protect the approved public GitHub repository and `release` environment.
2. Import the Developer ID and notarization credentials only through protected secrets.
3. Generate a separate Sparkle EdDSA keypair; never reuse an Apple certificate key.
4. Publish a real signed/notarized baseline N release and complete its acceptance.
5. Build N+1 through `Direct release draft`, review the notarized draft and appcast, then publish manually.
6. Require the post-publication acceptance workflow to pass and complete `DIRECT_UPDATE_ACCEPTANCE.md` on a clean Mac before directing users to the release.

Until the Apple and GitHub authority gates above are complete, `/Applications/Clasp.app` remains the correct local installation, but it is not a distributable or App Store-submittable artifact.
