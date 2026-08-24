#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck source=../lib/direct_package_resolution.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/script/lib/direct_package_resolution.sh"

TEMP_BASE="${TMPDIR:-/tmp}"
TEMP_DIR="$(mktemp -d "${TEMP_BASE%/}/clasp-direct-resolution.XXXXXX")"
TEMP_DIR="$(cd "$TEMP_DIR" && pwd -P)"
trap 'rm -rf "$TEMP_DIR"' EXIT

REVIEWED="$TEMP_DIR/Package.direct.resolved"
printf '{"fixture":"reviewed"}\n' >"$REVIEWED"

expect_failure() {
  local label="$1"
  shift
  if "$@" >"$TEMP_DIR/$label.stdout" 2>"$TEMP_DIR/$label.stderr"; then
    echo "expected direct-resolution custody failure: $label" >&2
    exit 1
  fi
}

DANGLING="$TEMP_DIR/dangling/Package.resolved"
DANGLING_EXTERNAL="$TEMP_DIR/dangling-external"
mkdir -p "$(dirname "$DANGLING")"
ln -s "$DANGLING_EXTERNAL" "$DANGLING"
expect_failure dangling-install \
  clasp_install_direct_package_resolution "$DANGLING" "$REVIEWED"
[[ -L "$DANGLING" && ! -e "$DANGLING_EXTERNAL" ]]

EXISTING="$TEMP_DIR/existing/Package.resolved"
mkdir -p "$(dirname "$EXISTING")"
printf 'preserve me\n' >"$EXISTING"
expect_failure existing-install \
  clasp_install_direct_package_resolution "$EXISTING" "$REVIEWED"
grep -F 'preserve me' "$EXISTING" >/dev/null

SOURCE_LINK="$TEMP_DIR/Package.direct.link"
ln -s "$REVIEWED" "$SOURCE_LINK"
expect_failure reviewed-symlink \
  clasp_install_direct_package_resolution "$TEMP_DIR/source-link-target" "$SOURCE_LINK"
[[ ! -e "$TEMP_DIR/source-link-target" && ! -L "$TEMP_DIR/source-link-target" ]]

OWNED="$TEMP_DIR/owned/Package.resolved"
mkdir -p "$(dirname "$OWNED")"
clasp_install_direct_package_resolution "$OWNED" "$REVIEWED"
clasp_verify_direct_package_resolution "$OWNED" "$REVIEWED"
clasp_remove_direct_package_resolution "$OWNED" "$REVIEWED"
[[ ! -e "$OWNED" && ! -L "$OWNED" ]]

CHANGED="$TEMP_DIR/changed/Package.resolved"
mkdir -p "$(dirname "$CHANGED")"
clasp_install_direct_package_resolution "$CHANGED" "$REVIEWED"
printf 'changed by another owner\n' >"$CHANGED"
expect_failure changed-cleanup \
  clasp_remove_direct_package_resolution "$CHANGED" "$REVIEWED"
grep -F 'changed by another owner' "$CHANGED" >/dev/null

REPLACED="$TEMP_DIR/replaced/Package.resolved"
REPLACED_EXTERNAL="$TEMP_DIR/replaced-external"
mkdir -p "$(dirname "$REPLACED")"
clasp_install_direct_package_resolution "$REPLACED" "$REVIEWED"
rm -f "$REPLACED"
ln -s "$REPLACED_EXTERNAL" "$REPLACED"
expect_failure replaced-with-symlink \
  clasp_remove_direct_package_resolution "$REPLACED" "$REVIEWED"
[[ -L "$REPLACED" && ! -e "$REPLACED_EXTERNAL" ]]

echo "direct Package.resolved custody fixture tests passed"
