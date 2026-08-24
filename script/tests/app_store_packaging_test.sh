#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT_DIR/script/lib/validate_app_store_profile_payload.sh"
SIGNED_VALIDATOR="$ROOT_DIR/script/validate_app_store_profile.sh"
PAYLOAD_VALIDATOR="$ROOT_DIR/script/lib/verify_packaged_app_payload.sh"
COMMON="$ROOT_DIR/script/lib/app_store_common.sh"
STAGER="$ROOT_DIR/script/stage_app.sh"
ARTIFACT_VALIDATOR="$ROOT_DIR/script/validate_app_store_artifacts.sh"
FIXTURE="$ROOT_DIR/script/tests/fixtures/app-store-profile-valid.plist"
ENTITLEMENTS="$ROOT_DIR/release/Clasp.app-store.entitlements"
METADATA="$ROOT_DIR/release/AppStore/METADATA_DRAFT.md"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/clasp-app-store-tests.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
# shellcheck source=../lib/app_store_common.sh
# shellcheck disable=SC1091
source "$COMMON"

validate_payload() {
  "$VALIDATOR" \
    --profile-plist "$1" \
    --bundle-id com.robertmoore.personalnotepad \
    --team-id ZYXWV67890 \
    --app-id-prefix ABCDE12345 \
    --entitlements "${2:-$ENTITLEMENTS}"
}

expect_failure() {
  local label="$1"
  shift
  if "$@" >"$TEMP_DIR/$label.stdout" 2>"$TEMP_DIR/$label.stderr"; then
    echo "expected failure: $label" >&2
    exit 1
  fi
}

require_non_root_readable_fixture() {
  (app_store_require_non_root_readable_bundle "$1")
}

plutil -lint "$FIXTURE" "$ENTITLEMENTS" >/dev/null
grep -F 'app_store_clear_profile_download_xattrs "$APP/Contents/embedded.provisionprofile"' "$STAGER" >/dev/null
grep -F 'chmod 0644 "$APP/Contents/embedded.provisionprofile"' "$STAGER" >/dev/null
grep -F 'app_store_require_non_root_readable_bundle "$APP"' "$ARTIFACT_VALIDATOR" >/dev/null
validate_payload "$FIXTURE" >/dev/null
grep -F 'selected-content capture through macOS Services' "$METADATA" >/dev/null
grep -F 'omits Accessibility-assisted selection shortcuts' "$METADATA" >/dev/null
if grep -F 'selection capture permissions' "$METADATA" >/dev/null; then
  echo "App Store review notes still describe a permission flow absent from the Store build" >&2
  exit 1
fi

FIXTURE_INSTALLER_IDENTITY='3rd Party Mac Developer Installer: Fixture LLC (ZYXWV67890)'
FIXTURE_INSTALLER_SHA256='D73319AA7B859462C3B26E6B1315F8D246F6FD157274ECCBF8C73A0293F03D9E'
VALID_PACKAGE_SIGNATURE=$'Package "fixture.pkg":\n   Status: signed by a developer certificate issued by Apple (Development)\n   Certificate Chain:\n    1. 3rd Party Mac Developer Installer: Fixture LLC (ZYXWV67890)\n       Expires: 2027-08-24 18:45:06 +0000\n       SHA256 Fingerprint:\n           D7 33 19 AA 7B 85 94 62 C3 B2 6E 6B 13 15 F8 D2 46 F6 FD 15 72 74\n           EC CB F8 C7 3A 02 93 F0 3D 9E\n       ------------------------------------------------------------------------\n    2. Apple Worldwide Developer Relations Certification Authority'
app_store_validate_package_signature_details \
  "$VALID_PACKAGE_SIGNATURE" "$FIXTURE_INSTALLER_IDENTITY" "$FIXTURE_INSTALLER_SHA256"
TRUSTED_PACKAGE_SIGNATURE="${VALID_PACKAGE_SIGNATURE/signed by a developer certificate issued by Apple \(Development\)/signed by a certificate trusted by macOS}"
app_store_validate_package_signature_details \
  "$TRUSTED_PACKAGE_SIGNATURE" "$FIXTURE_INSTALLER_IDENTITY" "$FIXTURE_INSTALLER_SHA256"
