# Direct in-app update acceptance (N→N+1)

Status: **not certified until this record is completed against two real signed, notarized, published direct releases on a clean Mac or clean macOS user/VM**. Pipeline, fixture, local-build, and draft-release results are not substitutes.

Use synthetic notes only. Never put real note bodies, Vault titles, recovery keys, signing keys, tokens, or other secrets in this record. Preserve failed artifacts and receipts; do not delete user data to make a retry pass.

## Release custody

- Public GitHub repository:
- Protected default branch:
- N tag / version / build / source SHA:
- N+1 tag / version / build / source SHA:
- Trusted verifier SHA:
- N+1 draft workflow run URL:
- N+1 published-acceptance workflow run URL:
- Published-acceptance receipt artifact URL:
- Receipt source SHA matches N+1 tag:
- Receipt verifier SHA matches trusted protected-branch workflow:
- Public appcast URL:
- Public appcast SHA-256:
- N+1 public archive URL:
- N+1 archive SHA-256 and checksum-file result:

## Clean client custody

- Operator and date/time:
- Mac model and architecture:
- macOS version/build:
- Clean environment type (separate Mac, fresh macOS user, or disposable VM):
- Evidence that Clasp was not previously installed in this environment:
- N acquisition source and archive checksum:
- Installed bundle path (must be `/Applications/Clasp.app`):

## Baseline N acceptance

- `CFBundleShortVersionString` / `CFBundleVersion`:
- Developer ID Application identity and Team ID:
- `codesign --verify --deep --strict` result:
- `xcrun stapler validate` result:
- `spctl -a -vv -t exec` result (`Notarized Developer ID` required):
- Launch and relaunch result:
- Synthetic regular-note count:
- Synthetic regular Markdown/sidecar/attachment checksums recorded without content:
- Synthetic Vault configured and unlocked with macOS authentication:
- Synthetic active Vault-note count:
- Synthetic Vault Trash-note count:
- Encrypted Vault export SHA-256:
- Recovery key stored separately and **not** copied into this record:

## In-app N→N+1 update

- Public `latest` appcast serves the reviewed N+1 appcast byte-for-byte:
- **Clasp › Check for Updates…** invoked in N:
- Offered version/build:
- Offered archive URL matches the public N+1 release asset:
- Sparkle download/verification/install result:
- Unexpected prompts, warnings, retries, or interruptions (write `none` or explain):
- App quit/relaunch result after installation:

## Post-update N+1 acceptance

- `/Applications/Clasp.app` now reports N+1 version/build:
- Developer ID Application identity and Team ID unchanged/expected:
- `codesign --verify --deep --strict` result:
- `xcrun stapler validate` result:
- `spctl -a -vv -t exec` result (`Notarized Developer ID` required):
- N+1 launches, quits, and relaunches cleanly:
- Regular-note count matches baseline:
- Regular Markdown/sidecar/attachment checksums match baseline:
- Vault unlocks through the existing Keychain item after macOS authentication:
- Active Vault-note count matches baseline:
- Vault Trash-note count matches baseline:
- A synthetic trashed Vault note restores successfully and can be moved back to Trash:
- A new synthetic regular note persists across relaunch:
- A new synthetic Vault note persists encrypted across lock, unlock, and relaunch:
- **Check for Updates…** now reports no newer published release:

## Decision

- Published-acceptance workflow: PASS / FAIL
- Clean-client N→N+1 acceptance: PASS / FAIL
- Any mismatch, warning, or unresolved limitation:
- If failed, N+1 was unpublished before users were directed to it:
- Final human approval and date/time:

PASS requires every custody field and validation above. A failure remains a release blocker; preserve the workflow receipt, public asset hashes, client evidence, and synthetic-data discrepancy for repair and a fresh full rerun.
