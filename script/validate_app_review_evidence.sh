#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DEFAULT_RESPONSE="$ROOT_DIR/release/AppStore/APP_REVIEW_RESPONSE.md"
DEFAULT_RECORDING_PLAN="$ROOT_DIR/release/AppStore/APP_REVIEW_RECORDING.md"
DEFAULT_MANIFEST="$ROOT_DIR/release/AppStore/APP_REVIEW_EVIDENCE.env"
MEDIA_PROBE="$ROOT_DIR/script/app_review_media_probe.swift"

RESPONSE_PATH="$DEFAULT_RESPONSE"
RECORDING_PATH="$DEFAULT_RECORDING_PLAN"
MANIFEST_PATH="$DEFAULT_MANIFEST"
PACKAGE_PATH=""
VIDEO_PATH=""
ATTACHMENT_PATH=""
FIXTURES_PATH=""
MODE=""
RESPONSE_EXPLICIT=0
RECORDING_EXPLICIT=0
TEMP_DIR=""

SUBMISSION_ID='4f60dde3-4ad3-4d0b-a21b-3cc63edd7453'
VERSION_BUILD='1.0.0 (8)'
PACKAGE_FILENAME='Clasp-1.0.0-8-AppStore.pkg'
PACKAGE_SHA='09dcc9361d7a95c5cb699507b7a5d381c3d925b88130c346aae2e3fe6d80ccb0'
LATEST_MACOS='26.6.2'
LATEST_MACOS_BUILD='25G83'

MANIFEST_KEYS=(
  EVIDENCE_STATUS SUBMISSION_ID VERSION_BUILD PACKAGE_FILENAME PACKAGE_SHA256
  TESTFLIGHT_VERSION_BUILD PHYSICAL_DEVICE_MODEL CHIP_ARCH MACOS_VERSION MACOS_BUILD
  RECORDING_FILENAME RECORDING_BYTES RECORDING_SHA256 RECORDING_MIME
  RECORDING_DURATION_SECONDS RECORDING_WIDTH RECORDING_HEIGHT
  UPLOADED_ATTACHMENT_FILENAME UPLOADED_ATTACHMENT_BYTES UPLOADED_ATTACHMENT_SHA256
  APP_STORE_ATTACHMENT_REFERENCE FIXTURE_MANIFEST_FILENAME FIXTURE_MANIFEST_SHA256
  CAPTURE_STARTED_AT CAPTURE_OPERATOR PRIVACY_REVIEW_RESULT PRIVACY_REVIEWER
  PRIVACY_REVIEWED_AT PRIVACY_REVIEW_RECORDING_SHA256 INDEPENDENT_REVIEW_RESULT
  INDEPENDENT_REVIEWER INDEPENDENT_REVIEWED_AT INDEPENDENT_REVIEW_RECORDING_SHA256
  REGION_RECHECK_RESULT REGION_RECHECKED_AT TRADER_RECHECK_RESULT TRADER_RECHECKED_AT
)

DYNAMIC_MANIFEST_KEYS=(
  TESTFLIGHT_VERSION_BUILD PHYSICAL_DEVICE_MODEL CHIP_ARCH MACOS_VERSION MACOS_BUILD
  RECORDING_FILENAME RECORDING_BYTES RECORDING_SHA256 RECORDING_MIME
  RECORDING_DURATION_SECONDS RECORDING_WIDTH RECORDING_HEIGHT
  UPLOADED_ATTACHMENT_FILENAME UPLOADED_ATTACHMENT_BYTES UPLOADED_ATTACHMENT_SHA256
  APP_STORE_ATTACHMENT_REFERENCE FIXTURE_MANIFEST_FILENAME FIXTURE_MANIFEST_SHA256
  CAPTURE_STARTED_AT CAPTURE_OPERATOR PRIVACY_REVIEW_RESULT PRIVACY_REVIEWER
  PRIVACY_REVIEWED_AT PRIVACY_REVIEW_RECORDING_SHA256 INDEPENDENT_REVIEW_RESULT
  INDEPENDENT_REVIEWER INDEPENDENT_REVIEWED_AT INDEPENDENT_REVIEW_RECORDING_SHA256
  REGION_RECHECK_RESULT REGION_RECHECKED_AT TRADER_RECHECK_RESULT TRADER_RECHECKED_AT
)

usage() {
  cat >&2 <<'USAGE'
Usage:
  validate_app_review_evidence.sh --draft [--response PATH] [--recording-plan PATH] [--manifest PATH]
  validate_app_review_evidence.sh --final --response FINAL_RESPONSE --recording-plan FINAL_RECORD \
    --manifest MANIFEST \
    --package PKG --video MOV_OR_MP4 --attachment UPLOAD_FILE --fixtures FIXTURE_FILE \
    [--recording-plan PATH]

Draft mode validates the checked-in, explicitly incomplete evidence template.
Final mode requires a separate final response plus a structured, hash-bound
evidence bundle and validates the actual package, recording, upload file, media
metadata, fixtures, privacy review, independent review, territory recheck, and
trader-declaration recheck. It does not upload or submit anything.
USAGE
  exit 64
}

