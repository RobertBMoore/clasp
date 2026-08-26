#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
VALIDATOR="$ROOT_DIR/script/validate_app_review_evidence.sh"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/clasp-app-review-evidence.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

BASE_RESPONSE="$ROOT_DIR/release/AppStore/APP_REVIEW_RESPONSE.md"
BASE_RECORDING="$ROOT_DIR/release/AppStore/APP_REVIEW_RECORDING.md"
BASE_MANIFEST="$ROOT_DIR/release/AppStore/APP_REVIEW_EVIDENCE.env"
KNOWN_PACKAGE_SHA='09dcc9361d7a95c5cb699507b7a5d381c3d925b88130c346aae2e3fe6d80ccb0'
VIDEO_BASE64='AAAAFGZ0eXBxdCAgAAAAAHF0ICAAAAAId2lkZQAAAKhtZGF0AAAAOwYFMkdWStxcTEM/lO/FETzRQ6gBAAADAAEDAAADAAECAAHmAAsAAAMAAAMAAAMCngwDiSQBDf////+AAAAAQiW4IB/eCOVM/4LMHptQ27MV46J60AESjwz+e+/xknhbgLhfiBe3ZzNq8Pp4KExAyQYAABeUCv/4Bkwj6JOGkJe34QAAABch4QRfxJTkTdJOZlYxGLSiDmACMa4HQAAAAzRtb292AAAAbG12aGQAAAAA5rQO2ua0DtoAAAJYAAAEsAABAAABAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAACwHRyYWsAAABcdGtoZAAAAA/mtA7a5rQO2gAAAAEAAAAAAAAEsAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAEAAAAAAQAAAAEAAAAAAAER0YXB0AAAAFGNsZWYAAAAAAEAAAABAAAAAAAAUcHJvZgAAAAAAQAAAAEAAAAAAABRlbm9mAAAAAABAAAAAQAAAAAAAJGVkdHMAAAAcZWxzdAAAAAAAAAABAAAEsAAAAAAAAQAAAAAB9G1kaWEAAAAgbWRoZAAAAADmtA7a5rQO2gAAAlgAAASwVcQAAAAAADFoZGxyAAAAAG1obHJ2aWRlYXBwbAAAAAAAAAAAEENvcmUgTWVkaWEgVmlkZW8AAAGbbWluZgAAABR2bWhkAAAAAQBAgACAAIAAAAAAOGhkbHIAAAAAZGhscmFsaXNhcHBsAAAAAAAAAAAXQ29yZSBNZWRpYSBEYXRhIEhhbmRsZXIAAAAkZGluZgAAABxkcmVmAAAAAAAAAAEAAAAMYWxpcwAAAAEAAAEjc3RibAAAAJFzdHNkAAAAAAAAAAEAAACBYXZjMQAAAAAAAAABAAAAAAAAAAAAAAIAAAACAABAAEAASAAAAEgAAAAAAAAAAQVILjI2NAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABj//wAAACdhdmNDAWQAC//hAAwnZAALrFZQw3gQYRQBAAQo7jyw/fj4AAAAAAAAAAAYc3R0cwAAAAAAAAABAAAAAgAAAlgAAAAUc3RzcwAAAAAAAAABAAAAAQAAAA5zZHRwAAAAACAQAAAAHHN0c2MAAAAAAAAAAQAAAAEAAAABAAAAAQAAABxzdHN6AAAAAAAAAAAAAAACAAAAhQAAABsAAAAYc3RjbwAAAAAAAAACAAAAJAAAAKk='

fail() {
  echo "App Review evidence fixture failed: $*" >&2
  exit 1
}

expect_fail() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail "expected validation failure: $name"
  fi
}

expect_fail_with_message() {
  local name="$1"
  local expected_message="$2"
  shift 2
  local output
  if output="$("$@" 2>&1)"; then
    fail "expected validation failure: $name"
  fi
  grep -F "$expected_message" <<< "$output" >/dev/null \
    || fail "validation failed for $name without the expected message"
}

