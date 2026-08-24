# App Sandbox migration and Vault custody acceptance

Status: **not performed**. This record must be completed with the exact final signed Store build on a disposable macOS user, disposable VM, or separately controlled test Mac. **Real notes and the production Vault must never be the first migration test.**

Use synthetic content only. Take a restorable snapshot of the disposable environment before first launch because Apple's container migration is one-way and may move the legacy folder. Keep the encrypted export and its recovery key separate; never put note bodies, Vault titles, recovery keys, Keychain values, certificates, or other secrets in this record.

## Build and environment custody

- Source commit SHA:
- Protected branch and Store-package workflow run URL:
- Store version / build:
- Package filename and SHA-256:
- App Store Connect/TestFlight build ID and processing result, if used:
- Bundle ID (must be `com.robertmoore.personalnotepad`):
- Signing Team ID and application identity:
- Provisioning profile UUID and expiry:
- Signed App Sandbox entitlement result:
- Embedded container-migration manifest hash/result:
- macOS version/build, Mac model, and architecture:
- Disposable environment type and restorable snapshot ID:
- Operator and date/time:

## Synthetic legacy baseline

- Exact local/direct Clasp version, build, source, and signature:
- Legacy data root (must be `~/Library/Application Support/Personal Notepad/` for the disposable user):
- Regular active / Inbox / archived / pinned / Trash note counts:
- Regular Markdown, sidecar, index, and attachment manifest with SHA-256 values but no content:
- Synthetic image-attachment count:
- Vault active-note count:
- Vault Trash-note count:
- Vault unlock succeeds through macOS authentication:
- Keychain service/account presence recorded without reading the value:
- `vault.pnvault` SHA-256:
- Encrypted Vault export filename and SHA-256:
- Recovery key stored separately and **not** copied into this record:
- Legacy app quit cleanly and all pending edits persisted:
- Restorable disposable-environment snapshot taken after the baseline:

## First signed-sandbox launch

- Exact signed Store app installed without manually moving or deleting the legacy data folder:
- First launch date/time:
- App Sandbox container path shown by Clasp Help:
- Container migration completed without crash, partial UI, or unexpected permission prompt:
- Legacy source-path state after migration recorded (present, moved, or absent; do not normalize it manually):
- Container data-root manifest and SHA-256 values:
- No unrelated files were moved into the container:
- No Accessibility permission was requested:
- Store binary contains no Sparkle UI/framework/update metadata:

## Data, Vault, Trash, and relaunch acceptance

- Regular active / Inbox / archived / pinned / Trash counts match baseline:
- Markdown, sidecar, index, and attachment checksums match baseline:
- Every synthetic attachment opens in its owning note:
- Existing Vault unlocks through the pre-migration Keychain item after macOS authentication:
- Vault active-note count matches baseline:
- Vault Trash-note count matches baseline:
- A synthetic trashed Vault note restores and can be moved back to Trash:
- Lock immediately removes Vault results from Vault, All Notes, search, and Trash:
- Unlock restores the expected active and Trash results:
- New regular and Vault notes persist across quit/relaunch:
- Existing and new Vault notes survive lock, quit, relaunch, and unlock:
- Encrypted Vault export succeeds from the Store build:
- Store-build export authenticates and its SHA-256 is recorded:

## Signed-sandbox workflow acceptance

- Quick Capture primary shortcut and fallback behavior:
- Global Lock Vault shortcut:
- Normal and private selected-content Services from at least one text source:
- Image/link Service behavior or documented clipboard fallback:
- Clipboard capture to Inbox:
- Clipboard capture to Vault with safe clearing enabled:
- Clipboard capture to Vault with **Never** leaves the value in place:
- Newer clipboard content is not cleared by an older scheduled capture:
- Export save panel writes only to the chosen location:
- Import open panel reads only the chosen file and balances sandbox access:
- Onboarding, Help, Settings, menu-bar actions, Dock actions, and main-window relaunch:

## Recovery fallback drill

Run this only from a fresh restore of the disposable baseline snapshot, not by modifying a failed migration in place.

- Reproduced missing/inaccessible legacy Keychain custody without reading or deleting any key:
- Clasp failed closed instead of creating or overwriting an empty Vault:
- Preflight encrypted export authenticated with the separately stored recovery key:
- Import created/unlocked a fresh local Store-accessible Vault key after macOS authentication:
- Imported active and Trash note counts match baseline:
- Imported Vault note/attachment behavior matches baseline:
- Previous encrypted container is preserved as `vault.previous.pnvault`:
- Lock, relaunch, unlock, export, and Trash restore pass after fallback import:

Fallback PASS proves recoverability only. It does **not** prove transparent legacy Keychain custody. If the transparent unlock section fails, shipping remains blocked unless the product implements and verifies an explicit pre-migration export/recovery experience for every affected user.

## Decision

- Transparent path migration: PASS / FAIL
- Transparent Vault Keychain custody: PASS / FAIL
- Recovery fallback: PASS / FAIL
- Signed-sandbox workflow matrix: PASS / FAIL
- Any warning, discrepancy, or unresolved limitation:
- Final release decision and human approver/date:

Only after the complete synthetic disposable run passes may a separately authorized controlled copy of real data be considered. Never run the one-way migration first against the production note folder or production Vault.