cleanup() {
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf "$TEMP_DIR"
  fi
}

fail() {
  echo "App Review evidence validation failed: $*" >&2
  exit 1
}

require_regular_file() {
  local path="$1"
  local label="$2"
  [[ -f "$path" && ! -L "$path" ]] \
    || fail "$label must be a regular, non-symbolic-link file"
  [[ -s "$path" ]] \
    || fail "$label must not be empty"
}

require_fixed() {
  local path="$1"
  local label="$2"
  local value="$3"
  grep -F -- "$value" "$path" >/dev/null \
    || fail "$label is missing"
}

require_exact_line() {
  local path="$1"
  local label="$2"
  local value="$3"
  local count
  count="$(grep -Fxc -- "$value" "$path" || true)"
  [[ "$count" == '1' ]] \
    || fail "$label must appear exactly once"
}

require_unique_field() {
  local path="$1"
  local label="$2"
  local field="$3"
  awk -v prefix="- $field:" '
    index($0, prefix) == 1 { count++ }
    END { exit count == 1 ? 0 : 1 }
  ' "$path" || fail "$label must appear as exactly one anchored field"
}

require_exact_field_value() {
  local path="$1"
  local label="$2"
  local field="$3"
  local value="$4"
  require_exact_line "$path" "$label" "- $field: $value"
}

require_unique_gate() {
  local path="$1"
  local label="$2"
  local gate="$3"
  awk -v unchecked="- [ ] $gate" -v checked="- [x] $gate" '
    $0 == unchecked || $0 == checked { count++ }
    END { exit count == 1 ? 0 : 1 }
  ' "$path" || fail "$label must appear as exactly one checkbox row"
}

require_regex() {
  local path="$1"
  local label="$2"
  local pattern="$3"
  grep -Eiq -- "$pattern" "$path" \
    || fail "$label is missing"
}

require_pending_field() {
  local path="$1"
  local label="$2"
  local field="$3"
  awk -v prefix="- $field:" '
    index($0, prefix) == 1 && index($0, "[PENDING") > 0 { count++ }
    END { exit count == 1 ? 0 : 1 }
  ' "$path" || fail "$label is missing or duplicated"
}

is_manifest_key() {
  local candidate="$1"
  local key
  for key in "${MANIFEST_KEYS[@]}"; do
    [[ "$candidate" == "$key" ]] && return 0
  done
  return 1
}

manifest_value() {
  local key="$1"
  local count value
  count="$(grep -Ec "^${key}=" "$MANIFEST_PATH" || true)"
  [[ "$count" == '1' ]] \
    || fail "manifest key $key must appear exactly once"
  value="$(sed -n "s/^${key}=//p" "$MANIFEST_PATH")"
  [[ -n "$value" && "$value" != *$'\r'* ]] \
    || fail "manifest key $key has an invalid value"
  printf '%s' "$value"
}

require_manifest_value() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(manifest_value "$key")"
  [[ "$actual" == "$expected" ]] \
    || fail "manifest key $key does not match its required value"
}

require_manifest_regex() {
  local key="$1"
  local pattern="$2"
  local actual
  actual="$(manifest_value "$key")"
  [[ "$actual" =~ $pattern ]] \
    || fail "manifest key $key has an invalid format"
}

validate_manifest_schema() {
  require_regular_file "$MANIFEST_PATH" 'App Review evidence manifest'
  local line key
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" =~ ^[A-Z0-9_]+=.+$ ]] \
      || fail 'manifest contains a malformed line'
    key="${line%%=*}"
    is_manifest_key "$key" \
      || fail "manifest contains unknown key $key"
  done < "$MANIFEST_PATH"

  for key in "${MANIFEST_KEYS[@]}"; do
    manifest_value "$key" >/dev/null
  done

  require_manifest_value SUBMISSION_ID "$SUBMISSION_ID"
  require_manifest_value VERSION_BUILD "$VERSION_BUILD"
  require_manifest_value PACKAGE_FILENAME "$PACKAGE_FILENAME"
  require_manifest_value PACKAGE_SHA256 "$PACKAGE_SHA"
}

