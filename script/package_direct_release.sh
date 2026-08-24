#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../release/config.env
source "$ROOT_DIR/release/config.env"
# shellcheck source=lib/output_custody.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/script/lib/output_custody.sh"
VERSION="${1:-$CLASP_VERSION}"; BUILD_NUMBER="${2:-$CLASP_BUILD_NUMBER}"
[[ "$#" -le 2 ]] || { echo "usage: $0 [VERSION BUILD_NUMBER]" >&2; exit 2; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "invalid version" >&2; exit 2; }
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]{0,17}$ ]] || { echo "invalid build number" >&2; exit 2; }

OUT="$ROOT_DIR/release-output"
FINAL_APP="$OUT/$CLASP_APP_NAME.app"
FINAL_ZIP="$OUT/$CLASP_APP_NAME-$VERSION-$BUILD_NUMBER.zip"
FINAL_CHECKSUM="$FINAL_ZIP.sha256"
clasp_prepare_channel_output_root "$ROOT_DIR" direct
clasp_require_fresh_named_output "$OUT" "$FINAL_APP" "$CLASP_APP_NAME.app" "direct app"
clasp_require_fresh_named_output \
  "$OUT" "$FINAL_ZIP" "$CLASP_APP_NAME-$VERSION-$BUILD_NUMBER.zip" "direct archive"
clasp_require_fresh_named_output \
  "$OUT" "$FINAL_CHECKSUM" "$CLASP_APP_NAME-$VERSION-$BUILD_NUMBER.zip.sha256" "direct checksum"

: "${CLASP_DEVELOPER_ID_APPLICATION:?set the exact Developer ID Application identity}"
: "${CLASP_UPDATE_FEED_URL:?set the HTTPS appcast URL}"
: "${CLASP_SPARKLE_PUBLIC_KEY:?set the Sparkle EdDSA public key}"
security find-identity -p codesigning -v | grep -Fq "$CLASP_DEVELOPER_ID_APPLICATION" || { echo "signing identity is unavailable" >&2; exit 1; }
STAGE_DIR="$(mktemp -d "$OUT/.clasp-direct-package.XXXXXX")"
APP="$STAGE_DIR/$CLASP_APP_NAME.app"
ZIP="$STAGE_DIR/$CLASP_APP_NAME-$VERSION-$BUILD_NUMBER.zip"
CHECKSUM="$ZIP.sha256"
NO_REPLACE_MOVER="$STAGE_DIR/clasp-rename-no-replace"
PRESERVE_MARKER="$STAGE_DIR/.clasp-preserve-staging"
PUBLICATION_ATTEMPTED=0
PUBLICATION_SUCCEEDED=0

cleanup() {
  local status=$?
  if [[ -d "$STAGE_DIR" ]]; then
    if [[ -f "$PRESERVE_MARKER" && ! -L "$PRESERVE_MARKER" ]] \
      || ((PUBLICATION_ATTEMPTED && PUBLICATION_SUCCEEDED == 0)); then
      echo "preserved release recovery directory: $STAGE_DIR" >&2
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

"$ROOT_DIR/script/stage_app.sh" \
  --channel direct \
  --configuration release \
  --version "$VERSION" \
  --build-number "$BUILD_NUMBER" \
  --output "$APP" \
  --managed-output direct-package \
  --sign-identity "$CLASP_DEVELOPER_ID_APPLICATION"
"$ROOT_DIR/script/validate_app.sh" direct "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
(
  cd "$STAGE_DIR"
  shasum -a 256 "${ZIP##*/}" >"${ZIP##*/}.sha256"
)

# Recheck all destinations immediately before publishing the completed set.
clasp_require_fresh_named_output "$OUT" "$FINAL_APP" "$CLASP_APP_NAME.app" "direct app"
clasp_require_fresh_named_output \
  "$OUT" "$FINAL_ZIP" "$CLASP_APP_NAME-$VERSION-$BUILD_NUMBER.zip" "direct archive"
clasp_require_fresh_named_output \
  "$OUT" "$FINAL_CHECKSUM" "$CLASP_APP_NAME-$VERSION-$BUILD_NUMBER.zip.sha256" "direct checksum"
PUBLICATION_ATTEMPTED=1
"$ROOT_DIR/script/lib/publish_output_set.sh" \
  --mover "$NO_REPLACE_MOVER" \
  --preserve-marker "$PRESERVE_MARKER" \
  app "$APP" "$FINAL_APP" \
  archive "$ZIP" "$FINAL_ZIP" \
  checksum "$CHECKSUM" "$FINAL_CHECKSUM"
PUBLICATION_SUCCEEDED=1
echo "$FINAL_ZIP"
