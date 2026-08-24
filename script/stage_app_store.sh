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
APPLICATION_CERTIFICATE_SHA256="${CLASP_APP_STORE_APPLICATION_CERTIFICATE_SHA256:-}"
OUTPUT="$ROOT_DIR/release-output/AppStore/$CLASP_APP_NAME.app"
MANAGED_OUTPUT=""
while (($#)); do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --build-number) BUILD_NUMBER="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    --team-id) TEAM_ID="$2"; shift 2 ;;
    --app-id-prefix) APP_ID_PREFIX="$2"; shift 2 ;;
    --application-identity) APPLICATION_IDENTITY="$2"; shift 2 ;;
    --application-certificate-sha256) APPLICATION_CERTIFICATE_SHA256="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --managed-output) MANAGED_OUTPUT="$2"; shift 2 ;;
    *) app_store_die "unknown argument: $1" ;;
  esac
done

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || app_store_die "version is invalid"
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || app_store_die "build number is invalid"
clasp_prepare_channel_output_root "$ROOT_DIR" app-store
clasp_validate_app_store_wrapper_output "$ROOT_DIR" "$CLASP_APP_NAME" "$OUTPUT" "$MANAGED_OUTPUT"
OUT_PARENT="$(dirname "$OUTPUT")"

"$ROOT_DIR/script/validate_app_store_profile.sh" \
  --profile "$PROFILE" \
  --bundle-id "$CLASP_BUNDLE_ID" \
  --team-id "$TEAM_ID" \
  --app-id-prefix "$APP_ID_PREFIX" \
  --entitlements "$ROOT_DIR/release/Clasp.app-store.entitlements" \
  --application-identity "$APPLICATION_IDENTITY" \
  --application-certificate-sha256 "$APPLICATION_CERTIFICATE_SHA256"

STAGE_DIR="$(mktemp -d "$OUT_PARENT/.clasp-app-store.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
APP="$STAGE_DIR/$CLASP_APP_NAME.app"
NO_REPLACE_MOVER="$STAGE_DIR/clasp-rename-no-replace"
clasp_compile_no_replace_mover "$ROOT_DIR" "$NO_REPLACE_MOVER"

# The shared staging script owns the channel-specific Swift compile flag and
# migration resource. This wrapper intentionally uses only its public CLI.
"$ROOT_DIR/script/stage_app.sh" \
  --channel app-store \
  --configuration release \
  --version "$VERSION" \
  --build-number "$BUILD_NUMBER" \
  --output "$APP" \
  --managed-output app-store \
  --sign-identity "$APPLICATION_IDENTITY" \
  --provisioning-profile "$PROFILE"

SIGNING_ENTITLEMENTS="$STAGE_DIR/signing-entitlements.plist"
cp "$ROOT_DIR/release/Clasp.app-store.entitlements" "$SIGNING_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c \
  "Add :com.apple.application-identifier string $APP_ID_PREFIX.$CLASP_BUNDLE_ID" \
  "$SIGNING_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c \
  "Add :com.apple.developer.team-identifier string $TEAM_ID" \
  "$SIGNING_ENTITLEMENTS"
plutil -convert xml1 "$SIGNING_ENTITLEMENTS"
codesign --force --options runtime --timestamp --generate-entitlement-der \
  --entitlements "$SIGNING_ENTITLEMENTS" \
  --sign "$APPLICATION_IDENTITY" \
  "$APP"

"$ROOT_DIR/script/validate_app_store_artifacts.sh" \
  --app "$APP" \
  --profile "$PROFILE" \
  --team-id "$TEAM_ID" \
  --app-id-prefix "$APP_ID_PREFIX" \
  --application-identity "$APPLICATION_IDENTITY" \
  --application-certificate-sha256 "$APPLICATION_CERTIFICATE_SHA256" \
  --version "$VERSION" \
  --build-number "$BUILD_NUMBER"

clasp_validate_app_store_wrapper_output "$ROOT_DIR" "$CLASP_APP_NAME" "$OUTPUT" "$MANAGED_OUTPUT"
"$NO_REPLACE_MOVER" "$APP" "$OUTPUT"
echo "$OUTPUT"
