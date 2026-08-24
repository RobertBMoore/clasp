#!/usr/bin/env bash
set -euo pipefail

SOURCE_APP="${1:-}"
PACKAGE="${2:-}"
[[ -d "$SOURCE_APP" && ! -L "$SOURCE_APP" && "$SOURCE_APP" == *.app ]] || {
  echo "a staged source app is required" >&2
  exit 1
}
[[ -f "$PACKAGE" && ! -L "$PACKAGE" && "$PACKAGE" == *.pkg ]] || {
  echo "a flat installer package is required" >&2
  exit 1
}

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/clasp-package-payload.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

PAYLOAD_LIST="$TEMP_DIR/payload-files.txt"
pkgutil --payload-files "$PACKAGE" >"$PAYLOAD_LIST"
if awk '
  /^\// || /(^|\/)\.\.($|\/)/ { unsafe = 1 }
  END { exit unsafe ? 0 : 1 }
' "$PAYLOAD_LIST"; then
  echo "installer package contains an unsafe payload path" >&2
  exit 1
fi

pkgutil --expand "$PACKAGE" "$TEMP_DIR/expanded"
PAYLOAD_COUNT="$(find "$TEMP_DIR/expanded" -type f -name Payload | wc -l | tr -d '[:space:]')"
[[ "$PAYLOAD_COUNT" == 1 ]] || {
  echo "installer package must contain exactly one component payload" >&2
  exit 1
}
PAYLOAD="$(find "$TEMP_DIR/expanded" -type f -name Payload -print -quit)"
APP_NAME="$(basename "$SOURCE_APP")"
COMPONENT_DIR="$(dirname "$PAYLOAD")"
PACKAGE_INFO="$COMPONENT_DIR/PackageInfo"
[[ -f "$PACKAGE_INFO" && ! -L "$PACKAGE_INFO" ]] || {
  echo "installer component PackageInfo is missing or unsafe" >&2
  exit 1
}
if grep -Eiq '<![[:space:]]*(DOCTYPE|ENTITY)' "$PACKAGE_INFO"; then
  echo "installer component PackageInfo contains a forbidden declaration" >&2
  exit 1
fi
xmllint --nonet --noout "$PACKAGE_INFO" 2>/dev/null || {
  echo "installer component PackageInfo is not well-formed XML" >&2
  exit 1
}

SOURCE_INFO="$SOURCE_APP/Contents/Info.plist"
[[ -f "$SOURCE_INFO" && ! -L "$SOURCE_INFO" ]] || {
  echo "staged source app Info.plist is missing or unsafe" >&2
  exit 1
}
SOURCE_IDENTIFIER="$(plutil -extract CFBundleIdentifier raw -o - "$SOURCE_INFO")"
SOURCE_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$SOURCE_INFO")"
SOURCE_BUILD="$(plutil -extract CFBundleVersion raw -o - "$SOURCE_INFO")"
xml_attribute() {
  xmllint --nonet --xpath "string($1)" "$PACKAGE_INFO" 2>/dev/null
}
[[ "$(xml_attribute '/pkg-info/@format-version')" == 2 ]] || {
  echo "installer PackageInfo format version is unexpected" >&2
  exit 1
}
[[ "$(xml_attribute '/pkg-info/@identifier')" == "$SOURCE_IDENTIFIER" ]] || {
  echo "installer PackageInfo identifier differs from the staged app" >&2
  exit 1
}
[[ "$(xml_attribute '/pkg-info/@version')" == "$SOURCE_VERSION" ]] || {
  echo "installer PackageInfo version differs from the staged app" >&2
  exit 1
}
[[ "$(xml_attribute '/pkg-info/@install-location')" == /Applications ]] || {
  echo "installer PackageInfo install location must be /Applications" >&2
  exit 1
}
[[ "$(xml_attribute '/pkg-info/@relocatable')" == false ]] || {
  echo "installer PackageInfo must not be relocatable" >&2
  exit 1
}
[[ "$(xml_attribute '/pkg-info/@postinstall-action')" == none ]] || {
  echo "installer PackageInfo contains an unexpected postinstall action" >&2
  exit 1
}
[[ "$(xml_attribute '/pkg-info/@auth')" == root ]] || {
  echo "installer PackageInfo authorization policy is unexpected" >&2
  exit 1
}
[[ "$(xml_attribute '/pkg-info/@overwrite-permissions')" == true ]] || {
  echo "installer PackageInfo permission policy is unexpected" >&2
  exit 1
}
[[ "$(xml_attribute '/pkg-info/@preserve-xattr')" == true ]] || {
  echo "installer PackageInfo must preserve extended attributes" >&2
  exit 1
}
[[ "$(xml_attribute 'count(/pkg-info/payload)')" == 1 ]] || {
  echo "installer PackageInfo must describe exactly one payload" >&2
  exit 1
}
[[ "$(xml_attribute 'count(/pkg-info/bundle)')" == 1 ]] || {
  echo "installer PackageInfo must describe exactly one app bundle" >&2
  exit 1
}
[[ "$(xml_attribute '/pkg-info/bundle/@path')" == "./$APP_NAME" ]] || {
  echo "installer PackageInfo app path is unexpected" >&2
  exit 1
}
[[ "$(xml_attribute '/pkg-info/bundle/@id')" == "$SOURCE_IDENTIFIER" ]] || {
  echo "installer PackageInfo app identifier mismatch" >&2
  exit 1
}
[[ "$(xml_attribute '/pkg-info/bundle/@CFBundleShortVersionString')" == "$SOURCE_VERSION" ]] || {
  echo "installer PackageInfo app version mismatch" >&2
  exit 1
}
[[ "$(xml_attribute '/pkg-info/bundle/@CFBundleVersion')" == "$SOURCE_BUILD" ]] || {
  echo "installer PackageInfo app build mismatch" >&2
  exit 1
}
[[ "$(xml_attribute 'count(/pkg-info/scripts)')" == 0 ]] || {
  echo "installer PackageInfo must not declare scripts" >&2
  exit 1
}