make_draft_bundle() {
  local directory="$1"
  mkdir -p "$directory"
  cp "$BASE_RESPONSE" "$directory/response.md"
  cp "$BASE_RECORDING" "$directory/recording.md"
  cp "$BASE_MANIFEST" "$directory/evidence.env"
}

run_draft() {
  local directory="$1"
  "$VALIDATOR" --draft \
    --response "$directory/response.md" \
    --recording-plan "$directory/recording.md" \
    --manifest "$directory/evidence.env"
}

write_final_response() {
  local directory="$1"
  local package_sha="$2"
  local video_sha="$3"
  local video_bytes="$4"
  local fixture_sha="$5"
  cat > "$directory/APP_REVIEW_RESPONSE_FINAL.md" <<EOF
# Final Apple response
Status: FINAL — independently verified against the attached evidence bundle
Submission: 4f60dde3-4ad3-4d0b-a21b-3cc63edd7453
Version/build: 1.0.0 (8)
Uploaded package SHA-256: $package_sha
Latest macOS tested: 26.6.2 build 25G83
Physical device: MacBook Pro Mac16,5; Apple M4 Max, arm64
TestFlight build: 1.0.0 (8)
Recording: apple-review.mov; $video_bytes bytes; SHA-256 $video_sha
Attachment reference: asc-review-attachment-001
Fixture-manifest SHA-256: $fixture_sha
Privacy reviewer: reviewer-one
Region recheck: PASS_CHINA_MAINLAND_EXCLUDED
Trader recheck: PASS_NOT_TRADER
### 1. Physical recording attachment reference
The one-take recording apple-review.mov is attached as asc-review-attachment-001, $video_bytes bytes, SHA-256 $video_sha.
### 2. Tested physical device and operating system
MacBook Pro Mac16,5; Apple M4 Max, arm64; macOS 26.6.2 build 25G83; TestFlight 1.0.0 (8).
### 3. Purpose, audience, problem, and value
Clasp is a local-first Markdown notes app for individual Mac users.
### 4. Setup, access, and sample data
No login, account, invitation, demo credential, or special server access is required. Synthetic fixtures are attached.
### 5. External services, data, authentication, payment, and AI
There are no purchases, in-app purchases, subscriptions, payment flow, backend, cloud sync, analytics, tracking, external AI, or note-content transmission. There is no public/cloud user-generated-content service. Store builds update only through the Mac App Store.
### 6. Regional consistency and China exclusion
Functions are region-consistent. China mainland is intentionally excluded.
### 7. Regulated or protected-material applicability
Paper LLC is not a trader for this app. Clasp is not a regulated product or service and uses no protected third-party material.
EOF
}

format_epoch() {
  /bin/date -r "$1" '+%Y-%m-%dT%H:%M:%S%z' | sed -E 's/([+-][0-9]{2})([0-9]{2})$/\1:\2/'
}

