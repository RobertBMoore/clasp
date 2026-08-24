#!/usr/bin/env bash
set -euo pipefail
APP="${1:?usage: notarize_direct_release.sh APP ZIP}"
ZIP="${2:?missing zip}"
: "${CLASP_NOTARY_KEY_FILE:?set the App Store Connect API .p8 path}"
: "${CLASP_NOTARY_KEY_ID:?set the API key ID}"
: "${CLASP_NOTARY_ISSUER_ID:?set the API issuer ID}"
xcrun notarytool submit "$ZIP" --key "$CLASP_NOTARY_KEY_FILE" --key-id "$CLASP_NOTARY_KEY_ID" --issuer "$CLASP_NOTARY_ISSUER_ID" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
spctl -a -vv -t exec "$APP"
ZIP_DIR="$(dirname "$ZIP")"
ZIP_NAME="$(basename "$ZIP")"
(
  cd "$ZIP_DIR"
  shasum -a 256 "$ZIP_NAME" >"$ZIP_NAME.sha256"
)