validate_document_contract() {
  require_regular_file "$RESPONSE_PATH" 'App Review response'
  require_regular_file "$RECORDING_PATH" 'recording plan'
  require_regular_file "$MEDIA_PROBE" 'media probe'

  local heading
  for heading in \
    '### 1. Physical recording attachment reference' \
    '### 2. Tested physical device and operating system' \
    '### 3. Purpose, audience, problem, and value' \
    '### 4. Setup, access, and sample data' \
    '### 5. External services, data, authentication, payment, and AI' \
    '### 6. Regional consistency and China exclusion' \
    '### 7. Regulated or protected-material applicability'; do
    require_exact_line "$RESPONSE_PATH" "Apple response section: $heading" "$heading"
  done

  require_fixed "$RESPONSE_PATH" 'reviewed version/build' "$VERSION_BUILD"
  require_fixed "$RESPONSE_PATH" 'uploaded package custody SHA-256' "$PACKAGE_SHA"
  require_fixed "$RECORDING_PATH" 'recording version/build' "$VERSION_BUILD"
  require_fixed "$RECORDING_PATH" 'recording package custody SHA-256' "$PACKAGE_SHA"
  require_fixed "$RESPONSE_PATH" 'latest macOS evidence target' "$LATEST_MACOS"
  require_fixed "$RECORDING_PATH" 'recording latest macOS target' "$LATEST_MACOS"

  require_regex "$RESPONSE_PATH" 'no-account access statement' \
    'No login, account, invitation, demo credential, or special server access is required'
  require_regex "$RESPONSE_PATH" 'no-purchase statement' \
    'no (login or account system, )?purchases?, (in-app purchases|IAP), subscriptions?, payment flow'
  require_regex "$RESPONSE_PATH" 'no public/cloud UGC statement' \
    'no public(/| or )cloud (user-generated-content|UGC)'
  require_regex "$RESPONSE_PATH" 'no-backend statement' 'no .*backend'
  require_regex "$RESPONSE_PATH" 'no-external-AI statement' 'no .*external AI'
  require_regex "$RESPONSE_PATH" 'no-content-transmission statement' 'no .*content transmission'
  require_regex "$RESPONSE_PATH" 'Mac App Store update-channel statement' \
    '(App Store|Store) builds? update only through the Mac App Store'
  require_regex "$RESPONSE_PATH" 'region-consistency statement' \
    '(region-consistent|consistent in every territory)'
  require_regex "$RESPONSE_PATH" 'China mainland exclusion statement' \
    'China mainland is intentionally excluded'
  require_regex "$RESPONSE_PATH" 'non-regulated statement' \
    '(not a regulated product or service|not a regulated product)'
  require_regex "$RESPONSE_PATH" 'protected-material statement' \
    'no protected third-party material'

  require_exact_line "$RECORDING_PATH" 'evidence fields section' '## Evidence fields'
  require_exact_line "$RECORDING_PATH" 'recording acceptance gates' '## Acceptance gates'

  local field
  for field in \
    'TestFlight app/build identifier' 'TestFlight installation source' 'Physical device model' \
    'Chip and architecture' 'macOS version and build' 'Latest-OS proof (`26.6.2`)' \
    'Recording start date/time and timezone' 'Recording duration' \
    'Recording format/container and resolution' 'Original recording filename' \
    'Original recording byte size' 'Original recording SHA-256' \
    'Uploaded attachment filename' 'Uploaded attachment byte size' \
    'Uploaded attachment SHA-256' 'App Store Connect attachment reference' \
    'Fixture manifest filename' 'Fixture manifest SHA-256' 'Capture operator' \
    'Privacy review result' 'Evidence reviewer and review date'; do
    require_unique_field "$RECORDING_PATH" "recording field: $field" "$field"
  done

  local gate package_gate
  package_gate='The package custody hash remains `'
  package_gate+="$PACKAGE_SHA"
  package_gate+='`.'
  for gate in \
    'Physical Mac identity and observed OS/build are recorded during the one-take.' \
    'The app was installed and launched from TestFlight, and the visible build is exactly `1.0.0 (8)`.' \
    'The latest-OS gate is closed with physical TestFlight evidence on macOS `26.6.2`; otherwise resubmission remains blocked.' \
    'The recording is one contiguous take with no post-capture edits.' \
    'The recording shows only synthetic fixtures and passes the privacy review.' \
    'Regular local Markdown persistence and exact Markdown view are shown.' \
    'Vault local encryption/user-presence and locked state are shown without exposing a secret.' \
    'Store Services/clipboard behavior is shown without Accessibility-assisted selection capture.' \
    'No login/account, purchase/IAP/subscription, public/cloud UGC/moderation, analytics/tracking, cloud sync, external AI, backend, or content transmission is introduced by the flow.' \
    'Original and uploaded recording checksums, byte sizes, duration, and attachment reference are filled and verified.' \
    "$package_gate" \
    'Regional behavior is stated as consistent, China mainland remains intentionally excluded, and live availability is rechecked before resubmission.' \
    'The exact notes in [`APP_REVIEW_RESPONSE.md`](APP_REVIEW_RESPONSE.md), [`READINESS.md`](READINESS.md), [`SUBMISSION_HANDOFF.md`](SUBMISSION_HANDOFF.md), and [`METADATA_DRAFT.md`](METADATA_DRAFT.md) match the final evidence.' \
    'An independent reviewer confirms the recording and all fields before App Store Connect attachment.' \
    'The structured final evidence bundle passes `script/validate_app_review_evidence.sh --final` immediately before the live reply/upload.'; do
    require_unique_gate "$RECORDING_PATH" "recording acceptance gate: $gate" "$gate"
  done
}