make_final_bundle() {
  local directory="$1"
  mkdir -p "$directory"
  printf '%s' 'synthetic package fixture' > "$directory/Clasp-1.0.0-8-AppStore.pkg"
  cp "$BASE_VIDEO" "$directory/apple-review.mov"
  cp "$directory/apple-review.mov" "$directory/apple-review-upload.mov"
  cp "$ROOT_DIR/release/AppStore/APP_REVIEW_FIXTURES.txt" "$directory/APP_REVIEW_FIXTURES.txt"

  local package_sha video_sha video_bytes fixture_sha now capture_at privacy_at independent_at recheck_at
  package_sha="$(/usr/bin/shasum -a 256 "$directory/Clasp-1.0.0-8-AppStore.pkg" | awk '{print $1}')"
  video_sha="$(/usr/bin/shasum -a 256 "$directory/apple-review.mov" | awk '{print $1}')"
  video_bytes="$(/usr/bin/stat -f '%z' "$directory/apple-review.mov")"
  fixture_sha="$(/usr/bin/shasum -a 256 "$directory/APP_REVIEW_FIXTURES.txt" | awk '{print $1}')"
  now="$(/bin/date '+%s')"
  capture_at="$(format_epoch $((now - 1200)))"
  privacy_at="$(format_epoch $((now - 900)))"
  independent_at="$(format_epoch $((now - 600)))"
  recheck_at="$(format_epoch $((now - 300)))"

  sed "s/$KNOWN_PACKAGE_SHA/$package_sha/g" "$BASE_RECORDING" > "$directory/APP_REVIEW_RECORDING.md"
  sed -E -i '' \
    -e 's/^Status: .*/Status: **FINAL — independently verified against the evidence manifest**/' \
    -e 's/The evidence fields below are blank until the take actually occurs\./The evidence fields below were filled from the exact completed take./' \
    -e 's/\*\*\[PENDING[^]]*\]\*\*/FINAL/g' \
    -e 's/^- \[ \]/- [x]/' \
    "$directory/APP_REVIEW_RECORDING.md"
  sed -i '' \
    -e 's#^- TestFlight app/build identifier:.*#- TestFlight app/build identifier: 1.0.0 (8)#' \
    -e 's#^- TestFlight installation source:.*#- TestFlight installation source: Apple TestFlight#' \
    -e 's#^- Physical device model:.*#- Physical device model: MacBook Pro Mac16,5#' \
    -e 's#^- Chip and architecture:.*#- Chip and architecture: Apple M4 Max, arm64#' \
    -e 's#^- macOS version and build:.*#- macOS version and build: 26.6.2 build 25G83#' \
    -e 's#^- Latest-OS proof (`26.6.2`):.*#- Latest-OS proof (`26.6.2`): PASS on physical TestFlight run#' \
    -e "s#^- Recording start date/time and timezone:.*#- Recording start date/time and timezone: $capture_at#" \
    -e 's#^- Recording duration:.*#- Recording duration: 2.000 seconds#' \
    -e 's#^- Recording format/container and resolution:.*#- Recording format/container and resolution: video/quicktime; 64x64#' \
    -e 's#^- Original recording filename:.*#- Original recording filename: apple-review.mov#' \
    -e "s#^- Original recording byte size:.*#- Original recording byte size: $video_bytes#" \
    -e "s#^- Original recording SHA-256:.*#- Original recording SHA-256: $video_sha#" \
    -e 's#^- Uploaded attachment filename:.*#- Uploaded attachment filename: apple-review-upload.mov#' \
    -e "s#^- Uploaded attachment byte size:.*#- Uploaded attachment byte size: $video_bytes#" \
    -e "s#^- Uploaded attachment SHA-256:.*#- Uploaded attachment SHA-256: $video_sha#" \
    -e 's#^- App Store Connect attachment reference:.*#- App Store Connect attachment reference: asc-review-attachment-001#' \
    -e 's#^- Fixture manifest filename:.*#- Fixture manifest filename: APP_REVIEW_FIXTURES.txt#' \
    -e "s#^- Fixture manifest SHA-256:.*#- Fixture manifest SHA-256: $fixture_sha#" \
    -e 's#^- Capture operator:.*#- Capture operator: capture-op#' \
    -e "s#^- Privacy review result:.*#- Privacy review result: PASS by reviewer-one at $privacy_at#" \
    -e "s#^- Evidence reviewer and review date:.*#- Evidence reviewer and review date: reviewer-two at $independent_at#" \
    "$directory/APP_REVIEW_RECORDING.md"
  write_final_response "$directory" "$package_sha" "$video_sha" "$video_bytes" "$fixture_sha"
  cat > "$directory/APP_REVIEW_EVIDENCE.env" <<EOF
EVIDENCE_STATUS=FINAL
SUBMISSION_ID=4f60dde3-4ad3-4d0b-a21b-3cc63edd7453
VERSION_BUILD=1.0.0 (8)
PACKAGE_FILENAME=Clasp-1.0.0-8-AppStore.pkg
PACKAGE_SHA256=$package_sha
TESTFLIGHT_VERSION_BUILD=1.0.0 (8)
PHYSICAL_DEVICE_MODEL=MacBook Pro Mac16,5
CHIP_ARCH=Apple M4 Max, arm64
MACOS_VERSION=26.6.2
MACOS_BUILD=25G83
RECORDING_FILENAME=apple-review.mov
RECORDING_BYTES=$video_bytes
RECORDING_SHA256=$video_sha
RECORDING_MIME=video/quicktime
RECORDING_DURATION_SECONDS=2.000
RECORDING_WIDTH=64
RECORDING_HEIGHT=64
UPLOADED_ATTACHMENT_FILENAME=apple-review-upload.mov
UPLOADED_ATTACHMENT_BYTES=$video_bytes
UPLOADED_ATTACHMENT_SHA256=$video_sha
APP_STORE_ATTACHMENT_REFERENCE=asc-review-attachment-001
FIXTURE_MANIFEST_FILENAME=APP_REVIEW_FIXTURES.txt
FIXTURE_MANIFEST_SHA256=$fixture_sha
CAPTURE_STARTED_AT=$capture_at
CAPTURE_OPERATOR=capture-op
PRIVACY_REVIEW_RESULT=PASS
PRIVACY_REVIEWER=reviewer-one
PRIVACY_REVIEWED_AT=$privacy_at
PRIVACY_REVIEW_RECORDING_SHA256=$video_sha
INDEPENDENT_REVIEW_RESULT=PASS
INDEPENDENT_REVIEWER=reviewer-two
INDEPENDENT_REVIEWED_AT=$independent_at
INDEPENDENT_REVIEW_RECORDING_SHA256=$video_sha
REGION_RECHECK_RESULT=PASS_CHINA_MAINLAND_EXCLUDED
REGION_RECHECKED_AT=$recheck_at
TRADER_RECHECK_RESULT=PASS_NOT_TRADER
TRADER_RECHECKED_AT=$recheck_at
EOF
}

