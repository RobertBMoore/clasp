#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../release/config.env
# shellcheck disable=SC1091
source "$ROOT_DIR/release/config.env"
CHANNEL="${1:?usage: validate_app.sh local|direct|app-store APP}"; APP="${2:?missing app path}"
INFO="$APP/Contents/Info.plist"; BIN="$APP/Contents/MacOS/Clasp"
[[ -f "$INFO" && -x "$BIN" ]] || { echo "invalid app bundle" >&2; exit 1; }
plutil -lint "$INFO" "$APP/Contents/Resources/PrivacyInfo.xcprivacy" >/dev/null
[[ "$(plutil -extract CFBundleIdentifier raw "$INFO")" == "com.robertmoore.personalnotepad" ]]
[[ "$(plutil -extract LSMinimumSystemVersion raw "$INFO")" == "14.0" ]]
[[ "$(lipo -archs "$BIN")" == "$CLASP_ARCH" ]] || {
  echo "$CHANNEL bundle architecture does not match the $CLASP_ARCH release policy" >&2
  exit 1
}
codesign --verify --deep --strict --verbose=2 "$APP"

reject_direct_update_surface() {
  local key
  for key in SUFeedURL SUPublicEDKey SURequireSignedFeed SUVerifyUpdateBeforeExtraction; do
    if plutil -extract "$key" raw "$INFO" >/dev/null 2>&1; then
      echo "$CHANNEL bundle unexpectedly contains $key" >&2
      exit 1
    fi
  done
  if otool -L "$BIN" | grep -F 'Sparkle.framework/' >/dev/null; then
    echo "$CHANNEL bundle unexpectedly links Sparkle" >&2
    exit 1
  fi
  if [[ -e "$APP/Contents/Resources/Sparkle-LICENSE.txt" ]]; then
    echo "$CHANNEL bundle unexpectedly contains the direct-channel Sparkle license notice" >&2
    exit 1
  fi
}

case "$CHANNEL" in
  local)
    [[ ! -e "$APP/Contents/Frameworks/Sparkle.framework" ]]
    reject_direct_update_surface
    ;;
  direct)
    [[ -d "$APP/Contents/Frameworks/Sparkle.framework" ]]
    [[ -f "$APP/Contents/Resources/Sparkle-LICENSE.txt" && ! -L "$APP/Contents/Resources/Sparkle-LICENSE.txt" ]]
    [[ "$(shasum -a 256 "$APP/Contents/Resources/Sparkle-LICENSE.txt" | awk '{print $1}')" == "$CLASP_SPARKLE_LICENSE_SHA256" ]]
    [[ "$(plutil -extract SUFeedURL raw "$INFO")" == https://* ]]
    [[ "$(plutil -extract SUPublicEDKey raw "$INFO")" =~ ^[A-Za-z0-9+/]{43}=$ ]]
    [[ "$(plutil -extract SURequireSignedFeed raw "$INFO")" == true ]]
    [[ "$(plutil -extract SUVerifyUpdateBeforeExtraction raw "$INFO")" == true ]]
    otool -L "$BIN" | grep -F 'Sparkle.framework/' >/dev/null
    codesign -dvv "$APP" 2>&1 | grep -q 'flags=.*runtime'
    ;;
  app-store)
    [[ -f "$APP/Contents/embedded.provisionprofile" && ! -e "$APP/Contents/Frameworks/Sparkle.framework" ]]
    reject_direct_update_surface
    codesign -d --entitlements :- "$APP" 2>&1 | grep -q 'com.apple.security.app-sandbox'
    ;;
  *) exit 2 ;;
esac
echo "validated $CHANNEL bundle: $APP"
