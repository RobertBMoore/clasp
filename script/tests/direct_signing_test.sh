#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck source=../lib/direct_signing.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/script/lib/direct_signing.sh"

expect_failure() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "expected direct-signing failure: $label" >&2
    exit 1
  fi
}

IDENTITY='Developer ID Application: Fixture LLC (ZYXWV67890)'
SELECTED_CERTIFICATE_SHA256='0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF'
OTHER_CERTIFICATE_SHA256='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
SELECTED_IDENTITY_SHA1='FEDCBA9876543210FEDCBA9876543210FEDCBA98'
OTHER_IDENTITY_SHA1='0123456789ABCDEF0123456789ABCDEF01234567'
LOWERCASE_CERTIFICATE_SHA256="$(printf '%s' "$SELECTED_CERTIFICATE_SHA256" | tr '[:upper:]' '[:lower:]')"
# Both valid identities deliberately share one label. The protected SHA-256 pin
# must resolve the selected certificate to its unique SHA-1 codesign selector.
IDENTITY_DETAILS=$'  1) 0123456789ABCDEF0123456789ABCDEF01234567 "Developer ID Application: Fixture LLC (ZYXWV67890)"\n  2) FEDCBA9876543210FEDCBA9876543210FEDCBA98 "Developer ID Application: Fixture LLC (ZYXWV67890)"\n     2 valid identities found'
CERTIFICATE_RECORDS="$OTHER_CERTIFICATE_SHA256"$'\t'"$OTHER_IDENTITY_SHA1"$'\n'"$SELECTED_CERTIFICATE_SHA256"$'\t'"$SELECTED_IDENTITY_SHA1"

clasp_direct_is_valid_identity "$IDENTITY"
[[ "$(clasp_direct_team_id_from_identity "$IDENTITY")" == ZYXWV67890 ]]
expect_failure malformed-identity \
  clasp_direct_is_valid_identity 'Apple Distribution: Fixture LLC (ZYXWV67890)'
clasp_direct_is_valid_sha256 "$SELECTED_CERTIFICATE_SHA256"
clasp_direct_is_valid_sha256 "$LOWERCASE_CERTIFICATE_SHA256"
expect_failure short-fingerprint clasp_direct_is_valid_sha256 '1E6A022B16AC3CCD'

[[ "$(clasp_direct_select_certificate_sha1 \
  "$LOWERCASE_CERTIFICATE_SHA256" "$CERTIFICATE_RECORDS")" == "$SELECTED_IDENTITY_SHA1" ]]
clasp_direct_validate_selected_identity_details \
  "$IDENTITY" "$SELECTED_IDENTITY_SHA1" "$IDENTITY_DETAILS"
expect_failure wrong-fingerprint \
  clasp_direct_select_certificate_sha1 \
  'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB' \
  "$CERTIFICATE_RECORDS"
expect_failure duplicate-pinned-certificate \
  clasp_direct_select_certificate_sha1 \
  "$SELECTED_CERTIFICATE_SHA256" \
  "$CERTIFICATE_RECORDS"$'\n'"$SELECTED_CERTIFICATE_SHA256"$'\t'"$SELECTED_IDENTITY_SHA1"
expect_failure malformed-certificate-record \
  clasp_direct_select_certificate_sha1 \
  "$SELECTED_CERTIFICATE_SHA256" \
  "$CERTIFICATE_RECORDS"$'\nnot-a-certificate-record'
expect_failure selected-certificate-without-private-key \
  clasp_direct_validate_selected_identity_details \
  "$IDENTITY" "$SELECTED_IDENTITY_SHA1" \
  $'  1) 0123456789ABCDEF0123456789ABCDEF01234567 "Developer ID Application: Fixture LLC (ZYXWV67890)"\n     1 valid identities found'
expect_failure duplicate-selected-identity \
  clasp_direct_validate_selected_identity_details \
  "$IDENTITY" "$SELECTED_IDENTITY_SHA1" \
  "$IDENTITY_DETAILS"$'\n  3) FEDCBA9876543210FEDCBA9876543210FEDCBA98 "Developer ID Application: Fixture LLC (ZYXWV67890)"'

echo "direct signing certificate-pin contracts passed"