run_test_final() {
  local directory="$1"
  run_test_final_paths \
    "$directory" \
    "$directory/APP_REVIEW_RESPONSE_FINAL.md" \
    "$directory/APP_REVIEW_RECORDING.md"
}

run_test_final_paths() {
  local directory="$1"
  local response_path="$2"
  local recording_path="$3"
  (
    # The production CLI hard-codes the submitted package SHA. A sourced test
    # invocation substitutes only this synthetic fixture's expected SHA so the
    # same final-mode hash logic can receive a positive unit fixture.
    source "$VALIDATOR"
    DEFAULT_RESPONSE="${APP_REVIEW_TEST_DEFAULT_RESPONSE:-$DEFAULT_RESPONSE}"
    DEFAULT_RECORDING_PLAN="${APP_REVIEW_TEST_DEFAULT_RECORDING:-$DEFAULT_RECORDING_PLAN}"
    PACKAGE_SHA="$(sed -n 's/^PACKAGE_SHA256=//p' "$directory/APP_REVIEW_EVIDENCE.env")"
    main --final \
      --response "$response_path" \
      --recording-plan "$recording_path" \
      --manifest "$directory/APP_REVIEW_EVIDENCE.env" \
      --package "$directory/Clasp-1.0.0-8-AppStore.pkg" \
      --video "$directory/apple-review.mov" \
      --attachment "$directory/apple-review-upload.mov" \
      --fixtures "$directory/APP_REVIEW_FIXTURES.txt"
  )
}

run_test_final_with_default_overrides() {
  local directory="$1"
  local default_response="$2"
  local default_recording="$3"
  APP_REVIEW_TEST_DEFAULT_RESPONSE="$default_response" \
    APP_REVIEW_TEST_DEFAULT_RECORDING="$default_recording" \
    run_test_final "$directory"
}

run_test_final_with_manifest_mutation() {
  local directory="$1"
  local wrapper_directory="$directory/xcrun-wrapper"
  mkdir -p "$wrapper_directory"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "%s\n" "# concurrent mutation fixture" >> "$APP_REVIEW_MUTATE_MANIFEST"' \
    'exec /usr/bin/xcrun "$@"' \
    > "$wrapper_directory/xcrun"
  chmod +x "$wrapper_directory/xcrun"
  (
    source "$VALIDATOR"
    PACKAGE_SHA="$(sed -n 's/^PACKAGE_SHA256=//p' "$directory/APP_REVIEW_EVIDENCE.env")"
    PATH="$wrapper_directory:$PATH" \
      APP_REVIEW_MUTATE_MANIFEST="$directory/APP_REVIEW_EVIDENCE.env" \
      main --final \
        --response "$directory/APP_REVIEW_RESPONSE_FINAL.md" \
        --recording-plan "$directory/APP_REVIEW_RECORDING.md" \
        --manifest "$directory/APP_REVIEW_EVIDENCE.env" \
        --package "$directory/Clasp-1.0.0-8-AppStore.pkg" \
        --video "$directory/apple-review.mov" \
        --attachment "$directory/apple-review-upload.mov" \
        --fixtures "$directory/APP_REVIEW_FIXTURES.txt"
  )
}

