#!/usr/bin/env bash

app_store_die() {
  echo "error: $*" >&2
  exit 1
}

app_store_require_command() {
  command -v "$1" >/dev/null 2>&1 || app_store_die "required command is unavailable: $1"
}

app_store_require_single_line() {
  local label="$1" value="$2"
  [[ -n "$value" && "$value" != *$'\n'* && "$value" != *'"'* ]] \
    || app_store_die "$label must be a nonempty, single-line value without quotes"
}

app_store_identity_names() {
  local kind="$1"
  if [[ "$kind" == application ]]; then
    security find-identity -v -p codesigning
  else
    # Apple documents that installer identities are not code-signing
    # identities, so applying `-p codesigning` would hide them.
    security find-identity -v
  fi | sed -nE 's/^[[:space:]]*[0-9]+\) [[:xdigit:]]+ "(.*)"$/\1/p'
}

app_store_require_identity() {
  local kind="$1" identity="$2"
  app_store_require_single_line "$kind signing identity" "$identity"
  case "$kind:$identity" in
    application:'Apple Distribution: '*|application:'3rd Party Mac Developer Application: '*) ;;
    installer:'3rd Party Mac Developer Installer: '*|installer:'Mac Installer Distribution: '*) ;;
    *) app_store_die "$identity is not an accepted Mac App Store $kind identity label" ;;
  esac
  app_store_identity_names "$kind" | grep -Fx -- "$identity" >/dev/null \
    || app_store_die "exact $kind signing identity is unavailable: $identity"
}

app_store_profile_certificate_matches_identity() {
  local profile_plist="$1" identity="$2"
  local encoded profile_hash identity_hashes
  encoded="$(plutil -extract DeveloperCertificates.0 raw -o - "$profile_plist")" \
    || app_store_die "profile has no distribution certificate"
  profile_hash="$(printf '%s' "$encoded" | base64 --decode | shasum -a 256 | awk '{print toupper($1)}')" \
    || app_store_die "could not fingerprint the profile distribution certificate"
  identity_hashes="$(security find-certificate -a -c "$identity" -Z 2>/dev/null \
    | awk '/SHA-256 hash:/ {print toupper($3)}')"
  printf '%s\n' "$identity_hashes" | grep -Fx -- "$profile_hash" >/dev/null \
    || app_store_die "the provisioning profile does not contain the exact application signing certificate"
}
