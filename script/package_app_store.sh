#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../release/config.env
# shellcheck disable=SC1091
source "$ROOT_DIR/release/config.env"
# shellcheck source=lib/app_store_common.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/script/lib/app_store_common.sh"
# shellcheck source=lib/output_custody.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/script/lib/output_custody.sh"

VERSION="$CLASP_VERSION"; BUILD_NUMBER="$CLASP_BUILD_NUMBER"
PROFILE="${CLASP_APP_STORE_PROVISIONING_PROFILE:-}"
TEAM_ID="${CLASP_APP_STORE_TEAM_ID:-}"
APP_ID_PREFIX="${CLASP_APP_STORE_APP_ID_PREFIX:-}"
APPLICATION_IDENTITY="${CLASP_APP_STORE_APPLICATION_IDENTITY:-}"
INSTALLER_IDENTITY="${CLASP_APP_STORE_INSTALLER_IDENTITY:-}"
OUTPUT_DIR="$ROOT_DIR/release-output/AppStore"
while (($#)); do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --build-number) BUILD_NUMBER="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    --team-id) TEAM_ID="$2"; shift 2 ;;
    --app-id-prefix) APP_ID_PREFIX="$2"; shift 2 ;;
    --application-identity) APPLICATION_IDENTITY="$2"; shift 2 ;;
    --installer-identity) INSTALLER_IDENTITY="$2"; shift 2 ;;
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    *) app_store_die "unknown argument: $1" ;;
  esac
done

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || app_store_die "version is invalid"
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || app_store_die "build number is invalid"
clasp_require_canonical_absolute_path "$OUTPUT_DIR" "App Store package output root"
[[ "$OUTPUT_DIR" == "$ROOT_DIR/release-output/AppStore" ]] \
  || app_store_die "output directory must be exactly $ROOT_DIR/release-output/AppStore"
clasp_prepare_channel_output_root "$ROOT_DIR" app-store
app_store_require_identity installer "$INSTALLER_IDENTITY"

FINAL_APP="$OUTPUT_DIR/$CLASP_APP_NAME.app"
FINAL_PACKAGE="$OUTPUT_DIR/$CLASP_APP_NAME-$VERSION-$BUILD_NUMBER-AppStore.pkg"
FINAL_CHECKSUM="$FINAL_PACKAGE.sha256"
clasp_require_fresh_named_output "$OUTPUT_DIR" "$FINAL_APP" "$CLASP_APP_NAME.app" "App Store app"
clasp_require_fresh_named_output \
  "$OUTPUT_DIR" "$FINAL_PACKAGE" "$CLASP_APP_NAME-$VERSION-$BUILD_NUMBER-AppStore.pkg" "App Store package"
clasp_require_fresh_named_output \
  "$OUTPUT_DIR" "$FINAL_CHECKSUM" "$CLASP_APP_NAME-$VERSION-$BUILD_NUMBER-AppStore.pkg.sha256" "App Store checksum"

STAGE_DIR="$(mktemp -d "$OUTPUT_DIR/.clasp-package.XXXXXX")"
APP="$STAGE_DIR/$CLASP_APP_NAME.app"
PACKAGE="$STAGE_DIR/$(basename "$FINAL_PACKAGE")"
CHECKSUM="$PACKAGE.sha256"
NO_REPLACE_MOVER="$STAGE_DIR/clasp-rename-no-replace"
PRESERVE_MARKER="$STAGE_DIR/.clasp-preserve-staging"
PUBLICATION_ATTEMPTED=0
PUBLICATION_SUCCEEDED=0

cleanup() {
  local status=$?
  if [[ -d "$STAGE_DIR" ]]; then
    if [[ -f "$PRESERVE_MARKER" && ! -L "$PRESERVE_MARKER" ]] \
      || ((PUBLICATION_ATTEMPTED && PUBLICATION_SUCCEEDED == 0)); then
      echo "preserved App Store recovery directory: $STAGE_DIR" >&2
    else
      rm -rf "$STAGE_DIR"
    fi
  fi
  return "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
clasp_compile_no_replace_mover "$ROOT_DIR" "$NO_REPLACE_MOVER"

"$ROOT_DIR/script/stage_app_store.sh" \
  --version "$VERSION" \
  --build-number "$BUILD_NUMBER" \
  --profile "$PROFILE" \
  --team-id "$TEAM_ID" \
  --app-id-prefix "$APP_ID_PREFIX" \
  --application-identity "$APPLICATION_IDENTITY" \
  --output "$APP" \
  --managed-output app-store-package

# Apple documents --component mode as the submission-safe productbuild shape
# for a single Mac App Store app. This script only packages; it never uploads.
productbuild \
  --sign "$INSTALLER_IDENTITY" \
  --component "$APP" /Applications \
  "$PACKAGE"

"$ROOT_DIR/script/validate_app_store_artifacts.sh" \
  --app "$APP" \
  --package "$PACKAGE" \
  --profile "$PROFILE" \
  --team-id "$TEAM_ID" \
  --app-id-prefix "$APP_ID_PREFIX" \
  --application-identity "$APPLICATION_IDENTITY" \
  --installer-identity "$INSTALLER_IDENTITY" \
  --version "$VERSION" \
  --build-number "$BUILD_NUMBER"

(
  cd "$STAGE_DIR"
  shasum -a 256 "$(basename "$PACKAGE")" >"$(basename "$CHECKSUM")"
)

clasp_require_fresh_named_output "$OUTPUT_DIR" "$FINAL_APP" "$CLASP_APP_NAME.app" "App Store app"
clasp_require_fresh_named_output \
  "$OUTPUT_DIR" "$FINAL_PACKAGE" "$CLASP_APP_NAME-$VERSION-$BUILD_NUMBER-AppStore.pkg" "App Store package"
clasp_require_fresh_named_output \
  "$OUTPUT_DIR" "$FINAL_CHECKSUM" "$CLASP_APP_NAME-$VERSION-$BUILD_NUMBER-AppStore.pkg.sha256" "App Store checksum"
PUBLICATION_ATTEMPTED=1
"$ROOT_DIR/script/lib/publish_output_set.sh" \
  --mover "$NO_REPLACE_MOVER" \
  --preserve-marker "$PRESERVE_MARKER" \
  app "$APP" "$FINAL_APP" \
  package "$PACKAGE" "$FINAL_PACKAGE" \
  checksum "$CHECKSUM" "$FINAL_CHECKSUM"
PUBLICATION_SUCCEEDED=1
echo "$FINAL_PACKAGE"