BASE_VIDEO="$TEMP_DIR/base-video.mov"
printf '%s' "$VIDEO_BASE64" | /usr/bin/base64 -D > "$BASE_VIDEO"

DRAFT="$TEMP_DIR/draft"
make_draft_bundle "$DRAFT"
run_draft "$DRAFT" >/dev/null

cp "$DRAFT/response.md" "$DRAFT/response-valid.md"
printf '%s\n' '### 1. Physical recording attachment reference' >> "$DRAFT/response.md"
expect_fail duplicate_section run_draft "$DRAFT"
mv "$DRAFT/response-valid.md" "$DRAFT/response.md"

cp "$DRAFT/evidence.env" "$DRAFT/evidence-valid.env"
sed -i '' '/^TESTFLIGHT_VERSION_BUILD=/d' "$DRAFT/evidence.env"
expect_fail missing_named_field run_draft "$DRAFT"
cp "$DRAFT/evidence-valid.env" "$DRAFT/evidence.env"

printf '%s\n' 'UNKNOWN_EVIDENCE=PENDING' >> "$DRAFT/evidence.env"
expect_fail unknown_manifest_key run_draft "$DRAFT"
cp "$DRAFT/evidence-valid.env" "$DRAFT/evidence.env"

printf '%s\n' 'MACOS_BUILD=PENDING' >> "$DRAFT/evidence.env"
expect_fail duplicate_manifest_key run_draft "$DRAFT"
cp "$DRAFT/evidence-valid.env" "$DRAFT/evidence.env"

sed -i '' 's/VERSION_BUILD=1.0.0 (8)/VERSION_BUILD=1.0.0 (9)/' "$DRAFT/evidence.env"
expect_fail wrong_build run_draft "$DRAFT"
cp "$DRAFT/evidence-valid.env" "$DRAFT/evidence.env"

sed -i '' "s/$KNOWN_PACKAGE_SHA/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/" "$DRAFT/evidence.env"
expect_fail wrong_package_sha run_draft "$DRAFT"

FINAL="$TEMP_DIR/final"
make_final_bundle "$FINAL"
run_test_final "$FINAL" >/dev/null

NON_VIDEO="$TEMP_DIR/non-video"
make_final_bundle "$NON_VIDEO"
printf '%s' 'not video' > "$NON_VIDEO/apple-review.mov"
expect_fail non_video_container run_test_final "$NON_VIDEO"

EMPTY="$TEMP_DIR/empty"
make_final_bundle "$EMPTY"
: > "$EMPTY/apple-review.mov"
expect_fail empty_video run_test_final "$EMPTY"

BAD_CHECKSUM="$TEMP_DIR/checksum"
make_final_bundle "$BAD_CHECKSUM"
sed -i '' 's/^RECORDING_SHA256=.*/RECORDING_SHA256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/' "$BAD_CHECKSUM/APP_REVIEW_EVIDENCE.env"
expect_fail checksum_mismatch run_test_final "$BAD_CHECKSUM"

MISSING_ATTACHMENT="$TEMP_DIR/missing-attachment"
make_final_bundle "$MISSING_ATTACHMENT"
sed -i '' '/^UPLOADED_ATTACHMENT_SHA256=/d' "$MISSING_ATTACHMENT/APP_REVIEW_EVIDENCE.env"
expect_fail missing_attachment_metadata run_test_final "$MISSING_ATTACHMENT"

