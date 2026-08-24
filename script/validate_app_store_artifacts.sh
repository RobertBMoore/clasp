#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../release/config.env
# shellcheck disable=SC1091
source "$ROOT_DIR/release/config.env"
# shellcheck source=lib/app_store_common.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/script/lib/app_store_common.sh"

APP=""; PACKAGE=""; PROFILE=""; TEAM_ID=""; APP_ID_PREFIX=""
APPLICATION_IDENTITY=""; INSTALLER_IDENTITY=""; VERSION=""; BUILD_NUMBER=""
while (($#)); do
  case "$1" in
    --app) APP="$2"; shift 2 ;;
    --package) PACKAGE="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    --team-id) TEAM_ID="$2"; shift 2 ;;
    --app-id-prefix) APP_ID_PREFIX="$2"; shift 2 ;;
    --application-identity) APPLICATION_IDENTITY="$2"; shift 2 ;;
    --installer-identity) INSTALLER_IDENTITY="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --build-number) BUILD_NUMBER="$2"; shift 2 ;;
    *) app_store_die "unknown argument: $1" ;;
  esac
done

[[ -d "$APP" && "$APP" == *.app ]] || app_store_die "signed App Store .app is required"
[[ -f "$PROFILE" && -n "$TEAM_ID" && -n "$APP_ID_PREFIX" && -n "$APPLICATION_IDENTITY" ]] \
  || app_store_die "profile and exact application identifiers are required"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || app_store_die "version is invalid"
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || app_store_die "build number is invalid"
"$ROOT_DIR/script/lib/validate_public_https_url.sh" "${CLASP_PRIVACY_POLICY_URL:-}" >/dev/null
if [[ -n "$PACKAGE" || -n "$INSTALLER_IDENTITY" ]]; then
  [[ -f "$PACKAGE" && "$PACKAGE" == *.pkg && -n "$INSTALLER_IDENTITY" ]] \
    || app_store_die "package and exact installer identity must be supplied together"
fi

"$ROOT_DIR/script/validate_app_store_profile.sh" \
  --profile "$PROFILE" \
  --bundle-id "$CLASP_BUNDLE_ID" \
  --team-id "$TEAM_ID" \
  --app-id-prefix "$APP_ID_PREFIX" \
  --entitlements "$ROOT_DIR/release/Clasp.app-store.entitlements" \
  --application-identity "$APPLICATION_IDENTITY"

INFO="$APP/Contents/Info.plist"
BIN="$APP/Contents/MacOS/$CLASP_APP_NAME"
EMBEDDED_PROFILE="$APP/Contents/embedded.provisionprofile"
MIGRATION="$APP/Contents/Resources/container-migration.plist"
# The dollar-prefixed token is literal syntax interpreted by Apple's migration engine.
# shellcheck disable=SC2016
EXPECTED_MIGRATION_PATH='${ApplicationSupport}/Personal Notepad'
[[ -f "$INFO" && -x "$BIN" && -f "$EMBEDDED_PROFILE" && -f "$MIGRATION" ]] \
  || app_store_die "App Store bundle structure or required migration resource is incomplete"
cmp -s "$PROFILE" "$EMBEDDED_PROFILE" \
  || app_store_die "embedded provisioning profile is not the validated input profile"
plutil -lint "$INFO" "$MIGRATION" "$APP/Contents/Resources/PrivacyInfo.xcprivacy" >/dev/null
cmp -s "$APP/Contents/Resources/PrivacyInfo.xcprivacy" "$ROOT_DIR/release/PrivacyInfo.xcprivacy" \
  || app_store_die "embedded privacy manifest differs from the reviewed source"
cmp -s "$MIGRATION" "$ROOT_DIR/release/AppStore/container-migration.plist" \
  || app_store_die "embedded container migration manifest differs from the reviewed source"
[[ "$(plutil -extract Move.0.0 raw -o - "$MIGRATION")" == "$EXPECTED_MIGRATION_PATH" ]] \
  || app_store_die "container migration source path is unexpected"
[[ "$(plutil -extract Move.0.1 raw -o - "$MIGRATION")" == "$EXPECTED_MIGRATION_PATH" ]] \
  || app_store_die "container migration destination path is unexpected"
if plutil -extract Move.1 raw -o - "$MIGRATION" >/dev/null 2>&1 \
  || plutil -extract Move.0.2 raw -o - "$MIGRATION" >/dev/null 2>&1; then
  app_store_die "container migration manifest contains unreviewed paths"
fi
[[ "$(plutil -extract CFBundleIdentifier raw -o - "$INFO")" == "$CLASP_BUNDLE_ID" ]] \
  || app_store_die "bundle identifier mismatch"
[[ "$(plutil -extract CFBundleShortVersionString raw -o - "$INFO")" == "$VERSION" ]] \
  || app_store_die "bundle version mismatch"
[[ "$(plutil -extract CFBundleVersion raw -o - "$INFO")" == "$BUILD_NUMBER" ]] \
  || app_store_die "bundle build number mismatch"
[[ "$(plutil -extract LSMinimumSystemVersion raw -o - "$INFO")" == "$CLASP_MIN_MACOS" ]] \
  || app_store_die "minimum macOS version mismatch"