expect_failure duplicate-package-status \
  app_store_validate_package_signature_details \
  "$VALID_PACKAGE_SIGNATURE"$'\n   Status: no signature' \
  "$FIXTURE_INSTALLER_IDENTITY" "$FIXTURE_INSTALLER_SHA256"
expect_failure wrong-package-identity \
  app_store_validate_package_signature_details \
  "$VALID_PACKAGE_SIGNATURE" \
  '3rd Party Mac Developer Installer: Wrong LLC (ZYXWV67890)' \
  "$FIXTURE_INSTALLER_SHA256"
expect_failure wrong-package-fingerprint \
  app_store_validate_package_signature_details \
  "$VALID_PACKAGE_SIGNATURE" "$FIXTURE_INSTALLER_IDENTITY" \
  'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
expect_failure duplicate-package-leaf \
  app_store_validate_package_signature_details \
  "$VALID_PACKAGE_SIGNATURE"$'\n    1. 3rd Party Mac Developer Installer: Fixture LLC (ZYXWV67890)' \
  "$FIXTURE_INSTALLER_IDENTITY" "$FIXTURE_INSTALLER_SHA256"
NOISY_PACKAGE_FINGERPRINT="${VALID_PACKAGE_SIGNATURE/D7 33 19 AA/D7 33 19! AA}"
expect_failure noisy-package-fingerprint \
  app_store_validate_package_signature_details \
  "$NOISY_PACKAGE_FINGERPRINT" "$FIXTURE_INSTALLER_IDENTITY" \
  "$FIXTURE_INSTALLER_SHA256"
LONG_PACKAGE_FINGERPRINT="${VALID_PACKAGE_SIGNATURE/EC CB F8 C7 3A 02 93 F0 3D 9E/EC CB F8 C7 3A 02 93 F0 3D 9E 00}"
expect_failure long-package-fingerprint \
  app_store_validate_package_signature_details \
  "$LONG_PACKAGE_FINGERPRINT" "$FIXTURE_INSTALLER_IDENTITY" \
  "$FIXTURE_INSTALLER_SHA256"

app_store_profile_xattrs_are_safe ""
app_store_profile_xattrs_are_safe $'com.apple.macl\ncom.apple.provenance'
if app_store_profile_xattrs_are_safe $'com.apple.provenance\ncom.example.fixture'; then
  echo "unexpected provisioning-profile xattr was accepted" >&2
  exit 1
fi
PROFILE_XATTR_FIXTURE="$TEMP_DIR/profile-xattrs"
printf 'fixture' >"$PROFILE_XATTR_FIXTURE"
xattr -w com.example.clasp-fixture value "$PROFILE_XATTR_FIXTURE"
app_store_clear_profile_download_xattrs "$PROFILE_XATTR_FIXTURE"
app_store_profile_xattrs_are_safe "$(xattr "$PROFILE_XATTR_FIXTURE")"

READABLE_APP_FIXTURE="$TEMP_DIR/non-root-readable/Clasp.app"
mkdir -p "$READABLE_APP_FIXTURE/Contents/Resources"
printf 'fixture profile\n' >"$READABLE_APP_FIXTURE/Contents/embedded.provisionprofile"
chmod 0755 "$READABLE_APP_FIXTURE" "$READABLE_APP_FIXTURE/Contents" "$READABLE_APP_FIXTURE/Contents/Resources"
chmod 0644 "$READABLE_APP_FIXTURE/Contents/embedded.provisionprofile"
require_non_root_readable_fixture "$READABLE_APP_FIXTURE"
chmod 0600 "$READABLE_APP_FIXTURE/Contents/embedded.provisionprofile"
expect_failure non-root-unreadable-file \
  require_non_root_readable_fixture "$READABLE_APP_FIXTURE"
chmod 0644 "$READABLE_APP_FIXTURE/Contents/embedded.provisionprofile"
chmod 0700 "$READABLE_APP_FIXTURE/Contents/Resources"
expect_failure non-root-untraversable-directory \
  require_non_root_readable_fixture "$READABLE_APP_FIXTURE"