MISSING_GATE="$TEMP_DIR/missing-gate"
make_final_bundle "$MISSING_GATE"
sed -i '' '/structured final evidence bundle passes/d' "$MISSING_GATE/APP_REVIEW_RECORDING.md"
expect_fail missing_acceptance_gate run_test_final "$MISSING_GATE"

PACKAGE_MISMATCH="$TEMP_DIR/package-mismatch"
make_final_bundle "$PACKAGE_MISMATCH"
printf '%s' 'changed after manifest creation' >> "$PACKAGE_MISMATCH/Clasp-1.0.0-8-AppStore.pkg"
expect_fail actual_package_mismatch run_test_final "$PACKAGE_MISMATCH"

ATTACHMENT_MISMATCH="$TEMP_DIR/attachment-mismatch"
make_final_bundle "$ATTACHMENT_MISMATCH"
printf '%s' 'changed upload bytes' >> "$ATTACHMENT_MISMATCH/apple-review-upload.mov"
expect_fail attachment_byte_mismatch run_test_final "$ATTACHMENT_MISMATCH"

PRIVACY_BINDING="$TEMP_DIR/privacy-binding"
make_final_bundle "$PRIVACY_BINDING"
sed -i '' 's/^PRIVACY_REVIEW_RECORDING_SHA256=.*/PRIVACY_REVIEW_RECORDING_SHA256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/' "$PRIVACY_BINDING/APP_REVIEW_EVIDENCE.env"
expect_fail privacy_review_hash_mismatch run_test_final "$PRIVACY_BINDING"

SAME_REVIEWER="$TEMP_DIR/same-reviewer"
make_final_bundle "$SAME_REVIEWER"
sed -i '' 's/^CAPTURE_OPERATOR=.*/CAPTURE_OPERATOR=reviewer-one/' "$SAME_REVIEWER/APP_REVIEW_EVIDENCE.env"
expect_fail non_independent_privacy_review run_test_final "$SAME_REVIEWER"

CAPTURE_AS_INDEPENDENT="$TEMP_DIR/capture-as-independent"
make_final_bundle "$CAPTURE_AS_INDEPENDENT"
sed -i '' 's/^INDEPENDENT_REVIEWER=.*/INDEPENDENT_REVIEWER=capture-op/' "$CAPTURE_AS_INDEPENDENT/APP_REVIEW_EVIDENCE.env"
expect_fail capture_operator_as_independent_reviewer run_test_final "$CAPTURE_AS_INDEPENDENT"

SAME_INDEPENDENT_REVIEWERS="$TEMP_DIR/same-independent-reviewers"
make_final_bundle "$SAME_INDEPENDENT_REVIEWERS"
sed -i '' 's/^INDEPENDENT_REVIEWER=.*/INDEPENDENT_REVIEWER=reviewer-one/' "$SAME_INDEPENDENT_REVIEWERS/APP_REVIEW_EVIDENCE.env"
expect_fail_with_message \
  privacy_and_independent_reviewer_are_same \
  'privacy reviewer and independent reviewer must be different people' \
  run_test_final "$SAME_INDEPENDENT_REVIEWERS"

STALE_CAPTURE="$TEMP_DIR/stale-capture"
make_final_bundle "$STALE_CAPTURE"
sed -i '' 's/^CAPTURE_STARTED_AT=.*/CAPTURE_STARTED_AT=2020-01-01T00:00:00-06:00/' "$STALE_CAPTURE/APP_REVIEW_EVIDENCE.env"
expect_fail_with_message \
  stale_physical_capture \
  'physical capture evidence is older than 24 hours' \
  run_test_final "$STALE_CAPTURE"

WRONG_OS_BUILD="$TEMP_DIR/wrong-os-build"
make_final_bundle "$WRONG_OS_BUILD"
sed -i '' 's/^MACOS_BUILD=.*/MACOS_BUILD=25F84/' "$WRONG_OS_BUILD/APP_REVIEW_EVIDENCE.env"
expect_fail_with_message \
  latest_macos_version_with_old_build \
  'manifest key MACOS_BUILD does not match its required value' \
  run_test_final "$WRONG_OS_BUILD"