validate_draft() {
  require_manifest_value EVIDENCE_STATUS DRAFT
  local key
  for key in "${DYNAMIC_MANIFEST_KEYS[@]}"; do
    require_manifest_value "$key" PENDING
  done

  require_fixed "$RESPONSE_PATH" 'response evidence warning' \
    'not ready to send while any `[PENDING ...]` field remains'
  require_fixed "$RECORDING_PATH" 'recording evidence-plan status' \
    'evidence plan only; no physical TestFlight run or recording is claimed'

  local field
  for field in \
    'TestFlight app/build identifier' 'TestFlight installation source' 'Physical device model' \
    'Chip and architecture' 'macOS version and build' 'Latest-OS proof (`26.6.2`)' \
    'Original recording filename' 'Original recording byte size' 'Original recording SHA-256' \
    'Uploaded attachment filename' 'Uploaded attachment byte size' \
    'Uploaded attachment SHA-256' 'App Store Connect attachment reference' \
    'Privacy review result' 'Evidence reviewer and review date'; do
    require_pending_field "$RECORDING_PATH" "pending recording field: $field" "$field"
  done
  echo 'App Review draft evidence contracts passed'
}

canonicalize_file() {
  local path="$1"
  local label="$2"
  local directory basename_value
  require_regular_file "$path" "$label"
  [[ "$path" != *$'\n'* && "$path" != *$'\r'* ]] \
    || fail "$label path contains an invalid character"
  directory="$(cd "$(dirname "$path")" && pwd -P)"
  basename_value="$(basename "$path")"
  [[ "$basename_value" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]] \
    || fail "$label filename is outside the safe grammar"
  printf '%s/%s' "$directory" "$basename_value"
}

sha256_file() {
  /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
}

file_size() {
  /usr/bin/stat -f '%z' "$1"
}

file_identity() {
  /usr/bin/stat -f '%d:%i:%z:%m' "$1"
}

require_stable_hash() {
  local path="$1"
  local label="$2"
  local first_identity="$3"
  local first_hash="$4"
  local second_identity second_hash
  second_identity="$(file_identity "$path")"
  second_hash="$(sha256_file "$path")"
  [[ "$second_identity" == "$first_identity" && "$second_hash" == "$first_hash" ]] \
    || fail "$label changed while it was being validated"
}

validate_timestamp_key() {
  require_manifest_regex "$1" '^20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[-+][0-9]{2}:[0-9]{2}$'
}

timestamp_epoch() {
  local value="$1"
  local normalized
  normalized="$(printf '%s' "$value" | sed -E 's/([+-][0-9]{2}):([0-9]{2})$/\1\2/')"
  /bin/date -j -f '%Y-%m-%dT%H:%M:%S%z' "$normalized" '+%s' 2>/dev/null \
    || fail 'manifest contains an invalid calendar timestamp'
}

validate_final_timeline() {
  local capture privacy independent region trader now oldest_allowed
  capture="$(timestamp_epoch "$(manifest_value CAPTURE_STARTED_AT)")"
  privacy="$(timestamp_epoch "$(manifest_value PRIVACY_REVIEWED_AT)")"
  independent="$(timestamp_epoch "$(manifest_value INDEPENDENT_REVIEWED_AT)")"
  region="$(timestamp_epoch "$(manifest_value REGION_RECHECKED_AT)")"
  trader="$(timestamp_epoch "$(manifest_value TRADER_RECHECKED_AT)")"
  now="$(/bin/date '+%s')"
  oldest_allowed=$((now - 86400))
  ((capture <= privacy && privacy <= independent)) \
    || fail 'capture, privacy review, and independent review timestamps are out of order'
  ((capture >= oldest_allowed)) \
    || fail 'physical capture evidence is older than 24 hours'
  ((region >= capture && trader >= capture)) \
    || fail 'region and trader rechecks must follow the physical capture'
  ((region >= oldest_allowed && trader >= oldest_allowed)) \
    || fail 'region or trader live-state recheck is older than 24 hours'
  ((region <= now + 300 && trader <= now + 300 && independent <= now + 300)) \
    || fail 'final evidence contains a future review or recheck timestamp'
}

