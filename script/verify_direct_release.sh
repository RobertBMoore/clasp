#!/usr/bin/env bash
set -euo pipefail

# Use only system trust and archive tools. The verifier itself performs no
# network request, accepts no private key, and never publishes an artifact.
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../release/config.env
source "$ROOT_DIR/release/config.env"
# shellcheck source=lib/direct_signing.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/script/lib/direct_signing.sh"

SPARKLE_NAMESPACE="http://www.andymatuschak.org/xml-namespaces/sparkle"
SIGNATURE_VERIFIER=""

fail() {
  echo "direct release verification failed: $*" >&2
  exit 1
}

reject() {
  echo "direct release check rejected: $*" >&2
  return 1
}

is_valid_version() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

is_valid_build_number() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

is_valid_public_key() {
  [[ "$1" =~ ^[A-Za-z0-9+/]{43}=$ ]]
}

is_valid_signature() {
  [[ "$1" =~ ^[A-Za-z0-9+/]{86}==$ ]]
}

is_https_url() {
  [[ "$1" =~ ^https://[^[:space:]]+$ ]]
}

plist_value() {
  /usr/bin/plutil -extract "$2" raw "$1" 2>/dev/null
}

xml_value() {
  /usr/bin/xmllint --nonet --xpath "$2" "$1" 2>/dev/null
}

code_signing_details_have_hardened_runtime() {
  local details="${1-}"
  /usr/bin/grep -Eq \
    '^(flags=|CodeDirectory[[:space:]].*[[:space:]]flags=)0x[[:xdigit:]]+\(([[:alnum:]_-]+,)*runtime(,[[:alnum:]_-]+)*\)([[:space:]]|$)' \
    <<< "$details"
}

bundle_trees_match_without_following_symlinks() {
  local source_tree="$1" extracted_tree="$2"
  [[ -d "$source_tree" && ! -L "$source_tree" \
    && -d "$extracted_tree" && ! -L "$extracted_tree" ]] || return 1
  /usr/bin/diff -qr --no-dereference "$source_tree" "$extracted_tree" >/dev/null
}

build_signature_verifier() {
  local output="$1"
  local module_cache="$2"
  /bin/mkdir -p "$module_cache"
  CLANG_MODULE_CACHE_PATH="$module_cache" /usr/bin/xcrun swiftc -O \
    -o "$output" "$ROOT_DIR/script/verify_sparkle_signature.swift" \
    || { reject "could not compile the public-key Sparkle signature verifier"; return 1; }
  [[ -x "$output" ]] || { reject "Sparkle signature verifier was not produced"; return 1; }
}

validate_release_names() {
  local release_dir="$1"
  local version="$2"
  local build_number="$3"
  local require_staged_app="${4:-1}"
  local app="$release_dir/$CLASP_APP_NAME.app"
  local archive="$release_dir/$CLASP_APP_NAME-$version-$build_number.zip"
  local checksum="$archive.sha256"
  local appcast="$release_dir/appcast.xml"
  local candidate

  [[ -d "$release_dir" && ! -L "$release_dir" ]] || { reject "release directory is missing or is a symbolic link"; return 1; }
  if [[ "$require_staged_app" == "1" ]]; then
    [[ -d "$app" && ! -L "$app" ]] || { reject "expected $CLASP_APP_NAME.app directory is missing or unsafe"; return 1; }
  else
    [[ "$require_staged_app" == "0" ]] || { reject "invalid staged-app requirement"; return 1; }
    [[ ! -e "$app" && ! -L "$app" ]] || { reject "archive-only verification must not trust a staged app"; return 1; }
  fi
  [[ -f "$archive" && ! -L "$archive" ]] || { reject "expected archive is missing or unsafe"; return 1; }
  [[ -f "$checksum" && ! -L "$checksum" ]] || { reject "expected checksum is missing or unsafe"; return 1; }
  [[ -f "$appcast" && ! -L "$appcast" ]] || { reject "expected appcast.xml is missing or unsafe"; return 1; }

  shopt -s nullglob
  for candidate in "$release_dir"/"$CLASP_APP_NAME"-*.zip; do
    [[ "$candidate" == "$archive" ]] || {
      shopt -u nullglob
      reject "unexpected release archive: ${candidate##*/}"
      return 1
    }
  done
  for candidate in "$release_dir"/"$CLASP_APP_NAME"-*.zip.sha256; do
    [[ "$candidate" == "$checksum" ]] || {
      shopt -u nullglob
      reject "unexpected release checksum: ${candidate##*/}"
      return 1
    }
  done
  shopt -u nullglob
}

validate_checksum() {
  local archive="$1"
  local checksum="$2"
  local expected_name="${archive##*/}"
  local line_count digest recorded_name actual

  line_count="$(/usr/bin/wc -l < "$checksum" | /usr/bin/tr -d '[:space:]')"
  [[ "$line_count" == "1" ]] || { reject "checksum file must contain exactly one line"; return 1; }
  read -r digest recorded_name < "$checksum" || { reject "checksum file could not be read"; return 1; }
  recorded_name="${recorded_name#\*}"
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || { reject "checksum digest is malformed"; return 1; }
  [[ "$recorded_name" == "$expected_name" ]] || { reject "checksum must name only the exact archive basename"; return 1; }

  actual="$(/usr/bin/shasum -a 256 "$archive")"
  actual="${actual%% *}"
  [[ "$actual" == "$digest" ]] || { reject "archive SHA-256 does not match its checksum file"; return 1; }
}

validate_appcast() {
  local appcast="$1"
  local version="$2"
  local build_number="$3"
  local expected_archive_url="$4"
  local archive_length="$5"
  local minimum_macos="$6"
  local archive="$7"
  local public_key="$8"
  local sparkle_version_xpath sparkle_short_version_xpath sparkle_minimum_xpath sparkle_signature_xpath
  local item_count enclosure_count feed_block_count feed_signature_count
  local archive_signature feed_block feed_signature

  if /usr/bin/grep -Eiq '<![[:space:]]*(DOCTYPE|ENTITY)' "$appcast"; then
    reject "appcast contains a forbidden document type or entity declaration"
    return 1
  fi
  /usr/bin/xmllint --nonet --noout "$appcast" 2>/dev/null || { reject "appcast is not well-formed offline XML"; return 1; }

  item_count="$(xml_value "$appcast" 'string(count(/rss/channel/item))')"
  enclosure_count="$(xml_value "$appcast" 'string(count(/rss/channel/item/enclosure))')"
  [[ "$item_count" == "1" ]] || { reject "appcast must contain exactly one release item"; return 1; }
  [[ "$enclosure_count" == "1" ]] || { reject "appcast must contain exactly one enclosure"; return 1; }
  [[ "$(xml_value "$appcast" 'string(/rss/@version)')" == "2.0" ]] || { reject "appcast RSS version is not 2.0"; return 1; }

  sparkle_version_xpath="string((/rss/channel/item/*[local-name()='version' and namespace-uri()='$SPARKLE_NAMESPACE'])[1])"
  sparkle_short_version_xpath="string((/rss/channel/item/*[local-name()='shortVersionString' and namespace-uri()='$SPARKLE_NAMESPACE'])[1])"
  sparkle_minimum_xpath="string((/rss/channel/item/*[local-name()='minimumSystemVersion' and namespace-uri()='$SPARKLE_NAMESPACE'])[1])"
  sparkle_signature_xpath="string((/rss/channel/item/enclosure/@*[local-name()='edSignature' and namespace-uri()='$SPARKLE_NAMESPACE'])[1])"

  [[ "$(xml_value "$appcast" "string(count(/rss/channel/item/*[local-name()='version' and namespace-uri()='$SPARKLE_NAMESPACE']))")" == "1" ]] || { reject "appcast must contain exactly one Sparkle build number"; return 1; }
  [[ "$(xml_value "$appcast" "string(count(/rss/channel/item/*[local-name()='shortVersionString' and namespace-uri()='$SPARKLE_NAMESPACE']))")" == "1" ]] || { reject "appcast must contain exactly one Sparkle version"; return 1; }
  [[ "$(xml_value "$appcast" "string(count(/rss/channel/item/*[local-name()='minimumSystemVersion' and namespace-uri()='$SPARKLE_NAMESPACE']))")" == "1" ]] || { reject "appcast must contain exactly one minimum system version"; return 1; }
  [[ "$(xml_value "$appcast" "$sparkle_version_xpath")" == "$build_number" ]] || { reject "appcast build number does not match"; return 1; }
  [[ "$(xml_value "$appcast" "$sparkle_short_version_xpath")" == "$version" ]] || { reject "appcast version does not match"; return 1; }
  [[ "$(xml_value "$appcast" "$sparkle_minimum_xpath")" == "$minimum_macos" ]] || { reject "appcast minimum macOS version does not match"; return 1; }
  [[ "$(xml_value "$appcast" 'string(/rss/channel/item/enclosure/@url)')" == "$expected_archive_url" ]] || { reject "appcast archive URL does not match the expected HTTPS release URL"; return 1; }
  [[ "$(xml_value "$appcast" 'string(/rss/channel/item/enclosure/@length)')" == "$archive_length" ]] || { reject "appcast archive length does not match"; return 1; }
  [[ "$(xml_value "$appcast" 'string(/rss/channel/item/enclosure/@type)')" == "application/octet-stream" ]] || { reject "appcast enclosure type is unexpected"; return 1; }

  archive_signature="$(xml_value "$appcast" "$sparkle_signature_xpath")"
  is_valid_signature "$archive_signature" || { reject "archive EdDSA signature is absent or malformed"; return 1; }
  [[ -x "$SIGNATURE_VERIFIER" ]] || { reject "public-key signature verifier is unavailable"; return 1; }
  "$SIGNATURE_VERIFIER" --file "$archive" "$archive_signature" "$public_key" >/dev/null \
    || { reject "archive EdDSA signature is not valid for the configured public key"; return 1; }

  feed_block_count="$(xml_value "$appcast" "string(count(//comment()[contains(., 'sparkle-signatures:')]))")"
  [[ "$feed_block_count" == "1" ]] || { reject "signed-feed comment block is absent or duplicated"; return 1; }
  feed_block="$(xml_value "$appcast" "string((//comment()[contains(., 'sparkle-signatures:')])[1])")"
  feed_signature_count="$(/usr/bin/grep -Ec '^[[:space:]]*edSignature: [A-Za-z0-9+/]{86}==[[:space:]]*$' <<< "$feed_block" || true)"
  [[ "$feed_signature_count" == "1" ]] || { reject "signed-feed EdDSA signature is absent, duplicated, or malformed"; return 1; }
  feed_signature="$(/usr/bin/sed -nE 's/^[[:space:]]*edSignature: ([A-Za-z0-9+\/]{86}==)[[:space:]]*$/\1/p' <<< "$feed_block")"
  is_valid_signature "$feed_signature" || { reject "signed-feed EdDSA signature shape is invalid"; return 1; }
  "$SIGNATURE_VERIFIER" --signed-feed "$appcast" "$public_key" >/dev/null \
    || { reject "feed EdDSA signature is not valid for the configured public key"; return 1; }
}

validate_bundle_metadata() {
  local app="$1"
  local version="$2"
  local build_number="$3"
  local expected_feed_url="$4"
  local expected_public_key="$5"
  local info="$app/Contents/Info.plist"
  local binary="$app/Contents/MacOS/$CLASP_APP_NAME"
  local privacy="$app/Contents/Resources/PrivacyInfo.xcprivacy"
  local sparkle_license="$app/Contents/Resources/Sparkle-LICENSE.txt"
  local sparkle="$app/Contents/Frameworks/Sparkle.framework"
  local sparkle_info="$sparkle/Resources/Info.plist"

  [[ -f "$info" && ! -L "$info" ]] || { reject "bundle Info.plist is missing or unsafe"; return 1; }
  [[ -f "$binary" && -x "$binary" && ! -L "$binary" ]] || { reject "bundle executable is missing or unsafe"; return 1; }
  [[ -f "$privacy" && ! -L "$privacy" ]] || { reject "privacy manifest is missing or unsafe"; return 1; }
  [[ -f "$sparkle_license" && ! -L "$sparkle_license" ]] || { reject "Sparkle license notice is missing or unsafe"; return 1; }
  [[ "$(/usr/bin/shasum -a 256 "$sparkle_license" | /usr/bin/awk '{print $1}')" == "$CLASP_SPARKLE_LICENSE_SHA256" ]] || { reject "Sparkle license notice does not match the pinned distribution"; return 1; }
  [[ -d "$sparkle" && ! -L "$sparkle" ]] || { reject "Sparkle.framework is missing or unsafe"; return 1; }
  [[ -f "$sparkle_info" ]] || { reject "Sparkle framework metadata is missing"; return 1; }
  [[ ! -e "$app/Contents/embedded.provisionprofile" && ! -L "$app/Contents/embedded.provisionprofile" ]] || { reject "direct bundle unexpectedly contains a provisioning profile"; return 1; }
  [[ ! -e "$app/Contents/_MASReceipt" && ! -L "$app/Contents/_MASReceipt" ]] || { reject "direct bundle unexpectedly contains an App Store receipt"; return 1; }

  /usr/bin/plutil -lint "$info" "$privacy" "$sparkle_info" >/dev/null || { reject "bundle property lists are malformed"; return 1; }
  [[ "$(plist_value "$info" CFBundleIdentifier)" == "$CLASP_BUNDLE_ID" ]] || { reject "bundle identifier does not match"; return 1; }
  [[ "$(plist_value "$info" CFBundleExecutable)" == "$CLASP_APP_NAME" ]] || { reject "bundle executable metadata does not match"; return 1; }
  [[ "$(plist_value "$info" CFBundlePackageType)" == "APPL" ]] || { reject "bundle package type is not APPL"; return 1; }
  [[ "$(plist_value "$info" CFBundleShortVersionString)" == "$version" ]] || { reject "bundle version does not match"; return 1; }
  [[ "$(plist_value "$info" CFBundleVersion)" == "$build_number" ]] || { reject "bundle build number does not match"; return 1; }
  [[ "$(plist_value "$info" LSMinimumSystemVersion)" == "$CLASP_MIN_MACOS" ]] || { reject "bundle minimum macOS version does not match"; return 1; }
  [[ "$(/usr/bin/lipo -archs "$binary")" == "$CLASP_ARCH" ]] || { reject "bundle architecture does not match the $CLASP_ARCH release policy"; return 1; }
  [[ "$(plist_value "$info" SUFeedURL)" == "$expected_feed_url" ]] || { reject "bundle feed URL does not match the expected URL"; return 1; }
  [[ "$(plist_value "$info" SUPublicEDKey)" == "$expected_public_key" ]] || { reject "bundle Sparkle public key does not match the expected key"; return 1; }
  [[ "$(plist_value "$info" SURequireSignedFeed)" == "true" ]] || { reject "bundle does not require a signed feed"; return 1; }
  [[ "$(plist_value "$info" SUVerifyUpdateBeforeExtraction)" == "true" ]] || { reject "bundle does not require verification before extraction"; return 1; }
  [[ "$(plist_value "$sparkle_info" CFBundleIdentifier)" == "org.sparkle-project.Sparkle" ]] || { reject "bundled Sparkle identifier is unexpected"; return 1; }
  [[ "$(plist_value "$sparkle_info" CFBundlePackageType)" == "FMWK" ]] || { reject "bundled Sparkle package type is unexpected"; return 1; }
  [[ "$(plist_value "$sparkle_info" CFBundleShortVersionString)" == "$CLASP_SPARKLE_VERSION" ]] || { reject "bundled Sparkle version does not match the exact pin"; return 1; }
  /usr/bin/otool -L "$binary" | /usr/bin/grep -Fq '@rpath/Sparkle.framework/' || { reject "main executable does not link the bundled Sparkle framework"; return 1; }
}

signature_details_match() {
  local path="$1"
  local expected_identity="$2"
  local expected_team="$3"
  local expected_certificate_sha256="$4"
  local scratch="$5"
  local details

  details="$(/usr/bin/codesign -dvvv "$path" 2>&1)" || { reject "could not read code-signing details for $path"; return 1; }
  /usr/bin/grep -Fqx "Authority=$expected_identity" <<< "$details" || { reject "unexpected signing identity on $path"; return 1; }
  /usr/bin/grep -Fqx "TeamIdentifier=$expected_team" <<< "$details" || { reject "unexpected signing team on $path"; return 1; }
  code_signing_details_have_hardened_runtime "$details" \
    || { reject "hardened runtime is missing on $path"; return 1; }
  /usr/bin/grep -Eq '^Timestamp=' <<< "$details" || { reject "trusted signing timestamp is missing on $path"; return 1; }
  clasp_direct_require_signed_path_certificate \
    "$path" "$expected_certificate_sha256" "$scratch" \
    || { reject "unexpected signing certificate on $path"; return 1; }
}

validate_code_signing() {
  local app="$1"
  local expected_identity="$2"
  local expected_team="$3"
  local expected_certificate_sha256="$4"
  local scratch="$5"
  local framework="$app/Contents/Frameworks/Sparkle.framework"
  local candidate component kind
  local macho_count=0

  /usr/bin/codesign --verify --deep --strict --verbose=4 "$app" >/dev/null 2>&1 || { reject "deep strict app signature verification failed"; return 1; }
  /usr/bin/codesign --verify --strict --verbose=4 "$framework" >/dev/null 2>&1 || { reject "Sparkle framework signature verification failed"; return 1; }
  signature_details_match \
    "$app" "$expected_identity" "$expected_team" "$expected_certificate_sha256" "$scratch" \
    || return 1
  signature_details_match \
    "$framework" "$expected_identity" "$expected_team" "$expected_certificate_sha256" "$scratch" \
    || return 1

  for component in \
    "$framework/Versions/B/XPCServices/Installer.xpc" \
    "$framework/Versions/B/XPCServices/Downloader.xpc" \
    "$framework/Versions/B/Autoupdate" \
    "$framework/Versions/B/Updater.app"; do
    [[ -e "$component" && ! -L "$component" ]] || { reject "required Sparkle signing component is missing or unsafe: $component"; return 1; }
    /usr/bin/codesign --verify --strict --verbose=4 "$component" >/dev/null 2>&1 \
      || { reject "Sparkle component signature verification failed: $component"; return 1; }
    signature_details_match \
      "$component" "$expected_identity" "$expected_team" "$expected_certificate_sha256" "$scratch" \
      || return 1
  done

  /usr/bin/codesign -d --entitlements :- "$app" >"$scratch/entitlements.plist" 2>"$scratch/entitlements.log" || { reject "could not inspect app entitlements"; return 1; }
  if /usr/bin/grep -Fq 'com.apple.security.app-sandbox' "$scratch/entitlements.plist" "$scratch/entitlements.log"; then
    reject "direct bundle unexpectedly enables App Sandbox"
    return 1
  fi

  while IFS= read -r -d '' candidate; do
    kind="$(/usr/bin/file -b "$candidate")"
    [[ "$kind" == *Mach-O* ]] || continue
    macho_count=$((macho_count + 1))
    /usr/bin/codesign --verify --strict --verbose=4 "$candidate" >/dev/null 2>&1 || { reject "nested Mach-O signature verification failed: $candidate"; return 1; }
    signature_details_match \
      "$candidate" "$expected_identity" "$expected_team" "$expected_certificate_sha256" "$scratch" \
      || return 1
    /usr/bin/codesign -d --entitlements :- "$candidate" >"$scratch/macho-$macho_count-entitlements.plist" 2>"$scratch/macho-$macho_count-entitlements.log" || { reject "could not inspect nested entitlements: $candidate"; return 1; }
    if /usr/bin/grep -Fq 'com.apple.security.app-sandbox' "$scratch/macho-$macho_count-entitlements.plist" "$scratch/macho-$macho_count-entitlements.log"; then
      reject "nested code unexpectedly enables App Sandbox: $candidate"
      return 1
    fi
  done < <(/usr/bin/find "$app/Contents" -type f -print0)
  ((macho_count >= 2)) || { reject "expected signed Clasp and Sparkle Mach-O code was not found"; return 1; }
}

validate_notarization() {
  local app="$1"
  local gatekeeper_output

  /usr/bin/xcrun stapler validate "$app" >/dev/null 2>&1 || { reject "stapled notarization ticket validation failed"; return 1; }
  gatekeeper_output="$(/usr/sbin/spctl -a -vvv -t exec "$app" 2>&1)" || { reject "Gatekeeper rejected the app"; return 1; }
  /usr/bin/grep -Fq 'accepted' <<< "$gatekeeper_output" || { reject "Gatekeeper did not report acceptance"; return 1; }
  /usr/bin/grep -Fq 'source=Notarized Developer ID' <<< "$gatekeeper_output" || { reject "Gatekeeper acceptance is not from a notarized Developer ID"; return 1; }
}

validate_archive_entries() {
  local archive="$1"
  local entry
  local saw_info=0

  /usr/bin/zipinfo -t "$archive" >/dev/null 2>&1 || { reject "archive structure or CRC validation failed"; return 1; }
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || { reject "archive contains an empty path"; return 1; }
    [[ "$entry" != /* && "$entry" != ../* && "$entry" != *'/../'* && "$entry" != *'/..' ]] || { reject "archive contains an unsafe path"; return 1; }
    case "$entry" in
      *\\*) reject "archive contains an ambiguous backslash path"; return 1 ;;
    esac
    case "$entry" in
      "$CLASP_APP_NAME.app"|"$CLASP_APP_NAME.app"/*|__MACOSX|__MACOSX/*) ;;
      *) reject "archive contains unexpected top-level content: $entry"; return 1 ;;
    esac
    [[ "$entry" == "$CLASP_APP_NAME.app/Contents/Info.plist" ]] && saw_info=1
  done < <(/usr/bin/zipinfo -1 "$archive")
  [[ "$saw_info" == "1" ]] || { reject "archive does not contain the expected app bundle"; return 1; }
}

run_self_test() (
  set -euo pipefail
  local fixture version build archive checksum appcast archive_length archive_url
  local archive_signature feed_signature public_key feed_content_length invalid_signature
  local bad_checksum bad_appcast tree_a tree_b
  fixture="$(/usr/bin/mktemp -d /tmp/clasp-direct-verifier-self-test.XXXXXX)"
  [[ "$fixture" == /tmp/clasp-direct-verifier-self-test.* ]] || fail "unsafe self-test directory"
  trap '/bin/rm -rf "$fixture"' EXIT

  code_signing_details_have_hardened_runtime \
    'CodeDirectory v=20500 size=11403 flags=0x10000(runtime) hashes=349+3 location=embedded' \
    || fail "self-test rejected current macOS CodeDirectory runtime flags"
  code_signing_details_have_hardened_runtime \
    'flags=0x10000(runtime)' \
    || fail "self-test rejected legacy runtime flags"
  code_signing_details_have_hardened_runtime \
    'CodeDirectory v=20500 size=11403 flags=0x18000(kill,runtime,library-validation) hashes=349+3 location=embedded' \
    || fail "self-test rejected runtime among multiple exact flags"
  ! code_signing_details_have_hardened_runtime \
    'CodeDirectory v=20500 size=11403 flags=0x0(none) hashes=349+3 location=embedded' \
    || fail "self-test accepted code without hardened runtime"
  ! code_signing_details_have_hardened_runtime \
    'CodeDirectory v=20500 size=11403 flags=0x10000(notruntime) hashes=349+3 location=embedded' \
    || fail "self-test accepted a substring instead of the runtime flag token"
  ! code_signing_details_have_hardened_runtime \
    'Runtime Version=26.5.0' \
    || fail "self-test treated a runtime-version label as hardened-runtime flags"
  ! code_signing_details_have_hardened_runtime $'Executable=/tmp/Clasp flags=0x10000(runtime)\nCodeDirectory v=20500 size=11403 flags=0x0(none) hashes=349+3 location=embedded' \
    || fail "self-test accepted runtime text outside a canonical codesign flags line"

  tree_a="$fixture/tree-a"
  tree_b="$fixture/tree-b"
  /bin/mkdir -p "$tree_a/Versions/B/Headers"
  /usr/bin/printf 'signed payload' > "$tree_a/Versions/B/Headers/example.h"
  /bin/ln -s B "$tree_a/Versions/Current"
  /bin/ln -s Versions/Current/Headers "$tree_a/Headers"
  /usr/bin/ditto "$tree_a" "$tree_b"
  bundle_trees_match_without_following_symlinks "$tree_a" "$tree_b" \
    || fail "self-test rejected equivalent framework-style symlink trees"
  /usr/bin/printf 'changed payload' > "$tree_b/Versions/B/Headers/example.h"
  ! bundle_trees_match_without_following_symlinks "$tree_a" "$tree_b" \
    || fail "self-test accepted different bundle trees"
  /usr/bin/printf 'signed payload' > "$tree_b/Versions/B/Headers/example.h"
  /bin/rm "$tree_b/Headers"
  /bin/ln -s Versions/B/Headers "$tree_b/Headers"
  ! bundle_trees_match_without_following_symlinks "$tree_a" "$tree_b" \
    || fail "self-test accepted a changed framework symlink target"
  /bin/rm "$tree_b/Headers"
  /bin/ln -s Versions/Current/Headers "$tree_b/Headers"
  /usr/bin/printf 'unexpected' > "$tree_b/extra-file"
  ! bundle_trees_match_without_following_symlinks "$tree_a" "$tree_b" \
    || fail "self-test accepted an extra archived bundle entry"

  version="1.2.3"
  build="42"
  archive="$fixture/$CLASP_APP_NAME-$version-$build.zip"
  checksum="$archive.sha256"
  appcast="$fixture/appcast.xml"
  archive_url="https://example.invalid/releases/download/v$version/${archive##*/}"
  public_key="iojj3XQJ8ZX9UtstPLpdcspnCb8dlBIb83SIAbQPb1w="
  archive_signature="klVO7AVWjEQWNYdnhtO3utfVfRSr90NMWJEs+K7d2qvGcOH0H+DRKbVFLZhyrwXA52gUoeVRvem+aCKHeET9CA=="
  feed_signature="lBfMsssbpRbKRFAd5gAydevAYT1KUc79hx+k/6E/Yi2HwwwsDeWffLwtMOCTE+oMj6z7a66njPSyhG53opzJAw=="

  /usr/bin/printf 'offline fixture archive' > "$archive"
  (
    cd "$fixture"
    /usr/bin/shasum -a 256 "${archive##*/}" > "${checksum##*/}"
  )
  archive_length="$(/usr/bin/stat -f '%z' "$archive")"
  /bin/mkdir "$fixture/$CLASP_APP_NAME.app"
  /usr/bin/printf '%s\n' \
    '<?xml version="1.0" encoding="utf-8"?>' \
    '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">' \
    '<channel>' \
    '<item>' \
    "<sparkle:version>$build</sparkle:version>" \
    "<sparkle:shortVersionString>$version</sparkle:shortVersionString>" \
    "<sparkle:minimumSystemVersion>$CLASP_MIN_MACOS</sparkle:minimumSystemVersion>" \
    "<enclosure url=\"$archive_url\" length=\"$archive_length\" type=\"application/octet-stream\" sparkle:edSignature=\"$archive_signature\"/>" \
    '</item>' \
    '</channel>' \
    '</rss>' > "$appcast"
  feed_content_length="$(/usr/bin/stat -f '%z' "$appcast")"
  [[ "$feed_content_length" == "579" ]] || fail "self-test signed-feed fixture content drifted"
  /usr/bin/printf '%s\n' \
    '<!-- sparkle-signatures:' \
    "edSignature: $feed_signature" \
    "length: $feed_content_length" \
    '-->' >> "$appcast"

  SIGNATURE_VERIFIER="$fixture/sparkle-signature-verifier"
  build_signature_verifier "$SIGNATURE_VERIFIER" "$fixture/module-cache"

  validate_release_names "$fixture" "$version" "$build"
  validate_checksum "$archive" "$checksum"
  validate_appcast "$appcast" "$version" "$build" "$archive_url" "$archive_length" "$CLASP_MIN_MACOS" "$archive" "$public_key"
  is_valid_public_key "$public_key" || fail "self-test rejected a valid public key shape"
  ! is_valid_public_key 'private-or-malformed' || fail "self-test accepted a malformed public key"
  clasp_direct_is_valid_sha256 '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' \
    || fail "self-test rejected a valid certificate SHA-256 pin"
  ! clasp_direct_is_valid_sha256 '0123456789abcdef' \
    || fail "self-test accepted a malformed certificate SHA-256 pin"
  is_https_url "$archive_url" || fail "self-test rejected an HTTPS release URL"
  ! is_https_url 'http://example.invalid/appcast.xml' || fail "self-test accepted a non-HTTPS URL"
  ! is_valid_version '1.2.3;unexpected' || fail "self-test accepted an unsafe version"

  bad_checksum="$fixture/bad.sha256"
  /usr/bin/printf '%064d  %s\n' 0 "${archive##*/}" > "$bad_checksum"
  ! validate_checksum "$archive" "$bad_checksum" >/dev/null 2>&1 || fail "self-test accepted a mismatched checksum"

  bad_appcast="$fixture/bad-appcast.xml"
  /usr/bin/sed 's#https://example.invalid#http://example.invalid#' "$appcast" > "$bad_appcast"
  ! validate_appcast "$bad_appcast" "$version" "$build" "$archive_url" "$archive_length" "$CLASP_MIN_MACOS" "$archive" "$public_key" >/dev/null 2>&1 || fail "self-test accepted an unexpected appcast URL"
  /usr/bin/sed "s/$archive_signature/short-signature/" "$appcast" > "$bad_appcast"
  ! validate_appcast "$bad_appcast" "$version" "$build" "$archive_url" "$archive_length" "$CLASP_MIN_MACOS" "$archive" "$public_key" >/dev/null 2>&1 || fail "self-test accepted a malformed archive signature"
  invalid_signature="$(/usr/bin/printf 'A%.0s' {1..86})=="
  /usr/bin/sed "s#$archive_signature#$invalid_signature#" "$appcast" > "$bad_appcast"
  ! validate_appcast "$bad_appcast" "$version" "$build" "$archive_url" "$archive_length" "$CLASP_MIN_MACOS" "$archive" "$public_key" >/dev/null 2>&1 || fail "self-test accepted a cryptographically invalid archive signature"
  /usr/bin/sed 's#<channel>#<channel> #' "$appcast" > "$bad_appcast"
  ! validate_appcast "$bad_appcast" "$version" "$build" "$archive_url" "$archive_length" "$CLASP_MIN_MACOS" "$archive" "$public_key" >/dev/null 2>&1 || fail "self-test accepted a cryptographically invalid feed signature"
  /usr/bin/sed '/<!-- sparkle-signatures:/,/-->/d' "$appcast" > "$bad_appcast"
  ! validate_appcast "$bad_appcast" "$version" "$build" "$archive_url" "$archive_length" "$CLASP_MIN_MACOS" "$archive" "$public_key" >/dev/null 2>&1 || fail "self-test accepted a missing signed-feed block"

  /bin/rmdir "$fixture/$CLASP_APP_NAME.app"
  validate_release_names "$fixture" "$version" "$build" 0
  /bin/mkdir "$fixture/$CLASP_APP_NAME.app"
  ! validate_release_names "$fixture" "$version" "$build" 0 >/dev/null 2>&1 || fail "self-test archive-only mode trusted a caller-supplied staged app"

  /usr/bin/printf 'old' > "$fixture/$CLASP_APP_NAME-0.9.0-1.zip"
  ! validate_release_names "$fixture" "$version" "$build" >/dev/null 2>&1 || fail "self-test accepted an extra release archive"

  echo "direct release verifier self-test passed"
)

if [[ "${1:-}" == "--self-test" ]]; then
  [[ "$#" == "1" ]] || fail "--self-test accepts no other arguments"
  run_self_test
  exit 0
fi

[[ "$#" -ge 4 && "$#" -le 6 ]] || fail "usage: $0 RELEASE_DIR VERSION BUILD_NUMBER HTTPS_DOWNLOAD_PREFIX [--require-notarization] [--archive-only]"

RELEASE_DIR_INPUT="$1"
VERSION="$2"
BUILD_NUMBER="$3"
DOWNLOAD_PREFIX="$4"
REQUIRE_NOTARIZATION=0
ARCHIVE_ONLY=0
shift 4
while (($#)); do
  case "$1" in
    --require-notarization)
      [[ "$REQUIRE_NOTARIZATION" == "0" ]] || fail "duplicate option: $1"
      REQUIRE_NOTARIZATION=1
      ;;
    --archive-only)
      [[ "$ARCHIVE_ONLY" == "0" ]] || fail "duplicate option: $1"
      ARCHIVE_ONLY=1
      ;;
    *) fail "unknown option: $1" ;;
  esac
  shift
done

is_valid_version "$VERSION" || fail "version must be numeric dotted notation"
is_valid_build_number "$BUILD_NUMBER" || fail "build number must be a positive integer"
is_https_url "$DOWNLOAD_PREFIX" || fail "download prefix must use HTTPS"
[[ "$DOWNLOAD_PREFIX" == */ ]] || fail "download prefix must end with a slash"
[[ -d "$RELEASE_DIR_INPUT" && ! -L "$RELEASE_DIR_INPUT" && "$RELEASE_DIR_INPUT" != "/" ]] || fail "release directory is missing or unsafe"
RELEASE_DIR="$(cd "$RELEASE_DIR_INPUT" && pwd -P)"

: "${CLASP_DEVELOPER_ID_APPLICATION:?set the expected Developer ID Application identity}"
: "${CLASP_DEVELOPER_ID_APPLICATION_CERTIFICATE_SHA256:?set the expected Developer ID Application certificate SHA-256 fingerprint}"
: "${CLASP_UPDATE_FEED_URL:?set the expected HTTPS appcast URL}"
: "${CLASP_SPARKLE_PUBLIC_KEY:?set the expected Sparkle public key}"
EXPECTED_TEAM_ID="$(clasp_direct_team_id_from_identity \
  "$CLASP_DEVELOPER_ID_APPLICATION")" \
  || fail "expected signing identity is not a Developer ID Application identity"
clasp_direct_is_valid_sha256 "$CLASP_DEVELOPER_ID_APPLICATION_CERTIFICATE_SHA256" \
  || fail "expected Developer ID certificate pin must be an exact 64-character SHA-256 fingerprint"
EXPECTED_CERTIFICATE_SHA256="$(clasp_direct_uppercase_sha256 \
  "$CLASP_DEVELOPER_ID_APPLICATION_CERTIFICATE_SHA256")"
is_https_url "$CLASP_UPDATE_FEED_URL" || fail "expected appcast URL must use HTTPS"
is_valid_public_key "$CLASP_SPARKLE_PUBLIC_KEY" || fail "expected Sparkle public key is malformed"

APP="$RELEASE_DIR/$CLASP_APP_NAME.app"
ARCHIVE="$RELEASE_DIR/$CLASP_APP_NAME-$VERSION-$BUILD_NUMBER.zip"
CHECKSUM="$ARCHIVE.sha256"
APPCAST="$RELEASE_DIR/appcast.xml"
EXPECTED_ARCHIVE_URL="$DOWNLOAD_PREFIX${ARCHIVE##*/}"

TEMP_DIR="$(/usr/bin/mktemp -d /tmp/clasp-direct-release-verify.XXXXXX)"
[[ "$TEMP_DIR" == /tmp/clasp-direct-release-verify.* ]] || fail "unsafe verification directory"
trap '/bin/rm -rf "$TEMP_DIR"' EXIT
SIGNATURE_VERIFIER="$TEMP_DIR/sparkle-signature-verifier"
build_signature_verifier "$SIGNATURE_VERIFIER" "$TEMP_DIR/module-cache" || fail "could not prepare signature verification"

validate_release_names "$RELEASE_DIR" "$VERSION" "$BUILD_NUMBER" "$((1 - ARCHIVE_ONLY))" || fail "release artifact names are not exact"
validate_checksum "$ARCHIVE" "$CHECKSUM" || fail "checksum validation failed"
validate_archive_entries "$ARCHIVE" || fail "archive entry validation failed"
ARCHIVE_LENGTH="$(/usr/bin/stat -f '%z' "$ARCHIVE")"
validate_appcast "$APPCAST" "$VERSION" "$BUILD_NUMBER" "$EXPECTED_ARCHIVE_URL" "$ARCHIVE_LENGTH" "$CLASP_MIN_MACOS" "$ARCHIVE" "$CLASP_SPARKLE_PUBLIC_KEY" || fail "appcast validation failed"
/usr/bin/ditto -x -k "$ARCHIVE" "$TEMP_DIR/extracted"
EXTRACTED_APP="$TEMP_DIR/extracted/$CLASP_APP_NAME.app"
[[ -d "$EXTRACTED_APP" && ! -L "$EXTRACTED_APP" ]] || fail "archive did not extract the expected app"
UNEXPECTED_TOP_LEVEL="$(/usr/bin/find "$TEMP_DIR/extracted" -mindepth 1 -maxdepth 1 ! -name "$CLASP_APP_NAME.app" ! -name __MACOSX -print -quit)"
[[ -z "$UNEXPECTED_TOP_LEVEL" ]] || fail "archive extracted unexpected top-level content"
if [[ "$ARCHIVE_ONLY" == "1" ]]; then
  VERIFIED_APPS=("$EXTRACTED_APP")
else
  bundle_trees_match_without_following_symlinks "$APP" "$EXTRACTED_APP" \
    || fail "staged app and archived app contents differ"
  VERIFIED_APPS=("$APP" "$EXTRACTED_APP")
fi

for VERIFIED_APP in "${VERIFIED_APPS[@]}"; do
  APP_SCRATCH="$(/usr/bin/mktemp -d "$TEMP_DIR/app-check.XXXXXX")"
  validate_bundle_metadata "$VERIFIED_APP" "$VERSION" "$BUILD_NUMBER" "$CLASP_UPDATE_FEED_URL" "$CLASP_SPARKLE_PUBLIC_KEY" || fail "bundle metadata validation failed"
  validate_code_signing \
    "$VERIFIED_APP" \
    "$CLASP_DEVELOPER_ID_APPLICATION" \
    "$EXPECTED_TEAM_ID" \
    "$EXPECTED_CERTIFICATE_SHA256" \
    "$APP_SCRATCH" \
    || fail "code-signing validation failed"
  if [[ "$REQUIRE_NOTARIZATION" == "1" ]]; then
    validate_notarization "$VERIFIED_APP" || fail "notarization or Gatekeeper validation failed"
  fi
done

echo "verified direct release: ${ARCHIVE##*/}"
echo "archive sha256: $(/usr/bin/shasum -a 256 "$ARCHIVE" | /usr/bin/awk '{print $1}')"
echo "developer id certificate sha256: $EXPECTED_CERTIFICATE_SHA256"
echo "notarization required: $REQUIRE_NOTARIZATION"