STALE_REGION="$TEMP_DIR/stale-region"
make_final_bundle "$STALE_REGION"
sed -i '' 's/^REGION_RECHECKED_AT=.*/REGION_RECHECKED_AT=2020-01-01T00:00:00-06:00/' "$STALE_REGION/APP_REVIEW_EVIDENCE.env"
expect_fail stale_live_region_recheck run_test_final "$STALE_REGION"

MISSING_REGION="$TEMP_DIR/missing-region"
make_final_bundle "$MISSING_REGION"
sed -i '' 's/^REGION_RECHECK_RESULT=.*/REGION_RECHECK_RESULT=PENDING/' "$MISSING_REGION/APP_REVIEW_EVIDENCE.env"
expect_fail missing_live_region_recheck run_test_final "$MISSING_REGION"

FUTURE_TRADER="$TEMP_DIR/future-trader"
make_final_bundle "$FUTURE_TRADER"
sed -i '' 's/^TRADER_RECHECKED_AT=.*/TRADER_RECHECKED_AT=2099-01-01T00:00:00-06:00/' "$FUTURE_TRADER/APP_REVIEW_EVIDENCE.env"
expect_fail future_trader_recheck run_test_final "$FUTURE_TRADER"

STALE_FINAL="$TEMP_DIR/stale-final"
make_final_bundle "$STALE_FINAL"
printf '%s\n' 'No physical TestFlight run is claimed yet.' >> "$STALE_FINAL/APP_REVIEW_RESPONSE_FINAL.md"
expect_fail contradictory_final_language run_test_final "$STALE_FINAL"

SYMLINK_VIDEO="$TEMP_DIR/symlink-video"
make_final_bundle "$SYMLINK_VIDEO"
mv "$SYMLINK_VIDEO/apple-review.mov" "$SYMLINK_VIDEO/video-target.mov"
ln -s "$SYMLINK_VIDEO/video-target.mov" "$SYMLINK_VIDEO/apple-review.mov"
expect_fail symlink_video run_test_final "$SYMLINK_VIDEO"

EMPTY_SAMPLE_VIDEO="$TEMP_DIR/empty-sample-video"
make_final_bundle "$EMPTY_SAMPLE_VIDEO"
/bin/dd if=/dev/zero of="$EMPTY_SAMPLE_VIDEO/apple-review.mov" bs=1 seek=36 count=160 conv=notrunc 2>/dev/null
expect_fail_with_message \
  metadata_only_video_without_decodable_frame \
  'App Review recording could not be decoded as video' \
  run_test_final "$EMPTY_SAMPLE_VIDEO"

SAME_FINAL_PATH="$TEMP_DIR/same-final-path"
make_final_bundle "$SAME_FINAL_PATH"
expect_fail_with_message \
  same_response_and_recording_path \
  'final response and recording record must be distinct regular files' \
  run_test_final_paths \
  "$SAME_FINAL_PATH" \
  "$SAME_FINAL_PATH/APP_REVIEW_RECORDING.md" \
  "$SAME_FINAL_PATH/APP_REVIEW_RECORDING.md"

HARD_LINK_FINAL_DOCS="$TEMP_DIR/hard-link-final-docs"
make_final_bundle "$HARD_LINK_FINAL_DOCS"
rm "$HARD_LINK_FINAL_DOCS/APP_REVIEW_RESPONSE_FINAL.md"
ln "$HARD_LINK_FINAL_DOCS/APP_REVIEW_RECORDING.md" "$HARD_LINK_FINAL_DOCS/APP_REVIEW_RESPONSE_FINAL.md"
expect_fail_with_message \
  hard_linked_response_and_recording \
  'final response and recording record must be distinct regular files' \
  run_test_final "$HARD_LINK_FINAL_DOCS"

DRAFT_RESPONSE_ALIAS="$TEMP_DIR/draft-response-alias"
make_final_bundle "$DRAFT_RESPONSE_ALIAS"
ln "$DRAFT_RESPONSE_ALIAS/APP_REVIEW_RESPONSE_FINAL.md" "$DRAFT_RESPONSE_ALIAS/checked-in-response.md"
expect_fail_with_message \
  final_response_hard_links_checked_in_draft \
  'final response and recording record must not alias checked-in draft documents' \
  run_test_final_with_default_overrides \
  "$DRAFT_RESPONSE_ALIAS" \
  "$DRAFT_RESPONSE_ALIAS/checked-in-response.md" \
  "$BASE_RECORDING"

