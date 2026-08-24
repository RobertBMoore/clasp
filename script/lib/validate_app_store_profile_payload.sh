#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=app_store_common.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/script/lib/app_store_common.sh"

PROFILE_PLIST=""; BUNDLE_ID=""; TEAM_ID=""; APP_ID_PREFIX=""; ENTITLEMENTS=""
while (($#)); do
  case "$1" in
    --profile-plist) PROFILE_PLIST="$2"; shift 2 ;;
    --bundle-id) BUNDLE_ID="$2"; shift 2 ;;
    --team-id) TEAM_ID="$2"; shift 2 ;;
    --app-id-prefix) APP_ID_PREFIX="$2"; shift 2 ;;
    --entitlements) ENTITLEMENTS="$2"; shift 2 ;;
    *) app_store_die "unknown argument: $1" ;;
  esac
done

[[ -f "$PROFILE_PLIST" ]] || app_store_die "decoded provisioning profile plist is required"
[[ -f "$ENTITLEMENTS" ]] || app_store_die "App Store entitlements plist is required"
[[ "$BUNDLE_ID" =~ ^[A-Za-z0-9]+([.-][A-Za-z0-9]+)+$ && "$BUNDLE_ID" != *..* ]] \
  || app_store_die "bundle identifier is invalid"
[[ "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || app_store_die "Team ID must be exactly 10 uppercase letters or digits"
[[ "$APP_ID_PREFIX" =~ ^[A-Z0-9]{10}$ ]] \
  || app_store_die "application identifier prefix must be exactly 10 uppercase letters or digits"

plutil -lint "$PROFILE_PLIST" "$ENTITLEMENTS" >/dev/null

plist_buddy_read() {
  local plist="$1" path="$2"
  /usr/libexec/PlistBuddy -c "Print :$path" "$plist" 2>/dev/null
}

xml_value_count() {
  local plist="$1" key="$2" element="$3"
  plutil -extract "$key" xml1 -o - "$plist" \
    | awk -v element="<$element>" 'index($0, element) { count++ } END { print count + 0 }'
}

[[ "$(xml_value_count "$PROFILE_PLIST" TeamIdentifier string)" == 1 ]] \
  || app_store_die "profile must contain exactly one TeamIdentifier"
[[ "$(xml_value_count "$PROFILE_PLIST" ApplicationIdentifierPrefix string)" == 1 ]] \
  || app_store_die "profile must contain exactly one ApplicationIdentifierPrefix"
[[ "$(xml_value_count "$PROFILE_PLIST" DeveloperCertificates data)" == 1 ]] \
  || app_store_die "an App Store profile must contain exactly one distribution certificate"

PLATFORM_COUNT="$(plutil -extract Platform raw -o - "$PROFILE_PLIST")" \
  || app_store_die "profile Platform is missing"
[[ "$PLATFORM_COUNT" == 1 ]] \
  || app_store_die "profile Platform must contain exactly one value"
[[ "$(plist_buddy_read "$PROFILE_PLIST" 'Platform:0')" == OSX ]] \
  || app_store_die "profile Platform must be exactly OSX"

[[ "$(plist_buddy_read "$PROFILE_PLIST" 'TeamIdentifier:0')" == "$TEAM_ID" ]] \
  || app_store_die "profile TeamIdentifier does not match $TEAM_ID"
[[ "$(plist_buddy_read "$PROFILE_PLIST" 'ApplicationIdentifierPrefix:0')" == "$APP_ID_PREFIX" ]] \
  || app_store_die "profile application identifier prefix does not match $APP_ID_PREFIX"

EXPECTED_APPLICATION_IDENTIFIER="$APP_ID_PREFIX.$BUNDLE_ID"
[[ "$(plist_buddy_read "$PROFILE_PLIST" 'Entitlements:com.apple.application-identifier')" == "$EXPECTED_APPLICATION_IDENTIFIER" ]] \
  || app_store_die "profile application identifier does not exactly match $EXPECTED_APPLICATION_IDENTIFIER"
[[ "$(plist_buddy_read "$PROFILE_PLIST" 'Entitlements:com.apple.developer.team-identifier')" == "$TEAM_ID" ]] \
  || app_store_die "profile team entitlement does not match $TEAM_ID"

if plist_buddy_read "$PROFILE_PLIST" ProvisionedDevices >/dev/null; then
  app_store_die "device-bound provisioning profiles are not App Store distribution profiles"
fi
if plist_buddy_read "$PROFILE_PLIST" ProvisionsAllDevices >/dev/null; then
  app_store_die "all-device provisioning profiles are not App Store distribution profiles"
fi
for task_key in 'Entitlements:get-task-allow' 'Entitlements:com.apple.security.get-task-allow'; do
  if [[ "$(plist_buddy_read "$PROFILE_PLIST" "$task_key" || true)" == true ]]; then
    app_store_die "distribution profile must not authorize debugger attachment"
  fi
done

EXPIRATION="$(plutil -extract ExpirationDate raw -o - "$PROFILE_PLIST")" \
  || app_store_die "profile ExpirationDate is missing"
EXPIRATION_EPOCH="$(LC_ALL=C date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$EXPIRATION" '+%s' 2>/dev/null)" \
  || app_store_die "profile ExpirationDate is invalid"
(( EXPIRATION_EPOCH > $(date -u '+%s') )) || app_store_die "provisioning profile is expired"

# These are Clasp's complete source entitlements. App Sandbox entitlements are
# unrestricted on macOS, but the Store build must claim them and must not claim
# a debugger or a stale hard-coded application/team identifier.
[[ "$(plist_buddy_read "$ENTITLEMENTS" 'com.apple.security.app-sandbox')" == true ]] \
  || app_store_die "App Store entitlements must enable App Sandbox"
[[ "$(plist_buddy_read "$ENTITLEMENTS" 'com.apple.security.files.user-selected.read-write')" == true ]] \
  || app_store_die "App Store entitlements must preserve user-selected read/write access"
for forbidden_key in \
  'com.apple.security.get-task-allow' \
  'com.apple.application-identifier' \
  'com.apple.developer.team-identifier'; do
  if plist_buddy_read "$ENTITLEMENTS" "$forbidden_key" >/dev/null; then
    app_store_die "$forbidden_key must be derived during signing, not hard-coded in source entitlements"
  fi
done
SOURCE_ENTITLEMENT_COUNT="$(plutil -p "$ENTITLEMENTS" | awk '/ => / { count++ } END { print count + 0 }')"
[[ "$SOURCE_ENTITLEMENT_COUNT" == 2 ]] \
  || app_store_die "unreviewed App Store source entitlements are present"

PROFILE_SANDBOX="$(plist_buddy_read "$PROFILE_PLIST" 'Entitlements:com.apple.security.app-sandbox' || true)"
[[ -z "$PROFILE_SANDBOX" || "$PROFILE_SANDBOX" == true ]] \
  || app_store_die "profile conflicts with the required App Sandbox entitlement"

PROFILE_NAME="$(plist_buddy_read "$PROFILE_PLIST" Name || true)"
echo "validated decoded App Store profile${PROFILE_NAME:+: $PROFILE_NAME}"
