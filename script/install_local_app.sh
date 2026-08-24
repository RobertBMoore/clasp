#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../release/config.env
# shellcheck disable=SC1091
source "$ROOT_DIR/release/config.env"
# shellcheck source=lib/output_custody.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/script/lib/output_custody.sh"

APPLICATIONS_ROOT="/Applications"
SOURCE_APP="$ROOT_DIR/dist/$CLASP_APP_NAME.app"
VALIDATOR="$ROOT_DIR/script/validate_app.sh"
MOVER_OVERRIDE=""
TEST_OVERRIDE=0
while (($#)); do
  case "$1" in
    --applications-root) APPLICATIONS_ROOT="$2"; TEST_OVERRIDE=1; shift 2 ;;
    --source-app) SOURCE_APP="$2"; TEST_OVERRIDE=1; shift 2 ;;
    --validator) VALIDATOR="$2"; TEST_OVERRIDE=1; shift 2 ;;
    --mover) MOVER_OVERRIDE="$2"; TEST_OVERRIDE=1; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
if ((TEST_OVERRIDE)) && [[ "${CLASP_INSTALL_CUSTODY_TESTING:-}" != 1 ]]; then
  echo "install path overrides are available only to the isolated custody fixture" >&2
  exit 2
fi

clasp_require_physical_directory "$APPLICATIONS_ROOT" "Applications root"
clasp_require_physical_directory "$SOURCE_APP" "local app source"
clasp_require_canonical_absolute_path "$VALIDATOR" "local app validator"
[[ -x "$VALIDATOR" && ! -L "$VALIDATOR" ]] || {
  echo "local app validator is missing or unsafe: $VALIDATOR" >&2
  exit 1
}
DESTINATION="$APPLICATIONS_ROOT/$CLASP_APP_NAME.app"
[[ ! -L "$DESTINATION" ]] || {
  echo "refusing to replace a symbolic-link application destination: $DESTINATION" >&2
  exit 1
}
if [[ -e "$DESTINATION" ]]; then
  [[ -d "$DESTINATION" ]] || {
    echo "application destination is not an app directory: $DESTINATION" >&2
    exit 1
  }
  "$VALIDATOR" local "$DESTINATION" >/dev/null || {
    echo "refusing to replace an invalid installed app: $DESTINATION" >&2
    exit 1
  }
fi

INSTALL_STAGE="$(mktemp -d "$APPLICATIONS_ROOT/.clasp-install.XXXXXX")"
CANDIDATE="$INSTALL_STAGE/$CLASP_APP_NAME.app"
PREVIOUS="$INSTALL_STAGE/previous.app"
FAILED_CANDIDATE="$INSTALL_STAGE/failed-candidate.app"
NO_REPLACE_MOVER="$INSTALL_STAGE/clasp-rename-no-replace"
PREVIOUS_TAKEN=0
INSTALL_ATTEMPTED=0
INSTALL_COMMITTED=0
PRESERVE_STAGE=0
CANDIDATE_ID=""

path_identity() {
  stat -f '%d:%i' "$1" 2>/dev/null
}

cleanup() {
  local status=$?
  local candidate_installed=0
  local current_id=""

  [[ ! -e "$PREVIOUS" ]] || PREVIOUS_TAKEN=1
  if ((INSTALL_ATTEMPTED)) \
    && [[ ! -e "$CANDIDATE" && ! -L "$CANDIDATE" && -d "$DESTINATION" && ! -L "$DESTINATION" ]]; then
    current_id="$(path_identity "$DESTINATION" || true)"
    [[ -n "$CANDIDATE_ID" && "$current_id" == "$CANDIDATE_ID" ]] && candidate_installed=1
  fi

  if ((INSTALL_COMMITTED == 0)); then
    if ((candidate_installed)); then
      if ! "$NO_REPLACE_MOVER" "$DESTINATION" "$FAILED_CANDIDATE"; then
        echo "failed to recover the uncommitted install candidate" >&2
        PRESERVE_STAGE=1
        status=1
      fi
    fi
    if ((PREVIOUS_TAKEN)); then
      if [[ ! -e "$DESTINATION" && ! -L "$DESTINATION" ]]; then
        if ! "$NO_REPLACE_MOVER" "$PREVIOUS" "$DESTINATION"; then
          echo "failed to restore the previous installed app" >&2
          PRESERVE_STAGE=1
          status=1
        fi
      else
        echo "preserving the previous app because the install destination is occupied" >&2
        PRESERVE_STAGE=1
        status=1
      fi
    fi
  fi

  if [[ -d "$INSTALL_STAGE" ]]; then
    if ((PRESERVE_STAGE)); then
      echo "preserved install recovery directory: $INSTALL_STAGE" >&2
    else
      rm -rf "$INSTALL_STAGE"
    fi
  fi
  return "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

ditto "$SOURCE_APP" "$CANDIDATE"
"$VALIDATOR" local "$CANDIDATE" >/dev/null
CANDIDATE_ID="$(path_identity "$CANDIDATE")"
[[ -n "$CANDIDATE_ID" ]] || { echo "could not identify staged install candidate" >&2; exit 1; }

if [[ -n "$MOVER_OVERRIDE" ]]; then
  clasp_require_canonical_absolute_path "$MOVER_OVERRIDE" "install mover"
  [[ -x "$MOVER_OVERRIDE" && ! -L "$MOVER_OVERRIDE" ]] || {
    echo "install mover override is missing or unsafe" >&2
    exit 1
  }
  NO_REPLACE_MOVER="$MOVER_OVERRIDE"
else
  clasp_compile_no_replace_mover "$ROOT_DIR" "$NO_REPLACE_MOVER"
fi

if [[ -e "$DESTINATION" ]]; then
  [[ ! -L "$DESTINATION" ]] || { echo "application destination became a symbolic link" >&2; exit 1; }
  "$VALIDATOR" local "$DESTINATION" >/dev/null || {
    echo "installed app changed before replacement" >&2
    exit 1
  }
  "$NO_REPLACE_MOVER" "$DESTINATION" "$PREVIOUS"
  PREVIOUS_TAKEN=1
  "$VALIDATOR" local "$PREVIOUS" >/dev/null || {
    echo "previous installed app changed during replacement" >&2
    exit 1
  }
fi

[[ ! -e "$DESTINATION" && ! -L "$DESTINATION" ]] || {
  echo "application destination became occupied before installation" >&2
  exit 1
}
INSTALL_ATTEMPTED=1
"$NO_REPLACE_MOVER" "$CANDIDATE" "$DESTINATION"
"$VALIDATOR" local "$DESTINATION" >/dev/null
INSTALL_COMMITTED=1
echo "$DESTINATION"
