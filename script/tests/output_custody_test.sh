#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck source=../lib/output_custody.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/script/lib/output_custody.sh"
TEMP_BASE="${TMPDIR:-/tmp}"
TEMP_DIR="$(mktemp -d "${TEMP_BASE%/}/clasp-output-custody.XXXXXX")"
TEMP_DIR="$(cd "$TEMP_DIR" && pwd -P)"
trap 'rm -rf "$TEMP_DIR"' EXIT

expect_failure() {
  local label="$1"
  shift
  if "$@" >"$TEMP_DIR/$label.stdout" 2>"$TEMP_DIR/$label.stderr"; then
    echo "expected output-custody failure: $label" >&2
    exit 1
  fi
}

STAGE_ROOT="$TEMP_DIR/stage-repo"
mkdir -p "$STAGE_ROOT/dist" "$STAGE_ROOT/release-output/AppStore"
clasp_validate_stage_output "$STAGE_ROOT" Clasp local "$STAGE_ROOT/dist/Clasp.app" "" 0
expect_failure arbitrary-output \
  clasp_validate_stage_output "$STAGE_ROOT" Clasp local "$STAGE_ROOT/elsewhere/Clasp.app" "" 0
expect_failure path-escape \
  clasp_validate_stage_output "$STAGE_ROOT" Clasp direct \
    "$STAGE_ROOT/release-output/../escape/Clasp.app" "" 0

mkdir "$STAGE_ROOT/dist/Clasp.app"
expect_failure existing-local \
  clasp_validate_stage_output "$STAGE_ROOT" Clasp local "$STAGE_ROOT/dist/Clasp.app" "" 0
clasp_validate_stage_output "$STAGE_ROOT" Clasp local "$STAGE_ROOT/dist/Clasp.app" "" 1

ln -s "$TEMP_DIR/missing-app" "$STAGE_ROOT/release-output/Clasp.app"
expect_failure dangling-output-symlink \
  clasp_validate_stage_output "$STAGE_ROOT" Clasp direct "$STAGE_ROOT/release-output/Clasp.app" "" 0

SYMLINK_ROOT="$TEMP_DIR/symlink-repo"
mkdir "$SYMLINK_ROOT" "$TEMP_DIR/external-output"
ln -s "$TEMP_DIR/external-output" "$SYMLINK_ROOT/release-output"
expect_failure symlink-output-root clasp_prepare_channel_output_root "$SYMLINK_ROOT" direct

mkdir "$STAGE_ROOT/release-output/.clasp-direct-package.fixture"
clasp_validate_stage_output \
  "$STAGE_ROOT" Clasp direct \
  "$STAGE_ROOT/release-output/.clasp-direct-package.fixture/Clasp.app" direct-package 0
expect_failure managed-output-escape \
  clasp_validate_stage_output \
    "$STAGE_ROOT" Clasp direct "$STAGE_ROOT/release-output/AppStore/Clasp.app" direct-package 0

mkdir "$STAGE_ROOT/release-output/AppStore/.clasp-package.fixture"
clasp_validate_app_store_wrapper_output \
  "$STAGE_ROOT" Clasp \
  "$STAGE_ROOT/release-output/AppStore/.clasp-package.fixture/Clasp.app" app-store-package
expect_failure store-wrapper-arbitrary-output \
  clasp_validate_app_store_wrapper_output \
    "$STAGE_ROOT" Clasp "$STAGE_ROOT/release-output/Clasp.app" ""

NO_REPLACE_MOVER="$TEMP_DIR/clasp-rename-no-replace"
clasp_compile_no_replace_mover "$ROOT_DIR" "$NO_REPLACE_MOVER"
mkdir "$TEMP_DIR/move-source.app" "$TEMP_DIR/move-existing.app"
touch "$TEMP_DIR/move-existing.app/sentinel"
expect_failure exclusive-existing-directory \
  "$NO_REPLACE_MOVER" "$TEMP_DIR/move-source.app" "$TEMP_DIR/move-existing.app"
[[ -d "$TEMP_DIR/move-source.app" && -f "$TEMP_DIR/move-existing.app/sentinel" ]]
[[ ! -e "$TEMP_DIR/move-existing.app/move-source.app" ]]

mkdir "$TEMP_DIR/move-dangling-source.app"
ln -s "$TEMP_DIR/missing-move-target" "$TEMP_DIR/move-dangling-target.app"
expect_failure exclusive-dangling-symlink \
  "$NO_REPLACE_MOVER" "$TEMP_DIR/move-dangling-source.app" "$TEMP_DIR/move-dangling-target.app"
[[ -d "$TEMP_DIR/move-dangling-source.app" && -L "$TEMP_DIR/move-dangling-target.app" ]]

mkdir "$TEMP_DIR/move-fresh-source.app"
"$NO_REPLACE_MOVER" "$TEMP_DIR/move-fresh-source.app" "$TEMP_DIR/move-fresh-target.app"
[[ ! -e "$TEMP_DIR/move-fresh-source.app" && -d "$TEMP_DIR/move-fresh-target.app" ]]

make_package_fixture() {
  local label="$1"
  PACKAGE_ROOT="$TEMP_DIR/package-$label"
  mkdir -p "$PACKAGE_ROOT/script/lib" "$PACKAGE_ROOT/release"
  cp "$ROOT_DIR/script/package_direct_release.sh" "$PACKAGE_ROOT/script/package_direct_release.sh"
  cp "$ROOT_DIR/script/lib/direct_signing.sh" "$PACKAGE_ROOT/script/lib/direct_signing.sh"
  cp "$ROOT_DIR/script/lib/output_custody.sh" "$PACKAGE_ROOT/script/lib/output_custody.sh"
  cp "$ROOT_DIR/release/config.env" "$PACKAGE_ROOT/release/config.env"
  chmod +x "$PACKAGE_ROOT/script/package_direct_release.sh"
}