[[ "$(plutil -extract ClaspPrivacyPolicyURL raw -o - "$INFO")" == "$CLASP_PRIVACY_POLICY_URL" ]] \
  || app_store_die "embedded privacy policy URL mismatch"
[[ "$(lipo -archs "$BIN")" == "$CLASP_ARCH" ]] \
  || app_store_die "App Store executable architecture does not match the $CLASP_ARCH release policy"

for update_key in SUFeedURL SUPublicEDKey SURequireSignedFeed SUVerifyUpdateBeforeExtraction; do
  if plutil -extract "$update_key" raw -o - "$INFO" >/dev/null 2>&1; then
    app_store_die "App Store bundle unexpectedly contains $update_key"
  fi
done
[[ ! -e "$APP/Contents/Frameworks/Sparkle.framework" ]] \
  || app_store_die "App Store bundle unexpectedly contains Sparkle.framework"
[[ ! -e "$APP/Contents/Resources/Sparkle-LICENSE.txt" ]] \
  || app_store_die "App Store bundle unexpectedly contains the direct-channel Sparkle license notice"
if otool -L "$BIN" | grep -F 'Sparkle.framework/' >/dev/null; then
  app_store_die "App Store executable unexpectedly links Sparkle"
fi
app_store_require_command nm
if ! APP_STORE_SYMBOLS="$(nm "$BIN" 2>&1)"; then
  app_store_die "could not inspect App Store executable symbols"
fi
if app_store_symbol_list_contains_selection_capture "$APP_STORE_SYMBOLS"; then
  app_store_die "App Store executable contains Accessibility-assisted selection-capture implementation or APIs"
fi

codesign --verify --deep --strict --verbose=2 "$APP"
SIGNING_DETAILS="$(codesign -dvvv "$APP" 2>&1)"
[[ "$(printf '%s\n' "$SIGNING_DETAILS" | awk -F= '/^Authority=/{print substr($0, 11); exit}')" == "$APPLICATION_IDENTITY" ]] \
  || app_store_die "application signature does not use the exact requested identity"
[[ "$(printf '%s\n' "$SIGNING_DETAILS" | awk -F= '/^TeamIdentifier=/{print $2; exit}')" == "$TEAM_ID" ]] \
  || app_store_die "application signature TeamIdentifier mismatch"
[[ "$(printf '%s\n' "$SIGNING_DETAILS" | awk -F= '/^Identifier=/{print $2; exit}')" == "$CLASP_BUNDLE_ID" ]] \
  || app_store_die "code-signing identifier mismatch"

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/clasp-app-store-validation.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
SIGNED_ENTITLEMENTS="$TEMP_DIR/signed-entitlements.plist"
codesign --display --entitlements - --xml "$APP" >"$SIGNED_ENTITLEMENTS" 2>/dev/null
plutil -lint "$SIGNED_ENTITLEMENTS" >/dev/null
signed_entitlement() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$SIGNED_ENTITLEMENTS" 2>/dev/null
}
[[ "$(signed_entitlement 'com.apple.application-identifier')" == "$APP_ID_PREFIX.$CLASP_BUNDLE_ID" ]] \
  || app_store_die "signed application identifier entitlement mismatch"
[[ "$(signed_entitlement 'com.apple.developer.team-identifier')" == "$TEAM_ID" ]] \
  || app_store_die "signed team entitlement mismatch"
[[ "$(signed_entitlement 'com.apple.security.app-sandbox')" == true ]] \
  || app_store_die "signed app does not enable App Sandbox"
[[ "$(signed_entitlement 'com.apple.security.files.user-selected.read-write')" == true ]] \
  || app_store_die "signed app lost user-selected file access"
[[ "$(signed_entitlement 'com.apple.security.get-task-allow' || true)" != true ]] \
  || app_store_die "signed distribution app permits debugger attachment"

if [[ -n "$PACKAGE" ]]; then
  app_store_require_identity installer "$INSTALLER_IDENTITY"
  PACKAGE_SIGNATURE="$TEMP_DIR/package-signature.txt"
  pkgutil --check-signature "$PACKAGE" 2>&1 | tee "$PACKAGE_SIGNATURE"
  grep -F "Status: signed by a certificate trusted by macOS" "$PACKAGE_SIGNATURE" >/dev/null \
    || app_store_die "installer package signature is not trusted"
  grep -F "1. $INSTALLER_IDENTITY" "$PACKAGE_SIGNATURE" >/dev/null \
    || app_store_die "installer package does not use the exact requested identity"
  PAYLOAD_FILES="$TEMP_DIR/package-payload.txt"
  pkgutil --payload-files "$PACKAGE" >"$PAYLOAD_FILES"
  grep -Eq '(^|/)Clasp\.app/Contents/MacOS/Clasp$' "$PAYLOAD_FILES" \
    || app_store_die "installer package does not contain the expected Clasp executable"
  pkgutil --expand "$PACKAGE" "$TEMP_DIR/expanded-package"
  if find "$TEMP_DIR/expanded-package" -type d -name Scripts -print -quit | grep -q .; then
    app_store_die "App Store installer package must not contain install scripts"
  fi
  "$ROOT_DIR/script/lib/verify_packaged_app_payload.sh" "$APP" "$PACKAGE"
fi

echo "validated Mac App Store artifacts: $APP${PACKAGE:+ and $PACKAGE}"