validate_final() {
  [[ "$RESPONSE_EXPLICIT" == '1' && "$RECORDING_EXPLICIT" == '1' ]] \
    || fail 'final mode requires separate --response and --recording-plan files'
  [[ -n "$PACKAGE_PATH" && -n "$VIDEO_PATH" && -n "$ATTACHMENT_PATH" && -n "$FIXTURES_PATH" ]] \
    || fail 'final mode requires --package, --video, --attachment, and --fixtures'

  PACKAGE_PATH="$(canonicalize_file "$PACKAGE_PATH" 'App Store package')"
  VIDEO_PATH="$(canonicalize_file "$VIDEO_PATH" 'App Review recording')"
  ATTACHMENT_PATH="$(canonicalize_file "$ATTACHMENT_PATH" 'App Store attachment')"
  FIXTURES_PATH="$(canonicalize_file "$FIXTURES_PATH" 'fixture manifest')"
  MANIFEST_PATH="$(canonicalize_file "$MANIFEST_PATH" 'App Review evidence manifest')"
  RESPONSE_PATH="$(canonicalize_file "$RESPONSE_PATH" 'final App Review response')"
  RECORDING_PATH="$(canonicalize_file "$RECORDING_PATH" 'final App Review recording record')"

  local manifest_identity manifest_hash
  manifest_identity="$(file_identity "$MANIFEST_PATH")"
  manifest_hash="$(sha256_file "$MANIFEST_PATH")"

  local default_response_path default_recording_path
  local default_response_identity default_recording_identity
  default_response_path="$(canonicalize_file "$DEFAULT_RESPONSE" 'checked-in draft response')"
  default_recording_path="$(canonicalize_file "$DEFAULT_RECORDING_PLAN" 'checked-in draft recording plan')"
  default_response_identity="$(file_identity "$default_response_path")"
  default_recording_identity="$(file_identity "$default_recording_path")"
  [[ "$RESPONSE_PATH" != "$default_response_path" ]] \
    || fail 'final response resolves to the checked-in draft response'
  [[ "$RECORDING_PATH" != "$default_recording_path" ]] \
    || fail 'final recording record resolves to the checked-in draft recording plan'

  local response_identity recording_record_identity
  response_identity="$(file_identity "$RESPONSE_PATH")"
  recording_record_identity="$(file_identity "$RECORDING_PATH")"
  [[ "$RESPONSE_PATH" != "$RECORDING_PATH" && "$response_identity" != "$recording_record_identity" ]] \
    || fail 'final response and recording record must be distinct regular files'
  [[ "$response_identity" != "$default_response_identity" \
      && "$response_identity" != "$default_recording_identity" \
      && "$recording_record_identity" != "$default_response_identity" \
      && "$recording_record_identity" != "$default_recording_identity" ]] \
    || fail 'final response and recording record must not alias checked-in draft documents'

  local bundle_directory bundled
  bundle_directory="$(dirname "$MANIFEST_PATH")"
  for bundled in "$PACKAGE_PATH" "$VIDEO_PATH" "$ATTACHMENT_PATH" "$FIXTURES_PATH" "$RESPONSE_PATH" "$RECORDING_PATH"; do
    [[ "$(dirname "$bundled")" == "$bundle_directory" ]] \
      || fail 'all final evidence files must be regular files in one physical evidence-bundle directory'
  done

  validate_manifest_schema
  validate_document_contract
  require_manifest_value EVIDENCE_STATUS FINAL
  require_manifest_value TESTFLIGHT_VERSION_BUILD "$VERSION_BUILD"
  require_manifest_value MACOS_VERSION "$LATEST_MACOS"
  require_manifest_value MACOS_BUILD "$LATEST_MACOS_BUILD"
  require_manifest_value PHYSICAL_DEVICE_MODEL 'MacBook Pro Mac16,5'
  require_manifest_value CHIP_ARCH 'Apple M4 Max, arm64'
  require_manifest_value PACKAGE_FILENAME "$(basename "$PACKAGE_PATH")"
  require_manifest_value PRIVACY_REVIEW_RESULT PASS
  require_manifest_value INDEPENDENT_REVIEW_RESULT PASS
  require_manifest_value REGION_RECHECK_RESULT PASS_CHINA_MAINLAND_EXCLUDED
  require_manifest_value TRADER_RECHECK_RESULT PASS_NOT_TRADER
  require_manifest_regex APP_STORE_ATTACHMENT_REFERENCE '^[A-Za-z0-9][A-Za-z0-9._:/-]{2,255}$'
  require_manifest_regex CAPTURE_OPERATOR '^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$'
  require_manifest_regex PRIVACY_REVIEWER '^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$'
  require_manifest_regex INDEPENDENT_REVIEWER '^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$'
  validate_timestamp_key CAPTURE_STARTED_AT
  validate_timestamp_key PRIVACY_REVIEWED_AT
  validate_timestamp_key INDEPENDENT_REVIEWED_AT
  validate_timestamp_key REGION_RECHECKED_AT
  validate_timestamp_key TRADER_RECHECKED_AT
  [[ "$(manifest_value CAPTURE_OPERATOR)" != "$(manifest_value PRIVACY_REVIEWER)" ]] \
    || fail 'privacy reviewer must be independent from the capture operator'
  [[ "$(manifest_value CAPTURE_OPERATOR)" != "$(manifest_value INDEPENDENT_REVIEWER)" ]] \
    || fail 'independent reviewer must differ from the capture operator'
  [[ "$(manifest_value PRIVACY_REVIEWER)" != "$(manifest_value INDEPENDENT_REVIEWER)" ]] \
    || fail 'privacy reviewer and independent reviewer must be different people'
  validate_final_timeline

  local package_identity package_hash video_identity video_hash video_size_value
  local attachment_identity attachment_hash attachment_size fixture_identity fixture_hash
  local response_hash recording_record_hash
  package_identity="$(file_identity "$PACKAGE_PATH")"
  package_hash="$(sha256_file "$PACKAGE_PATH")"
  [[ "$package_hash" == "$PACKAGE_SHA" ]] \
    || fail 'actual App Store package SHA-256 does not match submitted package custody'

  video_identity="$(file_identity "$VIDEO_PATH")"
  video_hash="$(sha256_file "$VIDEO_PATH")"
  video_size_value="$(file_size "$VIDEO_PATH")"
  case "$VIDEO_PATH" in
    *.[Mm][Oo][Vv]|*.[Mm][Pp]4) ;;
    *) fail 'App Review recording must use a .mov or .mp4 filename' ;;
  esac

  local media_mime
  media_mime="$(/usr/bin/file -b --mime-type "$VIDEO_PATH")"
  [[ "$media_mime" == 'video/quicktime' || "$media_mime" == 'video/mp4' ]] \
    || fail 'App Review recording is not a recognized QuickTime or MP4 container'

  TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/clasp-app-review-probe.XXXXXX")"
  trap cleanup EXIT
  local probe_output duration width height
  if ! probe_output="$(xcrun swift -module-cache-path "$TEMP_DIR/module-cache" "$MEDIA_PROBE" "$VIDEO_PATH" 2>/dev/null)"; then
    fail 'App Review recording could not be decoded as video'
  fi
  IFS=$'\t' read -r duration width height <<< "$probe_output"
  [[ "$duration" =~ ^[0-9]+\.[0-9]{3}$ && "$duration" != '0.000' ]] \
    || fail 'App Review recording has no measurable duration'
  [[ "$width" =~ ^[1-9][0-9]*$ && "$height" =~ ^[1-9][0-9]*$ ]] \
    || fail 'App Review recording has no measurable video dimensions'

  attachment_identity="$(file_identity "$ATTACHMENT_PATH")"
  attachment_hash="$(sha256_file "$ATTACHMENT_PATH")"
  attachment_size="$(file_size "$ATTACHMENT_PATH")"
  [[ "$attachment_hash" == "$video_hash" && "$attachment_size" == "$video_size_value" ]] \
    || fail 'upload attachment bytes do not match the independently reviewed recording'

  fixture_identity="$(file_identity "$FIXTURES_PATH")"
  fixture_hash="$(sha256_file "$FIXTURES_PATH")"
  response_hash="$(sha256_file "$RESPONSE_PATH")"
  recording_record_hash="$(sha256_file "$RECORDING_PATH")"
  require_fixed "$FIXTURES_PATH" 'regular synthetic fixture token' 'APPLE-REVIEW-SYNTHETIC-001'
  require_fixed "$FIXTURES_PATH" 'Vault synthetic fixture token' 'VAULT-SYNTHETIC-ONLY-002'
  require_fixed "$FIXTURES_PATH" 'clipboard synthetic fixture token' 'APPLE-REVIEW-CLIPBOARD-003'
  require_fixed "$FIXTURES_PATH" 'reserved synthetic URL' 'https://example.invalid/apple-review'

  require_manifest_value RECORDING_FILENAME "$(basename "$VIDEO_PATH")"
  require_manifest_value RECORDING_BYTES "$video_size_value"
  require_manifest_value RECORDING_SHA256 "$video_hash"
  require_manifest_value RECORDING_MIME "$media_mime"
  require_manifest_value RECORDING_DURATION_SECONDS "$duration"
  require_manifest_value RECORDING_WIDTH "$width"
  require_manifest_value RECORDING_HEIGHT "$height"
  require_manifest_value UPLOADED_ATTACHMENT_FILENAME "$(basename "$ATTACHMENT_PATH")"
  require_manifest_value UPLOADED_ATTACHMENT_BYTES "$attachment_size"
  require_manifest_value UPLOADED_ATTACHMENT_SHA256 "$attachment_hash"
  require_manifest_value FIXTURE_MANIFEST_FILENAME "$(basename "$FIXTURES_PATH")"
  require_manifest_value FIXTURE_MANIFEST_SHA256 "$fixture_hash"
  require_manifest_value PRIVACY_REVIEW_RECORDING_SHA256 "$video_hash"
  require_manifest_value INDEPENDENT_REVIEW_RECORDING_SHA256 "$video_hash"

  if grep -F '[PENDING' "$RECORDING_PATH" >/dev/null \
      || grep -F -- '- [ ]' "$RECORDING_PATH" >/dev/null \
      || grep -Eiq 'evidence plan only|no physical TestFlight run or recording is claimed|evidence fields below are blank' "$RECORDING_PATH"; then
    fail 'final recording record retains a placeholder, unchecked gate, or contradictory draft-language claim'
  fi
  require_exact_line "$RECORDING_PATH" 'final recording-record status' 'Status: **FINAL — independently verified against the evidence manifest**'
  require_exact_field_value "$RECORDING_PATH" 'final app/version/build field' 'App/version/build' "\`Clasp: Private Markdown Notes\` / \`$VERSION_BUILD\`"
  require_exact_field_value "$RECORDING_PATH" 'final uploaded package field' 'Uploaded package SHA-256' "\`$package_hash\`"
  require_exact_field_value "$RECORDING_PATH" 'final TestFlight build field' 'TestFlight app/build identifier' "$VERSION_BUILD"
  require_exact_field_value "$RECORDING_PATH" 'final TestFlight source field' 'TestFlight installation source' 'Apple TestFlight'
  require_exact_field_value "$RECORDING_PATH" 'final physical device field' 'Physical device model' "$(manifest_value PHYSICAL_DEVICE_MODEL)"
  require_exact_field_value "$RECORDING_PATH" 'final chip/architecture field' 'Chip and architecture' "$(manifest_value CHIP_ARCH)"
  require_exact_field_value "$RECORDING_PATH" 'final macOS field' 'macOS version and build' "$(manifest_value MACOS_VERSION) build $(manifest_value MACOS_BUILD)"
  require_exact_field_value "$RECORDING_PATH" 'final latest-OS proof field' "Latest-OS proof (\`$LATEST_MACOS\`)" 'PASS on physical TestFlight run'
  require_exact_field_value "$RECORDING_PATH" 'final recording start field' 'Recording start date/time and timezone' "$(manifest_value CAPTURE_STARTED_AT)"
  require_exact_field_value "$RECORDING_PATH" 'final recording duration field' 'Recording duration' "$duration seconds"
  require_exact_field_value "$RECORDING_PATH" 'final recording media field' 'Recording format/container and resolution' "$media_mime; ${width}x${height}"
  require_exact_field_value "$RECORDING_PATH" 'final recording filename field' 'Original recording filename' "$(basename "$VIDEO_PATH")"
  require_exact_field_value "$RECORDING_PATH" 'final recording byte-size field' 'Original recording byte size' "$video_size_value"
  require_exact_field_value "$RECORDING_PATH" 'final recording SHA field' 'Original recording SHA-256' "$video_hash"
  require_exact_field_value "$RECORDING_PATH" 'final uploaded filename field' 'Uploaded attachment filename' "$(basename "$ATTACHMENT_PATH")"
  require_exact_field_value "$RECORDING_PATH" 'final uploaded byte-size field' 'Uploaded attachment byte size' "$attachment_size"
  require_exact_field_value "$RECORDING_PATH" 'final uploaded SHA field' 'Uploaded attachment SHA-256' "$attachment_hash"
  require_exact_field_value "$RECORDING_PATH" 'final attachment reference field' 'App Store Connect attachment reference' "$(manifest_value APP_STORE_ATTACHMENT_REFERENCE)"
  require_exact_field_value "$RECORDING_PATH" 'final fixture filename field' 'Fixture manifest filename' "$(basename "$FIXTURES_PATH")"
  require_exact_field_value "$RECORDING_PATH" 'final fixture SHA field' 'Fixture manifest SHA-256' "$fixture_hash"
  require_exact_field_value "$RECORDING_PATH" 'final capture operator field' 'Capture operator' "$(manifest_value CAPTURE_OPERATOR)"
  require_exact_field_value "$RECORDING_PATH" 'final privacy review field' 'Privacy review result' "PASS by $(manifest_value PRIVACY_REVIEWER) at $(manifest_value PRIVACY_REVIEWED_AT)"
  require_exact_field_value "$RECORDING_PATH" 'final independent review field' 'Evidence reviewer and review date' "$(manifest_value INDEPENDENT_REVIEWER) at $(manifest_value INDEPENDENT_REVIEWED_AT)"

  if grep -F '[PENDING' "$RESPONSE_PATH" >/dev/null \
      || grep -F -- '- [ ]' "$RESPONSE_PATH" >/dev/null \
      || grep -Eiq 'not attached yet|no physical TestFlight run is claimed yet|evidence plan only|remains gated|not ready to send' "$RESPONSE_PATH"; then
    fail 'final response retains a placeholder, unchecked gate, or contradictory draft-language claim'
  fi
  require_exact_line "$RESPONSE_PATH" 'final response status' 'Status: FINAL — independently verified against the attached evidence bundle'
  require_exact_line "$RESPONSE_PATH" 'final response submission' "Submission: $SUBMISSION_ID"
  require_exact_line "$RESPONSE_PATH" 'final response version/build' "Version/build: $VERSION_BUILD"
  require_exact_line "$RESPONSE_PATH" 'final response package SHA' "Uploaded package SHA-256: $package_hash"
  require_exact_line "$RESPONSE_PATH" 'final response latest macOS' "Latest macOS tested: $(manifest_value MACOS_VERSION) build $(manifest_value MACOS_BUILD)"
  require_exact_line "$RESPONSE_PATH" 'final response physical device' "Physical device: $(manifest_value PHYSICAL_DEVICE_MODEL); $(manifest_value CHIP_ARCH)"
  require_exact_line "$RESPONSE_PATH" 'final response TestFlight build' "TestFlight build: $(manifest_value TESTFLIGHT_VERSION_BUILD)"
  require_exact_line "$RESPONSE_PATH" 'final response recording' "Recording: $(basename "$VIDEO_PATH"); $video_size_value bytes; SHA-256 $video_hash"
  require_exact_line "$RESPONSE_PATH" 'final response attachment reference' "Attachment reference: $(manifest_value APP_STORE_ATTACHMENT_REFERENCE)"
  require_exact_line "$RESPONSE_PATH" 'final response fixture SHA' "Fixture-manifest SHA-256: $fixture_hash"
  require_exact_line "$RESPONSE_PATH" 'final response privacy reviewer' "Privacy reviewer: $(manifest_value PRIVACY_REVIEWER)"
  require_exact_line "$RESPONSE_PATH" 'final region recheck' \
    "Region recheck: $(manifest_value REGION_RECHECK_RESULT)"
  require_exact_line "$RESPONSE_PATH" 'final trader recheck' \
    "Trader recheck: $(manifest_value TRADER_RECHECK_RESULT)"
  if grep -Eiq 'China mainland is (included|available)|available in China mainland' "$RESPONSE_PATH"; then
    fail 'final response contains contradictory China-mainland availability wording'
  fi
  if grep -Eiq '(^|[^[:alpha:]])is a trader([^[:alpha:]]|$)|trading product' "$RESPONSE_PATH"; then
    fail 'final response contains contradictory trader wording'
  fi

  require_stable_hash "$PACKAGE_PATH" 'App Store package' "$package_identity" "$package_hash"
  require_stable_hash "$VIDEO_PATH" 'App Review recording' "$video_identity" "$video_hash"
  require_stable_hash "$ATTACHMENT_PATH" 'App Store attachment' "$attachment_identity" "$attachment_hash"
  require_stable_hash "$FIXTURES_PATH" 'fixture manifest' "$fixture_identity" "$fixture_hash"
  require_stable_hash "$MANIFEST_PATH" 'App Review evidence manifest' "$manifest_identity" "$manifest_hash"
  require_stable_hash "$RESPONSE_PATH" 'final App Review response' "$response_identity" "$response_hash"
  require_stable_hash "$RECORDING_PATH" 'final recording record' "$recording_record_identity" "$recording_record_hash"
  cleanup
  trap - EXIT
  echo "App Review final evidence contracts passed for $(basename "$VIDEO_PATH")"
}

