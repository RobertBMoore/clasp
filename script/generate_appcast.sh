#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATES_DIR="${1:?usage: generate_appcast.sh UPDATES_DIR DOWNLOAD_URL_PREFIX}"
DOWNLOAD_PREFIX="${2:?missing HTTPS download prefix}"
[[ "$DOWNLOAD_PREFIX" == https://* ]] || { echo "download prefix must use HTTPS" >&2; exit 1; }
: "${CLASP_SPARKLE_PRIVATE_KEY:?set the Sparkle EdDSA private key}"
TOOL="$(find "$ROOT_DIR/.build/artifacts" -type f -path '*/bin/generate_appcast' -print -quit)"
[[ -x "$TOOL" ]] || { echo "Sparkle generate_appcast tool unavailable; run an explicit direct build first" >&2; exit 1; }
printf '%s' "$CLASP_SPARKLE_PRIVATE_KEY" | "$TOOL" --ed-key-file - --download-url-prefix "$DOWNLOAD_PREFIX" "$UPDATES_DIR"
unset CLASP_SPARKLE_PRIVATE_KEY
APPCAST="$(find "$UPDATES_DIR" -maxdepth 1 -name '*.xml' -print -quit)"
[[ -s "$APPCAST" ]] || { echo "appcast was not generated" >&2; exit 1; }
grep -q 'sparkle:edSignature=' "$APPCAST" || { echo "appcast lacks EdDSA signature" >&2; exit 1; }
grep -q '<!-- sparkle-signatures:' "$APPCAST" || { echo "appcast feed is not EdDSA-signed" >&2; exit 1; }
grep -Eq '^[[:space:]]*edSignature: [A-Za-z0-9+/]{86}==$' "$APPCAST" || { echo "appcast feed signature is malformed" >&2; exit 1; }
echo "$APPCAST"
