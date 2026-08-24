#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../release/config.env
source "$ROOT_DIR/release/config.env"
# shellcheck source=lib/output_custody.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/script/lib/output_custody.sh"
# shellcheck source=lib/direct_package_resolution.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/script/lib/direct_package_resolution.sh"
# shellcheck source=lib/app_store_common.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/script/lib/app_store_common.sh"

CHANNEL="local"; CONFIGURATION="debug"; VERSION="$CLASP_VERSION"; BUILD_NUMBER="$CLASP_BUILD_NUMBER"
OUTPUT="$ROOT_DIR/dist/$CLASP_APP_NAME.app"; SIGN_IDENTITY="-"; PROFILE=""
UPDATE_FEED_URL="${CLASP_UPDATE_FEED_URL:-}"; SPARKLE_PUBLIC_KEY="${CLASP_SPARKLE_PUBLIC_KEY:-}"
MANAGED_OUTPUT=""; REPLACE_LOCAL_OUTPUT=0

while (($#)); do
  case "$1" in
    --channel) CHANNEL="$2"; shift 2 ;;
    --configuration) CONFIGURATION="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --build-number) BUILD_NUMBER="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --sign-identity) SIGN_IDENTITY="$2"; shift 2 ;;
    --provisioning-profile) PROFILE="$2"; shift 2 ;;
    --managed-output) MANAGED_OUTPUT="$2"; shift 2 ;;
    --replace-existing-local-output) REPLACE_LOCAL_OUTPUT=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ "$CHANNEL" =~ ^(local|direct|app-store)$ ]] || { echo "invalid channel" >&2; exit 2; }
[[ "$CONFIGURATION" =~ ^(debug|release)$ ]] || { echo "invalid configuration" >&2; exit 2; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "invalid version" >&2; exit 2; }
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { echo "invalid build number" >&2; exit 2; }
[[ "$CLASP_ARCH" == arm64 ]] || { echo "unsupported release architecture: $CLASP_ARCH" >&2; exit 2; }

clasp_prepare_channel_output_root "$ROOT_DIR" "$CHANNEL"
clasp_validate_stage_output \
  "$ROOT_DIR" "$CLASP_APP_NAME" "$CHANNEL" "$OUTPUT" "$MANAGED_OUTPUT" "$REPLACE_LOCAL_OUTPUT"
if [[ -e "$OUTPUT" ]]; then
  "$ROOT_DIR/script/validate_app.sh" local "$OUTPUT" >/dev/null || {
    echo "refusing to replace an invalid local build artifact: $OUTPUT" >&2
    exit 1
  }
fi