main() {
  while (($# > 0)); do
    case "$1" in
      --draft|--final)
        [[ -z "$MODE" ]] || usage
        MODE="${1#--}"
        shift
        ;;
      --response)
        (($# >= 2)) || usage
        RESPONSE_PATH="$2"
        RESPONSE_EXPLICIT=1
        shift 2
        ;;
      --recording-plan)
        (($# >= 2)) || usage
        RECORDING_PATH="$2"
        RECORDING_EXPLICIT=1
        shift 2
        ;;
      --manifest)
        (($# >= 2)) || usage
        MANIFEST_PATH="$2"
        shift 2
        ;;
      --package)
        (($# >= 2)) || usage
        PACKAGE_PATH="$2"
        shift 2
        ;;
      --video)
        (($# >= 2)) || usage
        VIDEO_PATH="$2"
        shift 2
        ;;
      --attachment)
        (($# >= 2)) || usage
        ATTACHMENT_PATH="$2"
        shift 2
        ;;
      --fixtures)
        (($# >= 2)) || usage
        FIXTURES_PATH="$2"
        shift 2
        ;;
      *) usage ;;
    esac
  done

  [[ -n "$MODE" ]] || usage
  if [[ "$MODE" == 'draft' ]]; then
    [[ -z "$PACKAGE_PATH" && -z "$VIDEO_PATH" && -z "$ATTACHMENT_PATH" && -z "$FIXTURES_PATH" ]] || usage
    validate_manifest_schema
    validate_document_contract
    validate_draft
  else
    validate_final
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