mkdir -p "$TEMP_DIR/root"
ditto -x "$PAYLOAD" "$TEMP_DIR/root"
PACKAGED_APP="$TEMP_DIR/root/$APP_NAME"
[[ -d "$PACKAGED_APP" && ! -L "$PACKAGED_APP" ]] || {
  echo "installer payload does not contain $APP_NAME at its expected root" >&2
  exit 1
}
if find "$TEMP_DIR/root" -mindepth 1 -maxdepth 1 ! -name "$APP_NAME" -print -quit | grep -q .; then
  echo "installer payload contains an unexpected top-level item" >&2
  exit 1
fi

tree_manifest() {
  local root="$1" output="$2"
  local path relative kind mode content attribute attributes xattr_digest
  local xattr_buffer="$TEMP_DIR/xattr-buffer"

  : > "$output"
  while IFS= read -r -d '' path; do
    relative="${path#"$root"}"
    [[ -n "$relative" ]] || relative='.'
    [[ "$relative" != *$'\n'* && "$relative" != *$'\r'* && "$relative" != *$'\t'* ]] || {
      echo "app payload contains a path that cannot be represented safely" >&2
      return 1
    }
    mode="$(stat -f '%Lp' "$path")"
    if [[ -L "$path" ]]; then
      kind='symlink'
      content="$(readlink "$path")"
      [[ "$content" != *$'\n'* && "$content" != *$'\r'* && "$content" != *$'\t'* ]] || {
        echo "app payload contains an unsafe symbolic-link target" >&2
        return 1
      }
    elif [[ -d "$path" ]]; then
      kind='directory'
      content='-'
    elif [[ -f "$path" ]]; then
      kind='file'
      content="$(shasum -a 256 "$path" | awk '{print $1}')"
    else
      echo "app payload contains an unsupported filesystem object: $relative" >&2
      return 1
    fi

    : > "$xattr_buffer"
    attributes="$(xattr -s "$path" | LC_ALL=C sort)"
    if [[ -n "$attributes" ]]; then
      while IFS= read -r attribute; do
        [[ -n "$attribute" && "$attribute" != *$'\t'* && "$attribute" != *$'\r'* ]] || {
          echo "app payload contains an unsafe extended-attribute name" >&2
          return 1
        }
        {
          printf '%s\n' "$attribute"
          xattr -s -px "$attribute" "$path" | tr -d '[:space:]'
          printf '\n'
        } >> "$xattr_buffer"
      done <<< "$attributes"
    fi
    xattr_digest="$(shasum -a 256 "$xattr_buffer" | awk '{print $1}')"
    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$relative" "$kind" "$mode" "$content" "$xattr_digest" >> "$output"
  done < <(find "$root" -print0 | LC_ALL=C sort -z)
}

SOURCE_MANIFEST="$TEMP_DIR/source-app.manifest"
PACKAGED_MANIFEST="$TEMP_DIR/packaged-app.manifest"
tree_manifest "$SOURCE_APP" "$SOURCE_MANIFEST"
tree_manifest "$PACKAGED_APP" "$PACKAGED_MANIFEST"
if ! cmp -s "$SOURCE_MANIFEST" "$PACKAGED_MANIFEST"; then
  diff -u "$SOURCE_MANIFEST" "$PACKAGED_MANIFEST" >&2 || true
  echo "packaged app structure, modes, links, bytes, or extended attributes differ from the validated staged app" >&2
  exit 1
fi
codesign --verify --deep --strict --verbose=2 "$PACKAGED_APP"

echo "packaged app payload and PackageInfo exactly match the validated staged app policy"
