#!/usr/bin/env bash
# GitHub expressions below are intentionally checked as literal strings.
# shellcheck disable=SC2016
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
CI="$ROOT_DIR/.github/workflows/ci.yml"
DIRECT="$ROOT_DIR/.github/workflows/direct-release-draft.yml"
STORE="$ROOT_DIR/.github/workflows/app-store-package.yml"
STAGE_APP="$ROOT_DIR/script/stage_app.sh"

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

require_literal "$CI" '[[ ! -e Package.resolved && ! -L Package.resolved ]]'
require_literal "$STORE" '[[ ! -e Package.resolved && ! -L Package.resolved ]]'
require_literal "$STAGE_APP" 'source "$ROOT_DIR/script/lib/direct_package_resolution.sh"'
require_literal "$STAGE_APP" '[[ ! -e "$ROOT_RESOLVED" && ! -L "$ROOT_RESOLVED" ]]'
require_literal "$STAGE_APP" 'clasp_install_direct_package_resolution "$ROOT_RESOLVED" "$DIRECT_RESOLVED"'
require_literal "$STAGE_APP" 'clasp_remove_direct_package_resolution "$ROOT_RESOLVED" "$DIRECT_RESOLVED"'

BUILD_AND_RUN="$ROOT_DIR/script/build_and_run.sh"
[[ "$(grep -Fc '[[ ! -e Package.resolved && ! -L Package.resolved ]]' "$BUILD_AND_RUN")" == 2 ]] \
  || fail "build_and_run.sh must reject regular and dangling root Package.resolved paths before and after testing"

echo "release workflow source contracts passed"
