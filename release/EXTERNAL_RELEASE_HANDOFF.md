# Clasp external release handoff

Observed: **2026-08-24**
Status: **local product ready; Bundle ID, App Store Connect record, Store identities/profile, public GitHub repository, protected `main`, and protected release environments created; remaining compliance, protected secret custody, signed acceptance, and release publication remain fail-closed**

This guide starts where the verified local build and repository release scaffolding stop. It does not authorize accepting agreements, choosing legal/compliance answers, generating credentials, publishing source, uploading binaries, or submitting for review without Robert at the relevant gate.

## Live Apple state

- **App Store Connect → Apps** contains the confirmed macOS record `Clasp: Private Markdown Notes`, Apple app ID `6804786714`, version `1.0`, in `Prepare for Submission`. Apple rejected the globally occupied bare product name `Clasp`; Robert approved the distinct Store name while the installed app remains `Clasp`. The permanent SKU was verified in the authenticated account and is intentionally withheld from this public repository.
- **Apple Developer → Identifiers** lists `Clasp` / `com.robertmoore.personalnotepad` under Paper LLC team `R3Z7H2TRCB`; this identifier was registered on 2026-08-24 with no optional capability selected. Apple's default In-App Purchase capability remains present.
- **Apple Developer → Certificates** now lists valid Mac App Distribution and Mac Installer Distribution certificates for Paper LLC through 2027-08-24, in addition to the pre-existing Developer ID and development rows. Their independently generated private keys are present in the login Keychain and match the imported public certificates. The login Keychain also proves private-key custody for both pre-existing Developer ID Application identities (SHA-256 `1E6A022B16AC3CCDCCB816383FCF03C0DF6784437337E4EB491B9436136E6F78`, expiring 2031-07-20, and `322807574BAAB0C6030832DD5BA786F6F7FA6A84090D14523DFE3706C9D81E10`, expiring 2031-08-10). No pre-existing certificate was revoked or replaced; direct-release selection/export remains pending.
- **Apple Developer → Profiles** now lists `Clasp Mac App Store 2026`, an App Store profile for `R3Z7H2TRCB.com.robertmoore.personalnotepad` through 2027-08-24. Local validation bound its team, identifier prefix, bundle ID, entitlements, platform, expiry, and embedded application certificate to the exact Keychain identity.
- **App Store Connect → Business** shows the Free Apps Agreement active. EU trader compliance is incomplete. The Paid Apps Agreement is new and unsigned; do not accept it unless the product will offer paid apps or in-app purchases and Robert approves the legal action.
- **GitHub** has the approved public repository `https://github.com/RobertBMoore/clasp` with no license file. The local checkout uses it as `origin`. Pull request `https://github.com/RobertBMoore/clasp/pull/4` passed required CI run `https://github.com/RobertBMoore/clasp/actions/runs/32774974087` from reviewed commit `70d1288a405a68ef193074785e41ce262d7b2a78` in 4m 54s and was squash-merged as public commit `09033781b131fad5812034132cb50d3214f436d1`. Untracked `artifacts/` data was not staged or published.
- **GitHub branch protection** applies to `main`: pull requests are required, approvals are deliberately not required for the solo maintainer, branches must be current, `test-and-package-local` from GitHub Actions must pass, conversations must be resolved, and linear history is required. Force pushes and deletions remain disabled.
- **GitHub release environments** `release` and `app-store-release` require reviewer `RobertBMoore`, disallow administrator bypass, allow self-review for the solo maintainer, and accept deployments only from protected branches. The direct environment has the public `CLASP_UPDATE_FEED_URL` and exact Developer ID identity label; the Store environment has the non-secret protection acknowledgement, team/application-prefix assertions, initial accepted-build assertion, exact application/installer identity labels, and the live `CLASP_PRIVACY_POLICY_URL`. The exact Clasp provisioning profile is present as a protected Store secret. P12/password secrets remain unset because macOS correctly stopped the exact-item exporter at the private-key authentication boundary; the direct public key and direct notarization/Sparkle credentials also remain unset.
- **Public support/security** now has Robert's approved Paper LLC publisher identity and monitored `hello@paper.ai` contact. GitHub Issues and private vulnerability reporting are enabled. HTTPS-enforced public GitHub Pages build `1172738403` published the canonical Support and Privacy sources from merge commit `09033781b131fad5812034132cb50d3214f436d1`; anonymous HTTPS requests to both canonical URLs returned `200` on 2026-08-24. Live email-intake and end-to-end private-report submission testing remain pending.