DRAFT_RECORDING_ALIAS="$TEMP_DIR/draft-recording-alias"
make_final_bundle "$DRAFT_RECORDING_ALIAS"
ln "$DRAFT_RECORDING_ALIAS/APP_REVIEW_RECORDING.md" "$DRAFT_RECORDING_ALIAS/checked-in-recording.md"
expect_fail_with_message \
  final_recording_hard_links_checked_in_draft \
  'final response and recording record must not alias checked-in draft documents' \
  run_test_final_with_default_overrides \
  "$DRAFT_RECORDING_ALIAS" \
  "$BASE_RESPONSE" \
  "$DRAFT_RECORDING_ALIAS/checked-in-recording.md"

MUTATED_MANIFEST="$TEMP_DIR/mutated-manifest"
make_final_bundle "$MUTATED_MANIFEST"
expect_fail_with_message \
  manifest_changed_during_validation \
  'App Review evidence manifest changed while it was being validated' \
  run_test_final_with_manifest_mutation "$MUTATED_MANIFEST"

FALSE_PRIVACY_RESULT="$TEMP_DIR/false-privacy-result"
make_final_bundle "$FALSE_PRIVACY_RESULT"
sed -i '' 's/^- Privacy review result: PASS by /- Privacy review result: FAIL by /' "$FALSE_PRIVACY_RESULT/APP_REVIEW_RECORDING.md"
expect_fail_with_message \
  false_privacy_result_with_matching_reviewer \
  'final privacy review field must appear exactly once' \
  run_test_final "$FALSE_PRIVACY_RESULT"

WRONG_REVIEW_TIMESTAMP="$TEMP_DIR/wrong-review-timestamp"
make_final_bundle "$WRONG_REVIEW_TIMESTAMP"
sed -E -i '' 's#^- Evidence reviewer and review date: reviewer-two at .*#- Evidence reviewer and review date: reviewer-two at 2099-01-01T00:00:00-06:00#' "$WRONG_REVIEW_TIMESTAMP/APP_REVIEW_RECORDING.md"
expect_fail_with_message \
  independent_review_timestamp_not_bound \
  'final independent review field must appear exactly once' \
  run_test_final "$WRONG_REVIEW_TIMESTAMP"

WRONG_RECORDED_DURATION="$TEMP_DIR/wrong-recorded-duration"
make_final_bundle "$WRONG_RECORDED_DURATION"
sed -i '' 's/^- Recording duration: 2.000 seconds$/- Recording duration: 2.000 seconds plus unverified text/' "$WRONG_RECORDED_DURATION/APP_REVIEW_RECORDING.md"
expect_fail_with_message \
  recording_duration_suffix \
  'final recording duration field must appear exactly once' \
  run_test_final "$WRONG_RECORDED_DURATION"

CONTRADICTORY_CHINA="$TEMP_DIR/contradictory-china"
make_final_bundle "$CONTRADICTORY_CHINA"
printf '%s\n' 'China mainland is intentionally excluded, but China mainland is included.' >> "$CONTRADICTORY_CHINA/APP_REVIEW_RESPONSE_FINAL.md"
expect_fail_with_message \
  contradictory_china_wording \
  'final response contains contradictory China-mainland availability wording' \
  run_test_final "$CONTRADICTORY_CHINA"

CONTRADICTORY_TRADER="$TEMP_DIR/contradictory-trader"
make_final_bundle "$CONTRADICTORY_TRADER"
printf '%s\n' 'Paper LLC is not a trader, although this is a trading product.' >> "$CONTRADICTORY_TRADER/APP_REVIEW_RESPONSE_FINAL.md"
expect_fail_with_message \
  contradictory_trader_wording \
  'final response contains contradictory trader wording' \
  run_test_final "$CONTRADICTORY_TRADER"

echo 'App Review evidence fixtures passed'
