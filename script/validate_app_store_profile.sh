#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/app_store_common.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/script/lib/app_store_common.sh"

PROFILE=""; BUNDLE_ID=""; TEAM_ID=""; APP_ID_PREFIX=""; ENTITLEMENTS=""
APPLICATION_IDENTITY=""; APPLICATION_CERTIFICATE_SHA256=""
while (($#)); do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --bundle-id) BUNDLE_ID="$2"; shift 2 ;;
    --team-id) TEAM_ID="$2"; shift 2 ;;
    --app-id-prefix) APP_ID_PREFIX="$2"; shift 2 ;;
    --entitlements) ENTITLEMENTS="$2"; shift 2 ;;
    --application-identity) APPLICATION_IDENTITY="$2"; shift 2 ;;
    --application-certificate-sha256) APPLICATION_CERTIFICATE_SHA256="$2"; shift 2 ;;
    *) app_store_die "unknown argument: $1" ;;
  esac
done

[[ -f "$PROFILE" ]] || app_store_die "signed .provisionprofile file is required"
[[ -n "$BUNDLE_ID" && -n "$TEAM_ID" && -n "$APP_ID_PREFIX" && -f "$ENTITLEMENTS" ]] \
  || app_store_die "bundle, team, application-prefix, and entitlements arguments are required"
app_store_require_command security
app_store_require_command plutil

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/clasp-profile.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
PAYLOAD="$TEMP_DIR/profile.plist"
security cms -D -i "$PROFILE" -o "$PAYLOAD" >/dev/null \
  || app_store_die "provisioning profile CMS signature could not be decoded"

"$ROOT_DIR/script/lib/validate_app_store_profile_payload.sh" \
  --profile-plist "$PAYLOAD" \
  --bundle-id "$BUNDLE_ID" \
  --team-id "$TEAM_ID" \
  --app-id-prefix "$APP_ID_PREFIX" \
  --entitlements "$ENTITLEMENTS"

app_store_require_identity_certificate application "$APPLICATION_IDENTITY" "$APPLICATION_CERTIFICATE_SHA256"
app_store_profile_certificate_matches_identity \
  "$PAYLOAD" "$APPLICATION_IDENTITY" "$APPLICATION_CERTIFICATE_SHA256"
echo "validated signed App Store provisioning profile: $PROFILE"
