#!/usr/bin/env bash
# GitHub expressions below are intentionally checked as literal strings.
# shellcheck disable=SC2016
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
CI="$ROOT_DIR/.github/workflows/ci.yml"
DIRECT="$ROOT_DIR/.github/workflows/direct-release-draft.yml"
STORE="$ROOT_DIR/.github/workflows/app-store-package.yml"
STAGE_APP="$ROOT_DIR/script/stage_app.sh"
DIRECT_PACKAGE="$ROOT_DIR/script/package_direct_release.sh"
DIRECT_VERIFY="$ROOT_DIR/script/verify_direct_release.sh"
INFO_PLIST="$ROOT_DIR/release/Info.plist"

fail() {
  echo "release workflow contract failed: $*" >&2
  exit 1
}

require_literal() {
  local file="$1"
  local expected="$2"
  grep -F -- "$expected" "$file" >/dev/null \
    || fail "${file##*/} is missing: $expected"
}

require_release_test_count() {
  local file="$1"
  local expected_count="$2"
  local count

  count="$(awk '
    /swift test[[:space:]]*\\/ {
      in_test = 1
      release = 0
      next
    }
    in_test && /--configuration release/ { release = 1 }
    in_test && /-Xswiftc/ {
      if (!release) exit 2
      count += 1
      in_test = 0
    }
    END {
      if (in_test) exit 3
      print count + 0
    }
  ' "$file")" || fail "${file##*/} has a non-Release or incomplete swift test command"
  [[ "$count" == "$expected_count" ]] \
    || fail "${file##*/} expected $expected_count Release test commands, found $count"
}

require_release_test_count "$CI" 2
require_release_test_count "$DIRECT" 1
require_release_test_count "$STORE" 1

require_literal "$DIRECT" 'environment: release'

for workflow in "$DIRECT" "$STORE"; do
  require_literal "$workflow" 'cancel-in-progress: false'
  require_literal "$workflow" 'queue: max'
done

for workflow in "$CI" "$DIRECT"; do
  require_literal "$workflow" 'source script/lib/direct_package_resolution.sh'
  require_literal "$workflow" 'clasp_install_direct_package_resolution Package.resolved release/Package.direct.resolved'
  require_literal "$workflow" 'clasp_remove_direct_package_resolution Package.resolved release/Package.direct.resolved'
  require_literal "$workflow" 'clasp_verify_direct_package_resolution Package.resolved release/Package.direct.resolved'
done

require_literal "$CI" 'if ! STORE_LINKS="$(otool -L "$STORE_BIN" 2>&1)"; then'
require_literal "$CI" 'if ! STORE_SYMBOLS="$(nm -u "$STORE_BIN" 2>&1)"; then'
if grep -F 'if otool -L "$STORE_BIN" | grep' "$CI" >/dev/null \
  || grep -F 'if nm -u "$STORE_BIN" | grep' "$CI" >/dev/null; then
  fail "CI binary inspection must not treat inspector failure as a clean result"
fi

require_literal "$STORE" 'persist-credentials: false'
for variable_name in \
  CLASP_APP_STORE_APPLICATION_CERTIFICATE_SHA256 \
  CLASP_APP_STORE_INSTALLER_CERTIFICATE_SHA256; do
  [[ "$(grep -Fc "vars.$variable_name" "$STORE")" == 2 ]] \
    || fail "$variable_name must be required by preflight and injected into packaging"
done

[[ "$(grep -Fc 'vars.DEVELOPER_ID_APPLICATION_CERTIFICATE_SHA256' "$DIRECT")" == 3 ]] \
  || fail "the Developer ID certificate pin must be required by preflight, packaging, and offline verification"