run_package() {
  CLASP_DEVELOPER_ID_APPLICATION='Developer ID Application: Fixture' \
  CLASP_DEVELOPER_ID_APPLICATION_CERTIFICATE_SHA256='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' \
  CLASP_UPDATE_FEED_URL='https://example.invalid/appcast.xml' \
  CLASP_SPARKLE_PUBLIC_KEY='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=' \
    "$PACKAGE_ROOT/script/package_direct_release.sh" 1.0.0 7
}

make_package_fixture existing-app
mkdir -p "$PACKAGE_ROOT/release-output/Clasp.app"
expect_failure package-existing-app run_package
[[ -d "$PACKAGE_ROOT/release-output/Clasp.app" ]]

make_package_fixture existing-archive
mkdir "$PACKAGE_ROOT/release-output"
touch "$PACKAGE_ROOT/release-output/Clasp-1.0.0-7.zip"
expect_failure package-existing-archive run_package
[[ -f "$PACKAGE_ROOT/release-output/Clasp-1.0.0-7.zip" ]]

make_package_fixture existing-checksum
mkdir "$PACKAGE_ROOT/release-output"
touch "$PACKAGE_ROOT/release-output/Clasp-1.0.0-7.zip.sha256"
expect_failure package-existing-checksum run_package
[[ -f "$PACKAGE_ROOT/release-output/Clasp-1.0.0-7.zip.sha256" ]]

make_package_fixture package-symlink
mkdir "$TEMP_DIR/package-external"
ln -s "$TEMP_DIR/package-external" "$PACKAGE_ROOT/release-output"
expect_failure package-output-root-symlink run_package
[[ -L "$PACKAGE_ROOT/release-output" ]]

make_package_fixture missing-certificate-pin
expect_failure package-missing-certificate-pin \
  env \
    CLASP_DEVELOPER_ID_APPLICATION='Developer ID Application: Fixture LLC (ZYXWV67890)' \
    CLASP_UPDATE_FEED_URL='https://example.invalid/appcast.xml' \
    CLASP_SPARKLE_PUBLIC_KEY='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=' \
    "$PACKAGE_ROOT/script/package_direct_release.sh" 1.0.0 7

make_package_fixture unsafe-version
expect_failure package-unsafe-version \
  env \
    CLASP_DEVELOPER_ID_APPLICATION='Developer ID Application: Fixture' \
    CLASP_DEVELOPER_ID_APPLICATION_CERTIFICATE_SHA256='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' \
    CLASP_UPDATE_FEED_URL='https://example.invalid/appcast.xml' \
    CLASP_SPARKLE_PUBLIC_KEY='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=' \
    "$PACKAGE_ROOT/script/package_direct_release.sh" '1.0.0/../../escape' 7
[[ ! -e "$PACKAGE_ROOT/release-output" ]]

make_store_package_fixture() {
  local label="$1"
  STORE_ROOT="$TEMP_DIR/store-package-$label"
  mkdir -p "$STORE_ROOT/script/lib" "$STORE_ROOT/release"
  cp "$ROOT_DIR/script/package_app_store.sh" "$STORE_ROOT/script/package_app_store.sh"
  cp "$ROOT_DIR/script/lib/app_store_common.sh" "$STORE_ROOT/script/lib/app_store_common.sh"
  cp "$ROOT_DIR/script/lib/output_custody.sh" "$STORE_ROOT/script/lib/output_custody.sh"
  cp "$ROOT_DIR/release/config.env" "$STORE_ROOT/release/config.env"
  chmod +x "$STORE_ROOT/script/package_app_store.sh"
}

run_store_package() {
  "$STORE_ROOT/script/package_app_store.sh" --version 1.0.0 --build-number 7
}

make_store_package_fixture existing-app
mkdir -p "$STORE_ROOT/release-output/AppStore/Clasp.app"
expect_failure store-package-existing-app run_store_package
[[ -d "$STORE_ROOT/release-output/AppStore/Clasp.app" ]]

make_store_package_fixture existing-package
mkdir -p "$STORE_ROOT/release-output/AppStore"
touch "$STORE_ROOT/release-output/AppStore/Clasp-1.0.0-7-AppStore.pkg"
expect_failure store-package-existing-package run_store_package
[[ -f "$STORE_ROOT/release-output/AppStore/Clasp-1.0.0-7-AppStore.pkg" ]]

make_store_package_fixture existing-checksum
mkdir -p "$STORE_ROOT/release-output/AppStore"
touch "$STORE_ROOT/release-output/AppStore/Clasp-1.0.0-7-AppStore.pkg.sha256"
expect_failure store-package-existing-checksum run_store_package
[[ -f "$STORE_ROOT/release-output/AppStore/Clasp-1.0.0-7-AppStore.pkg.sha256" ]]

make_store_package_fixture symlink-root
mkdir "$TEMP_DIR/store-package-external"
ln -s "$TEMP_DIR/store-package-external" "$STORE_ROOT/release-output"
expect_failure store-package-symlink-root run_store_package
[[ -L "$STORE_ROOT/release-output" ]]

make_store_package_fixture unsafe-output
expect_failure store-package-unsafe-output \
  "$STORE_ROOT/script/package_app_store.sh" \
    --version 1.0.0 \
    --build-number 7 \
    --output-dir "$STORE_ROOT/escape"
[[ ! -e "$STORE_ROOT/escape" ]]

echo "output custody fixture tests passed"