ROOT_RESOLVED="$ROOT_DIR/Package.resolved"
DIRECT_RESOLVED="$ROOT_DIR/release/Package.direct.resolved"
CREATED_ROOT_RESOLVED=0
STAGE_DIR=""
PREVIOUS_OUTPUT=""
REPLACEMENT_PENDING=0
NO_REPLACE_MOVER=""
PRESERVE_STAGE=0
cleanup() {
  local status=$?
  if ((REPLACEMENT_PENDING)) && [[ -n "$PREVIOUS_OUTPUT" && -e "$PREVIOUS_OUTPUT" && ! -e "$OUTPUT" && ! -L "$OUTPUT" ]]; then
    if [[ -x "$NO_REPLACE_MOVER" ]] && "$NO_REPLACE_MOVER" "$PREVIOUS_OUTPUT" "$OUTPUT"; then
      REPLACEMENT_PENDING=0
    else
      echo "failed to restore the previous local build artifact: $OUTPUT" >&2
      PRESERVE_STAGE=1
      status=1
    fi
  elif ((REPLACEMENT_PENDING)); then
    echo "preserving the previous local build because its destination is no longer empty: $PREVIOUS_OUTPUT" >&2
    PRESERVE_STAGE=1
    status=1
  fi
  if [[ -n "$STAGE_DIR" && -d "$STAGE_DIR" ]]; then
    if ((PRESERVE_STAGE)); then
      echo "preserved recovery staging directory: $STAGE_DIR" >&2
    else
      rm -rf "$STAGE_DIR"
    fi
  fi
  if ((CREATED_ROOT_RESOLVED)); then
    if ! clasp_remove_direct_package_resolution "$ROOT_RESOLVED" "$DIRECT_RESOLVED"; then
      status=1
    fi
  fi
  trap - EXIT
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

[[ ! -e "$ROOT_RESOLVED" && ! -L "$ROOT_RESOLVED" ]] || {
  echo "root Package.resolved is forbidden; Sparkle resolution is isolated to direct builds" >&2
  exit 1
}

if [[ "$CHANNEL" == direct ]]; then
  [[ "$SIGN_IDENTITY" != "-" ]] || { echo "direct releases require a Developer ID Application identity" >&2; exit 1; }
  [[ "$UPDATE_FEED_URL" == https://* ]] || { echo "CLASP_UPDATE_FEED_URL must be HTTPS" >&2; exit 1; }
  [[ "$SPARKLE_PUBLIC_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]] || { echo "CLASP_SPARKLE_PUBLIC_KEY must be a 32-byte base64 EdDSA public key" >&2; exit 1; }
  [[ -f "$DIRECT_RESOLVED" && ! -L "$DIRECT_RESOLVED" ]] || { echo "direct-only SwiftPM lockfile is missing or unsafe" >&2; exit 1; }
  clasp_install_direct_package_resolution "$ROOT_RESOLVED" "$DIRECT_RESOLVED"
  CREATED_ROOT_RESOLVED=1
fi
if [[ "$CHANNEL" == app-store ]]; then
  [[ "$SIGN_IDENTITY" != "-" && -f "$PROFILE" ]] || { echo "App Store signing identity and provisioning profile are required" >&2; exit 1; }
  "$ROOT_DIR/script/lib/validate_public_https_url.sh" "${CLASP_PRIVACY_POLICY_URL:-}" >/dev/null
fi

cd "$ROOT_DIR"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.cache/clang"
BUILD_ARGS=(swift build --configuration "$CONFIGURATION" --arch "$CLASP_ARCH")
if [[ "$CHANNEL" == direct ]]; then
  CLASP_DIRECT_DISTRIBUTION=1 "${BUILD_ARGS[@]}" --force-resolved-versions -Xswiftc -DCLASP_DIRECT_DISTRIBUTION
  BIN_DIR="$(CLASP_DIRECT_DISTRIBUTION=1 swift build --configuration "$CONFIGURATION" --arch "$CLASP_ARCH" --force-resolved-versions --show-bin-path)"
elif [[ "$CHANNEL" == app-store ]]; then
  CLASP_DIRECT_DISTRIBUTION=0 "${BUILD_ARGS[@]}" -Xswiftc -DCLASP_APP_STORE
  BIN_DIR="$(CLASP_DIRECT_DISTRIBUTION=0 swift build --configuration "$CONFIGURATION" --arch "$CLASP_ARCH" -Xswiftc -DCLASP_APP_STORE --show-bin-path)"
else
  CLASP_DIRECT_DISTRIBUTION=0 "${BUILD_ARGS[@]}"
  BIN_DIR="$(CLASP_DIRECT_DISTRIBUTION=0 swift build --configuration "$CONFIGURATION" --arch "$CLASP_ARCH" --show-bin-path)"
fi

OUT_PARENT="$(dirname "$OUTPUT")"
STAGE_DIR="$(mktemp -d "$OUT_PARENT/.clasp-stage.XXXXXX")"
NO_REPLACE_MOVER="$STAGE_DIR/clasp-rename-no-replace"
clasp_compile_no_replace_mover "$ROOT_DIR" "$NO_REPLACE_MOVER"
APP="$STAGE_DIR/$CLASP_APP_NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$CLASP_APP_NAME" "$APP/Contents/MacOS/$CLASP_APP_NAME"
cp "$ROOT_DIR/Assets/AppIcon/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/release/PrivacyInfo.xcprivacy" "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
cp "$ROOT_DIR/release/Info.plist" "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
if [[ "$CHANNEL" == app-store ]]; then
  plutil -insert ClaspPrivacyPolicyURL -string "$CLASP_PRIVACY_POLICY_URL" "$APP/Contents/Info.plist"
fi

if [[ "$CHANNEL" == direct ]]; then
  FRAMEWORK="$BIN_DIR/Sparkle.framework"
  [[ -d "$FRAMEWORK" ]] || { echo "Sparkle framework not found" >&2; exit 1; }
  SPARKLE_LICENSE="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/LICENSE"
  [[ -f "$SPARKLE_LICENSE" && ! -L "$SPARKLE_LICENSE" ]] || { echo "pinned Sparkle license notice is missing or unsafe" >&2; exit 1; }
  [[ "$(shasum -a 256 "$SPARKLE_LICENSE" | awk '{print $1}')" == "$CLASP_SPARKLE_LICENSE_SHA256" ]] \
    || { echo "pinned Sparkle license notice checksum changed" >&2; exit 1; }
  mkdir -p "$APP/Contents/Frameworks"; ditto "$FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
  cp "$SPARKLE_LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"
  FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
  SPARKLE_VERSION_DIR="$FRAMEWORK/Versions/B"
  INSTALLER_XPC="$SPARKLE_VERSION_DIR/XPCServices/Installer.xpc"
  DOWNLOADER_XPC="$SPARKLE_VERSION_DIR/XPCServices/Downloader.xpc"
  AUTOUPDATE="$SPARKLE_VERSION_DIR/Autoupdate"
  UPDATER_APP="$SPARKLE_VERSION_DIR/Updater.app"
  for component in "$INSTALLER_XPC" "$DOWNLOADER_XPC" "$AUTOUPDATE" "$UPDATER_APP"; do
    [[ -e "$component" && ! -L "$component" ]] || { echo "required Sparkle signing component is missing or unsafe: $component" >&2; exit 1; }
  done
  plutil -insert SUFeedURL -string "$UPDATE_FEED_URL" "$APP/Contents/Info.plist"
  plutil -insert SUPublicEDKey -string "$SPARKLE_PUBLIC_KEY" "$APP/Contents/Info.plist"
  plutil -insert SURequireSignedFeed -bool true "$APP/Contents/Info.plist"
  plutil -insert SUVerifyUpdateBeforeExtraction -bool true "$APP/Contents/Info.plist"
  DOWNLOADER_ENTITLEMENTS_BEFORE="$STAGE_DIR/downloader-entitlements-before.plist"
  DOWNLOADER_ENTITLEMENTS_AFTER="$STAGE_DIR/downloader-entitlements-after.plist"
  codesign --display --entitlements - --xml "$DOWNLOADER_XPC" >"$DOWNLOADER_ENTITLEMENTS_BEFORE" 2>/dev/null
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$INSTALLER_XPC"
  codesign --force --options runtime --timestamp --preserve-metadata=entitlements --sign "$SIGN_IDENTITY" "$DOWNLOADER_XPC"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$AUTOUPDATE"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$UPDATER_APP"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$FRAMEWORK"
  codesign --display --entitlements - --xml "$DOWNLOADER_XPC" >"$DOWNLOADER_ENTITLEMENTS_AFTER" 2>/dev/null
  cmp -s "$DOWNLOADER_ENTITLEMENTS_BEFORE" "$DOWNLOADER_ENTITLEMENTS_AFTER" || {
    echo "Sparkle Downloader entitlements changed during inside-out signing" >&2
    exit 1
  }
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
elif [[ "$CHANNEL" == app-store ]]; then
  cp "$ROOT_DIR/release/AppStore/container-migration.plist" "$APP/Contents/Resources/container-migration.plist"
  cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
  # Provisioning profiles are commonly exported with mode 0600. PackageKit
  # installs app payloads as root, so the embedded copy must be readable by
  # ordinary users for macOS to verify the app signature at launch.
  chmod 0644 "$APP/Contents/embedded.provisionprofile"
  # Clear removable download metadata before signing and packaging. macOS 26
  # can retain OS-managed macl/provenance attributes even when xattr -c exits
  # successfully, so fail closed if anything outside that allowlist remains.
  app_store_clear_profile_download_xattrs "$APP/Contents/embedded.provisionprofile"
  codesign --force --options runtime --timestamp --entitlements "$ROOT_DIR/release/Clasp.app-store.entitlements" --sign "$SIGN_IDENTITY" "$APP"
else
  codesign --force --deep --sign - "$APP"
fi

plutil -lint "$APP/Contents/Info.plist" "$APP/Contents/Resources/PrivacyInfo.xcprivacy" >/dev/null
if [[ "$CHANNEL" == app-store ]]; then
  plutil -lint "$APP/Contents/Resources/container-migration.plist" >/dev/null
fi
codesign --verify --deep --strict --verbose=2 "$APP"
# Recheck custody after the potentially long compile/sign operation so a late
# output cannot be silently adopted or replaced.
clasp_validate_stage_output \
  "$ROOT_DIR" "$CLASP_APP_NAME" "$CHANNEL" "$OUTPUT" "$MANAGED_OUTPUT" "$REPLACE_LOCAL_OUTPUT"
if [[ -e "$OUTPUT" ]]; then
  "$ROOT_DIR/script/validate_app.sh" local "$OUTPUT" >/dev/null || {
    echo "refusing to replace an invalid local build artifact: $OUTPUT" >&2
    exit 1
  }
  PREVIOUS_OUTPUT="$STAGE_DIR/previous.app"
  REPLACEMENT_PENDING=1
  if ! "$NO_REPLACE_MOVER" "$OUTPUT" "$PREVIOUS_OUTPUT"; then
    REPLACEMENT_PENDING=0
    echo "failed to take transactional custody of the previous local build: $OUTPUT" >&2
    exit 1
  fi
fi
if ! "$NO_REPLACE_MOVER" "$APP" "$OUTPUT"; then
  if ((REPLACEMENT_PENDING)) && [[ ! -e "$OUTPUT" && ! -L "$OUTPUT" ]]; then
    if "$NO_REPLACE_MOVER" "$PREVIOUS_OUTPUT" "$OUTPUT"; then
      REPLACEMENT_PENDING=0
    else
      PRESERVE_STAGE=1
    fi
  elif ((REPLACEMENT_PENDING)); then
    PRESERVE_STAGE=1
  fi
  echo "refusing to replace a late staged-app destination: $OUTPUT" >&2
  exit 1
fi
REPLACEMENT_PENDING=0
echo "$OUTPUT"