The unauthenticated Sparkle feed requires this public repository. Do not generate Apple/Sparkle keys, accept legal agreements, choose trader/export-compliance answers, or submit the app for review without action-time confirmation.

## Required order of operations

1. **Preserve the existing App Store Connect record** for Apple app ID `6804786714` and the exact registered Bundle ID. Revalidate its version/build state immediately before packaging or upload; keep the permanent SKU in authenticated account custody rather than public source.
2. **Preserve and operationalize the required Apple identities and profile** after their approved 2026-08-24 creation:
   - For direct distribution, select one of the two locally usable Developer ID Application identities and bind its exact fingerprint to the protected export and release record. Do not revoke or replace either identity implicitly.
   - Preserve the Mac App Distribution and Mac Installer Distribution private keys outside source control; do not revoke or replace them implicitly.
   - Preserve the exact Clasp App Store profile outside source control and rotate it deliberately before expiry.
   - Export protected CI copies and add GitHub secrets only through an approved credential-custody step; never expose their bytes or passwords in logs or source.
3. **Resolve Account Holder gates**: EU trader status, tax/banking if applicable, encryption export compliance for CryptoKit AES-GCM Vault data, age rating, content rights, and App Privacy. The Free Apps Agreement is already active.
4. **Preserve the published HTTPS pages** for Support and Privacy Policy from `main/docs`. Anonymous reachability is proven; test the monitored email/private-report intake routes before entering the URLs in App Store Connect.
5. **Maintain the protected GitHub boundary** already configured at `https://github.com/RobertBMoore/clasp`: every follow-up must use a pull request, pass `test-and-package-local`, remain current with `main`, resolve conversations, and preserve linear history. Never publish untracked `artifacts/` data or credentials. The repository intentionally has no license until Robert chooses one.
6. **Complete the two protected GitHub environments** from `release/README.md`. Required reviewers, protected-branch-only deployment, the public direct feed URL, live Store Privacy URL, known Store account assertions, exact identity labels, and Store profile secret are configured. Add the remaining P12/password, public-key, notarization, and Sparkle values only from exact approved custody; never paste private keys or credential bytes into source, issues, logs, screenshots, or this handoff.
7. **Produce the signed Store package** with the manual `Mac App Store package` workflow and complete `AppStore/SUBMISSION_HANDOFF.md` from its exact run and checksum.
8. **Upload the finished package** using Xcode, Transporter, or Apple’s supported command-line uploader. Chrome is for the app record, metadata, compliance, processed-build selection, and review submission—not binary transport.
9. **Run signed-sandbox acceptance** on a disposable environment with synthetic data, then complete `AppStore/MIGRATION_ACCEPTANCE.md`.
10. **Compare the screenshot candidates** in `AppStore/Screenshots/` with the exact signed Store build, recapture any drift, validate them, and have Robert approve their ordering and copy.
11. **Submit only after every readiness and custody field is complete** and Robert gives final human approval at the review action.

## Direct-update publication order

1. Preserve the configured `main` protection and `release` environment gates in the approved public GitHub repository.
2. Select one of the two locally usable Developer ID certificates; record its exact fingerprint and custodian before creating the protected export or adding secrets. Do not create, revoke, or replace a certificate implicitly.
3. Generate a separate Sparkle EdDSA keypair; never reuse an Apple certificate key.
4. Publish a real signed/notarized baseline N release and complete its acceptance.
5. Build N+1 through `Direct release draft`, review the notarized draft and appcast, then publish manually.
6. Require the post-publication acceptance workflow to pass and complete `DIRECT_UPDATE_ACCEPTANCE.md` on a clean Mac before directing users to the release.

Until the remaining Apple, GitHub, compliance, signed-package, and acceptance gates above are complete, `/Applications/Clasp.app` remains the correct local installation, but it is not a distributable or App Store-submittable artifact.