SAFE_APP_STORE_SYMBOLS=$'                 U _NSAccessibilityPostNotification\n0000000100001000 T _$s15PersonalNotepad24LocalConfirmationPresenterC'
if app_store_symbol_list_contains_selection_capture "$SAFE_APP_STORE_SYMBOLS"; then
  echo "ordinary UI accessibility symbols must remain allowed" >&2
  exit 1
fi
for forbidden_symbol in \
  _CGPreflightPostEventAccess \
  _CGRequestPostEventAccess \
  _CGEventCreateKeyboardEvent \
  _CGEventPost \
  SelectionCaptureService; do
  if ! app_store_symbol_list_contains_selection_capture "                 U $forbidden_symbol"; then
    echo "selection-capture symbol was not rejected: $forbidden_symbol" >&2
    exit 1
  fi
done

BAD_APP_ID="$TEMP_DIR/bad-app-id.plist"
cp "$FIXTURE" "$BAD_APP_ID"
/usr/libexec/PlistBuddy -c \
  'Set :Entitlements:com.apple.application-identifier ABCDE12345.com.example.wrong' \
  "$BAD_APP_ID"
expect_failure bad-app-id validate_payload "$BAD_APP_ID"

EXPIRED="$TEMP_DIR/expired.plist"
cp "$FIXTURE" "$EXPIRED"
plutil -replace ExpirationDate -date '2000-01-01T00:00:00Z' "$EXPIRED"
expect_failure expired validate_payload "$EXPIRED"

WRONG_PLATFORM="$TEMP_DIR/wrong-platform.plist"
cp "$FIXTURE" "$WRONG_PLATFORM"
/usr/libexec/PlistBuddy -c 'Set :Platform:0 iOS' "$WRONG_PLATFORM"
expect_failure wrong-platform validate_payload "$WRONG_PLATFORM"

DEVICE_BOUND="$TEMP_DIR/device-bound.plist"
cp "$FIXTURE" "$DEVICE_BOUND"
/usr/libexec/PlistBuddy -c 'Add :ProvisionedDevices array' "$DEVICE_BOUND"
/usr/libexec/PlistBuddy -c 'Add :ProvisionedDevices:0 string TEST-MAC' "$DEVICE_BOUND"
expect_failure device-bound validate_payload "$DEVICE_BOUND"

UNSANDBOXED="$TEMP_DIR/unsandboxed.entitlements"
cp "$ENTITLEMENTS" "$UNSANDBOXED"
/usr/libexec/PlistBuddy -c 'Set :com.apple.security.app-sandbox false' "$UNSANDBOXED"
expect_failure unsandboxed validate_payload "$FIXTURE" "$UNSANDBOXED"

expect_failure wrong-prefix \
  "$VALIDATOR" \
  --profile-plist "$FIXTURE" \
  --bundle-id com.robertmoore.personalnotepad \
  --team-id ZYXWV67890 \
  --app-id-prefix ZZZZZ99999 \
  --entitlements "$ENTITLEMENTS"

# A decoded XML fixture must never be accepted by the production CMS gate.
expect_failure unsigned-profile \
  "$SIGNED_VALIDATOR" \
  --profile "$FIXTURE" \
  --bundle-id com.robertmoore.personalnotepad \
  --team-id ZYXWV67890 \
  --app-id-prefix ABCDE12345 \
  --entitlements "$ENTITLEMENTS" \
  --application-identity 'Apple Distribution: Fixture (ZYXWV67890)'

[[ -d "$ROOT_DIR/dist/Clasp.app" ]] || {
  echo "dist/Clasp.app is required for package payload fixture tests" >&2
  exit 1
}
PAYLOAD_APP="$TEMP_DIR/Clasp.app"
PAYLOAD_PACKAGE="$TEMP_DIR/Clasp-fixture.pkg"
ditto "$ROOT_DIR/dist/Clasp.app" "$PAYLOAD_APP"
productbuild --component "$PAYLOAD_APP" /Applications "$PAYLOAD_PACKAGE" >/dev/null
expect_failure unsigned-package-signature \
  app_store_verify_package_signature \
  "$PAYLOAD_PACKAGE" "$FIXTURE_INSTALLER_IDENTITY" "$FIXTURE_INSTALLER_SHA256"
