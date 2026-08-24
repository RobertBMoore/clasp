#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck source=../lib/output_custody.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/script/lib/output_custody.sh"
INSTALLER="$ROOT_DIR/script/install_local_app.sh"
PUBLISHER="$ROOT_DIR/script/lib/publish_output_set.sh"
FAILING_MOVER="$ROOT_DIR/script/tests/fixtures/failing-exclusive-mover.sh"
TEMP_BASE="${TMPDIR:-/tmp}"
TEMP_DIR="$(mktemp -d "${TEMP_BASE%/}/clasp-install-publish-custody.XXXXXX")"
TEMP_DIR="$(cd "$TEMP_DIR" && pwd -P)"
trap 'rm -rf "$TEMP_DIR"' EXIT

REAL_MOVER="$TEMP_DIR/clasp-rename-no-replace"
clasp_compile_no_replace_mover "$ROOT_DIR" "$REAL_MOVER"

expect_failure() {
  local label="$1"
  shift
  if "$@" >"$TEMP_DIR/$label.stdout" 2>"$TEMP_DIR/$label.stderr"; then
    echo "expected custody failure: $label" >&2
    exit 1
  fi
}

run_install() {
  local source_app="$1"
  local applications_root="$2"
  shift 2
  CLASP_INSTALL_CUSTODY_TESTING=1 "$INSTALLER" \
    --source-app "$source_app" \
    --applications-root "$applications_root" \
    --validator /usr/bin/true \
    "$@"
}

FRESH_ROOT="$TEMP_DIR/fresh/Applications"
FRESH_SOURCE="$TEMP_DIR/fresh/source/Clasp.app"
mkdir -p "$FRESH_ROOT" "$FRESH_SOURCE"
touch "$FRESH_SOURCE/new-marker"
run_install "$FRESH_SOURCE" "$FRESH_ROOT" >/dev/null
[[ -f "$FRESH_ROOT/Clasp.app/new-marker" ]]

REPLACE_ROOT="$TEMP_DIR/replace/Applications"
REPLACE_SOURCE="$TEMP_DIR/replace/source/Clasp.app"
mkdir -p "$REPLACE_ROOT/Clasp.app" "$REPLACE_SOURCE"
touch "$REPLACE_ROOT/Clasp.app/old-marker" "$REPLACE_SOURCE/new-marker"
run_install "$REPLACE_SOURCE" "$REPLACE_ROOT" >/dev/null
[[ -f "$REPLACE_ROOT/Clasp.app/new-marker" && ! -e "$REPLACE_ROOT/Clasp.app/old-marker" ]]

SYMLINK_ROOT="$TEMP_DIR/symlink/Applications"
SYMLINK_SOURCE="$TEMP_DIR/symlink/source/Clasp.app"
mkdir -p "$SYMLINK_ROOT" "$SYMLINK_SOURCE"
ln -s "$TEMP_DIR/missing-installed-app" "$SYMLINK_ROOT/Clasp.app"
expect_failure install-dangling-symlink run_install "$SYMLINK_SOURCE" "$SYMLINK_ROOT"
[[ -L "$SYMLINK_ROOT/Clasp.app" ]]

RACE_ROOT="$TEMP_DIR/race/Applications"
RACE_SOURCE="$TEMP_DIR/race/source/Clasp.app"
RACE_STATE="$TEMP_DIR/race-mover-state"
mkdir -p "$RACE_ROOT/Clasp.app" "$RACE_SOURCE"
touch "$RACE_ROOT/Clasp.app/old-marker" "$RACE_SOURCE/new-marker"
expect_failure install-destination-race \
  env \
    CLASP_INSTALL_CUSTODY_TESTING=1 \
    CLASP_TEST_REAL_MOVER="$REAL_MOVER" \
    CLASP_TEST_MOVER_STATE="$RACE_STATE" \
    CLASP_TEST_MOVER_MODE=destination-race \
    "$INSTALLER" \
      --source-app "$RACE_SOURCE" \
      --applications-root "$RACE_ROOT" \
      --validator /usr/bin/true \
      --mover "$FAILING_MOVER"