require_literal "$DIRECT" 'clasp_direct_is_valid_sha256 "$DEVELOPER_ID_CERTIFICATE_SHA256"'
require_literal "$DIRECT_PACKAGE" ': "${CLASP_DEVELOPER_ID_APPLICATION_CERTIFICATE_SHA256:?set the exact Developer ID Application certificate SHA-256 fingerprint}"'
require_literal "$DIRECT_PACKAGE" 'SIGN_IDENTITY_SHA1="$(clasp_direct_resolve_identity_sha1'
require_literal "$DIRECT_PACKAGE" '--sign-identity "$SIGN_IDENTITY_SHA1"'
require_literal "$DIRECT_PACKAGE" 'clasp_direct_require_signed_path_certificate'
require_literal "$DIRECT_VERIFY" ': "${CLASP_DEVELOPER_ID_APPLICATION_CERTIFICATE_SHA256:?set the expected Developer ID Application certificate SHA-256 fingerprint}"'
require_literal "$DIRECT_VERIFY" 'clasp_direct_require_signed_path_certificate'
if grep -F 'CLASP_EPHEMERAL_KEYCHAIN_PASSWORD=' "$STORE" >/dev/null; then
  fail "the generated App Store keychain password must stay step-local"
fi

for secret_name in \
  CLASP_APP_STORE_APPLICATION_P12_BASE64 \
  CLASP_APP_STORE_APPLICATION_P12_PASSWORD \
  CLASP_APP_STORE_INSTALLER_P12_BASE64 \
  CLASP_APP_STORE_INSTALLER_P12_PASSWORD \
  CLASP_APP_STORE_PROVISIONING_PROFILE_BASE64; do
  [[ "$(grep -Fc "secrets.$secret_name" "$STORE")" == 1 ]] \
    || fail "$secret_name must be injected only by the credential-import step"
done

for secret_name in \
  DEVELOPER_ID_APPLICATION_P12_BASE64 \
  DEVELOPER_ID_APPLICATION_P12_PASSWORD \
  APP_STORE_CONNECT_API_KEY_P8_BASE64 \
  APP_STORE_CONNECT_KEY_ID \
  APP_STORE_CONNECT_ISSUER_ID \
  SPARKLE_PRIVATE_ED_KEY; do
  [[ "$(grep -Fc "secrets.$secret_name" "$DIRECT")" == 1 ]] \
    || fail "$secret_name must be injected only by its direct-release credential step"
done

require_literal "$DIRECT" '[[ -n "$P12_BASE64" && -n "$P12_PASSWORD" ]]'
require_literal "$DIRECT" '[[ -n "$NOTARY_P8_BASE64" ]]'
require_literal "$DIRECT" '[[ -n "$CLASP_NOTARY_KEY_ID" && -n "$CLASP_NOTARY_ISSUER_ID" ]]'
require_literal "$DIRECT" '[[ -n "$CLASP_SPARKLE_PRIVATE_KEY" ]]'

require_literal "$CI" '[[ ! -e Package.resolved && ! -L Package.resolved ]]'
require_literal "$STORE" '[[ ! -e Package.resolved && ! -L Package.resolved ]]'
require_literal "$STAGE_APP" 'source "$ROOT_DIR/script/lib/direct_package_resolution.sh"'
require_literal "$STAGE_APP" '[[ ! -e "$ROOT_RESOLVED" && ! -L "$ROOT_RESOLVED" ]]'
require_literal "$STAGE_APP" 'clasp_install_direct_package_resolution "$ROOT_RESOLVED" "$DIRECT_RESOLVED"'
require_literal "$STAGE_APP" 'clasp_remove_direct_package_resolution "$ROOT_RESOLVED" "$DIRECT_RESOLVED"'

BUILD_AND_RUN="$ROOT_DIR/script/build_and_run.sh"
[[ "$(grep -Fc '[[ ! -e Package.resolved && ! -L Package.resolved ]]' "$BUILD_AND_RUN")" == 2 ]] \
  || fail "build_and_run.sh must reject regular and dangling root Package.resolved paths before and after testing"

# shellcheck source=../../release/config.env
# shellcheck disable=SC1091
source "$ROOT_DIR/release/config.env"
[[ "$(plutil -extract CFBundleShortVersionString raw -o - "$INFO_PLIST")" == "$CLASP_VERSION" ]] \
  || fail "Info.plist version must match release/config.env"
[[ "$(plutil -extract CFBundleVersion raw -o - "$INFO_PLIST")" == "$CLASP_BUILD_NUMBER" ]] \
  || fail "Info.plist build must match release/config.env"
[[ "$(plutil -extract ITSAppUsesNonExemptEncryption raw -o - "$INFO_PLIST")" == false ]] \
  || fail "Info.plist must declare only exempt operating-system encryption"

echo "release workflow source contracts passed"