"$PAYLOAD_VALIDATOR" "$PAYLOAD_APP" "$PAYLOAD_PACKAGE" >/dev/null

plutil -replace CFBundleVersion -string 999 "$PAYLOAD_APP/Contents/Info.plist"
expect_failure payload-mismatch "$PAYLOAD_VALIDATOR" "$PAYLOAD_APP" "$PAYLOAD_PACKAGE"

MODE_APP="$TEMP_DIR/mode/Clasp.app"
MODE_PACKAGE="$TEMP_DIR/mode/Clasp.pkg"
mkdir -p "$TEMP_DIR/mode"
ditto "$ROOT_DIR/dist/Clasp.app" "$MODE_APP"
productbuild --component "$MODE_APP" /Applications "$MODE_PACKAGE" >/dev/null
chmod 600 "$MODE_APP/Contents/Info.plist"
expect_failure payload-mode-mismatch "$PAYLOAD_VALIDATOR" "$MODE_APP" "$MODE_PACKAGE"

XATTR_APP="$TEMP_DIR/xattr/Clasp.app"
XATTR_PACKAGE="$TEMP_DIR/xattr/Clasp.pkg"
mkdir -p "$TEMP_DIR/xattr"
ditto "$ROOT_DIR/dist/Clasp.app" "$XATTR_APP"
productbuild --component "$XATTR_APP" /Applications "$XATTR_PACKAGE" >/dev/null
xattr -w com.example.clasp-fixture changed-after-packaging "$XATTR_APP/Contents/Info.plist"
expect_failure payload-xattr-mismatch "$PAYLOAD_VALIDATOR" "$XATTR_APP" "$XATTR_PACKAGE"

SYMLINK_APP="$TEMP_DIR/symlink/Clasp.app"
SYMLINK_PACKAGE="$TEMP_DIR/symlink/Clasp.pkg"
mkdir -p "$TEMP_DIR/symlink"
ditto "$ROOT_DIR/dist/Clasp.app" "$SYMLINK_APP"
printf 'same fixture bytes\n' > "$SYMLINK_APP/Contents/Resources/symlink-a.txt"
cp "$SYMLINK_APP/Contents/Resources/symlink-a.txt" "$SYMLINK_APP/Contents/Resources/symlink-b.txt"
ln -s symlink-a.txt "$SYMLINK_APP/Contents/Resources/symlink-fixture"
codesign --force --deep --sign - "$SYMLINK_APP"
productbuild --component "$SYMLINK_APP" /Applications "$SYMLINK_PACKAGE" >/dev/null
rm "$SYMLINK_APP/Contents/Resources/symlink-fixture"
ln -s symlink-b.txt "$SYMLINK_APP/Contents/Resources/symlink-fixture"
expect_failure payload-symlink-mismatch "$PAYLOAD_VALIDATOR" "$SYMLINK_APP" "$SYMLINK_PACKAGE"

BAD_PACKAGE_ROOT="$TEMP_DIR/bad-package-info"
BAD_PACKAGE="$TEMP_DIR/Clasp-bad-install-location.pkg"
pkgutil --expand "$PAYLOAD_PACKAGE" "$BAD_PACKAGE_ROOT"
PACKAGE_INFO="$(find "$BAD_PACKAGE_ROOT" -type f -name PackageInfo -print -quit)"
sed 's#install-location="/Applications"#install-location="/tmp"#' \
  "$PACKAGE_INFO" > "$PACKAGE_INFO.changed"
mv "$PACKAGE_INFO.changed" "$PACKAGE_INFO"
pkgutil --flatten "$BAD_PACKAGE_ROOT" "$BAD_PACKAGE"
expect_failure package-install-location "$PAYLOAD_VALIDATOR" "$ROOT_DIR/dist/Clasp.app" "$BAD_PACKAGE"

echo "app-store packaging fixture tests passed"