[[ -f "$RACE_ROOT/Clasp.app/late-destination" ]]
RACE_RECOVERY="$(sed -n 's/^preserved install recovery directory: //p' "$TEMP_DIR/install-destination-race.stderr" | tail -1)"
[[ -n "$RACE_RECOVERY" && -f "$RACE_RECOVERY/previous.app/old-marker" ]]

RESTORE_ROOT="$TEMP_DIR/restore/Applications"
RESTORE_SOURCE="$TEMP_DIR/restore/source/Clasp.app"
RESTORE_STATE="$TEMP_DIR/restore-mover-state"
mkdir -p "$RESTORE_ROOT/Clasp.app" "$RESTORE_SOURCE"
touch "$RESTORE_ROOT/Clasp.app/old-marker" "$RESTORE_SOURCE/new-marker"
expect_failure install-restore-failure \
  env \
    CLASP_INSTALL_CUSTODY_TESTING=1 \
    CLASP_TEST_REAL_MOVER="$REAL_MOVER" \
    CLASP_TEST_MOVER_STATE="$RESTORE_STATE" \
    CLASP_TEST_MOVER_MODE=restore-failure \
    "$INSTALLER" \
      --source-app "$RESTORE_SOURCE" \
      --applications-root "$RESTORE_ROOT" \
      --validator /usr/bin/true \
      --mover "$FAILING_MOVER"
[[ ! -e "$RESTORE_ROOT/Clasp.app" && ! -L "$RESTORE_ROOT/Clasp.app" ]]
RESTORE_RECOVERY="$(sed -n 's/^preserved install recovery directory: //p' "$TEMP_DIR/install-restore-failure.stderr" | tail -1)"
[[ -n "$RESTORE_RECOVERY" && -f "$RESTORE_RECOVERY/previous.app/old-marker" ]]

run_publish_failure() {
  local mode="$1"
  local fixture="$TEMP_DIR/publish-$mode"
  local state="$fixture/mover-state"
  mkdir -p "$fixture/stage" "$fixture/final"
  touch "$fixture/stage/one" "$fixture/stage/two" "$fixture/stage/three"
  expect_failure "publish-$mode" \
    env \
      CLASP_TEST_REAL_MOVER="$REAL_MOVER" \
      CLASP_TEST_MOVER_STATE="$state" \
      CLASP_TEST_MOVER_MODE="$mode" \
      "$PUBLISHER" \
        --mover "$FAILING_MOVER" \
        --preserve-marker "$fixture/stage/preserve" \
        one "$fixture/stage/one" "$fixture/final/one" \
        two "$fixture/stage/two" "$fixture/final/two" \
        three "$fixture/stage/three" "$fixture/final/three"
  PUBLISH_FIXTURE="$fixture"
}

run_publish_failure publish-second-failure
[[ -f "$PUBLISH_FIXTURE/stage/one" && -f "$PUBLISH_FIXTURE/stage/two" && -f "$PUBLISH_FIXTURE/stage/three" ]]
[[ ! -e "$PUBLISH_FIXTURE/final/one" && ! -e "$PUBLISH_FIXTURE/final/two" && ! -e "$PUBLISH_FIXTURE/final/three" ]]
[[ ! -e "$PUBLISH_FIXTURE/stage/preserve" ]]

run_publish_failure publish-third-failure
[[ -f "$PUBLISH_FIXTURE/stage/one" && -f "$PUBLISH_FIXTURE/stage/two" && -f "$PUBLISH_FIXTURE/stage/three" ]]
[[ ! -e "$PUBLISH_FIXTURE/final/one" && ! -e "$PUBLISH_FIXTURE/final/two" && ! -e "$PUBLISH_FIXTURE/final/three" ]]

run_publish_failure publish-rollback-failure
[[ -f "$PUBLISH_FIXTURE/final/one" && ! -e "$PUBLISH_FIXTURE/stage/one" ]]
[[ -f "$PUBLISH_FIXTURE/stage/two" && -f "$PUBLISH_FIXTURE/stage/three" ]]
[[ -f "$PUBLISH_FIXTURE/stage/preserve" && ! -L "$PUBLISH_FIXTURE/stage/preserve" ]]

echo "install and partial-publication custody fixture tests passed"
