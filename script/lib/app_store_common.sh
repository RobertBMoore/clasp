#!/usr/bin/env bash

app_store_die() {
  echo "error: $*" >&2
  exit 1
}

app_store_require_command() {
  command -v "$1" >/dev/null 2>&1 || app_store_die "required command is unavailable: $1"
}

app_store_symbol_list_contains_selection_capture() {
  local symbols="${1-}"
  local forbidden_api_pattern='(^|[[:space:]])_?(CGPreflightPostEventAccess|CGRequestPostEventAccess|CGEventCreateKeyboardEvent|CGEventPost)([[:space:]]|$)'

  [[ "$symbols" == *SelectionCaptureService* || "$symbols" =~ $forbidden_api_pattern ]]
}

app_store_package_signature_status_is_accepted() {
  local details="${1-}"
  # Developer ID Installer packages are locally trusted. Mac App Store
  # submission packages use Mac Installer Distribution credentials, whose
  # verified Apple package-signing policy is reported as Apple Development.
  printf '%s\n' "$details" | grep -Eq \
    '^[[:space:]]*Status: signed by (a certificate trusted by macOS|a developer certificate issued by Apple \(Development\))[[:space:]]*$'
}

app_store_require_sha256() {
  local label="$1" value="$2"
  [[ "$value" =~ ^[A-Fa-f0-9]{64}$ ]] \
    || app_store_die "$label must be an exact 64-character SHA-256 fingerprint"
}

app_store_uppercase_sha256() {
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

app_store_package_leaf_identity() {
  awk '
    /^[[:space:]]*Certificate Chain:[[:space:]]*$/ { in_chain = 1; next }
    in_chain && /^[[:space:]]*1\. / {
      line = $0
      sub(/^[[:space:]]*1\.[[:space:]]*/, "", line)
      print line
      exit
    }
  '
}

app_store_package_leaf_block() {
  awk '
    /^[[:space:]]*Certificate Chain:[[:space:]]*$/ { in_chain = 1; next }
    in_chain && /^[[:space:]]*1\. / { in_leaf = 1 }
    in_leaf && /^[[:space:]]*2\. / { exit }
    in_leaf { print }
  '
}

app_store_package_leaf_sha256() {
  awk '
    /^[[:space:]]*SHA256 Fingerprint:[[:space:]]*$/ { capture = 1; next }
    capture {
      if ($0 ~ /^[[:space:]]*-+[[:space:]]*$/) {
        if (!invalid && byte_count == 32) print hash
        exit
      }
      line = $0
      sub(/^[[:space:]]*/, "", line)
      sub(/[[:space:]]*$/, "", line)
      if (line == "") {
        invalid = 1
        next
      }
      field_count = split(line, fields, /[[:space:]]+/)
      for (i = 1; i <= field_count; i++) {
        if (fields[i] !~ /^[[:xdigit:]][[:xdigit:]]$/) {
          invalid = 1
          next
        }
        byte_count++
        if (byte_count > 32) {
          invalid = 1
          next
        }
        hash = hash toupper(fields[i])
      }
    }
  '
}

app_store_profile_xattrs_are_safe() {
  local attributes="${1-}" attribute
  while IFS= read -r attribute; do
    case "$attribute" in
      ""|com.apple.macl|com.apple.provenance) ;;
      *) return 1 ;;
    esac
  done <<EOF
$attributes
EOF
}

app_store_clear_profile_download_xattrs() {
  local profile="$1" remaining
  xattr -c "$profile"
  remaining="$(xattr "$profile")"
  app_store_profile_xattrs_are_safe "$remaining" || {
    printf 'unexpected extended attributes remain on provisioning profile:\n%s\n' \
      "$remaining" >&2
    return 1
  }
}

app_store_validate_package_signature_details() {
  local details="$1" identity="$2" expected_sha256="$3"
  local status_count chain_count leaf_count leaf_block fingerprint_count
  local leaf_identity leaf_sha256

  app_store_require_single_line "installer signing identity" "$identity"
  app_store_require_sha256 "installer certificate" "$expected_sha256"
  expected_sha256="$(app_store_uppercase_sha256 "$expected_sha256")"
  status_count="$(printf '%s\n' "$details" | grep -Ec '^[[:space:]]*Status:' || true)"
  [[ "$status_count" == 1 ]] || return 1
  app_store_package_signature_status_is_accepted "$details" || return 1
  chain_count="$(printf '%s\n' "$details" \
    | grep -Ec '^[[:space:]]*Certificate Chain:[[:space:]]*$' || true)"
  [[ "$chain_count" == 1 ]] || return 1
  leaf_count="$(printf '%s\n' "$details" \
    | grep -Ec '^[[:space:]]*1\.[[:space:]]+' || true)"
  [[ "$leaf_count" == 1 ]] || return 1
  leaf_identity="$(printf '%s\n' "$details" | app_store_package_leaf_identity)"
  [[ "$leaf_identity" == "$identity" ]] || return 1
  leaf_block="$(printf '%s\n' "$details" | app_store_package_leaf_block)"
  fingerprint_count="$(printf '%s\n' "$leaf_block" \
    | grep -Ec '^[[:space:]]*SHA256 Fingerprint:[[:space:]]*$' || true)"
  [[ "$fingerprint_count" == 1 ]] || return 1
  leaf_sha256="$(printf '%s\n' "$leaf_block" | app_store_package_leaf_sha256)"
  [[ "$leaf_sha256" == "$expected_sha256" ]] || return 1
}

app_store_verify_package_signature() {
  local package="$1" identity="$2" expected_sha256="$3" details
  if ! details="$(/usr/sbin/pkgutil --check-signature "$package" 2>&1)"; then
    printf '%s\n' "$details" >&2
    return 1
  fi
  printf '%s\n' "$details"
  app_store_validate_package_signature_details "$details" "$identity" "$expected_sha256"
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
  local kind="$1" identity="$2" match_count
  app_store_require_single_line "$kind signing identity" "$identity"
  case "$kind:$identity" in
    application:'Apple Distribution: '*|application:'3rd Party Mac Developer Application: '*) ;;
    installer:'3rd Party Mac Developer Installer: '*|installer:'Mac Installer Distribution: '*) ;;
    *) app_store_die "$identity is not an accepted Mac App Store $kind identity label" ;;
  esac
  match_count="$(app_store_identity_names "$kind" | awk -v expected="$identity" \
    '$0 == expected { count++ } END { print count + 0 }')"
  [[ "$match_count" == 1 ]] \
    || app_store_die "exactly one $kind signing identity must be available for: $identity"
}

app_store_require_identity_certificate() {
  local kind="$1" identity="$2" expected_sha256="$3"
  local matching_hashes match_count
  app_store_require_identity "$kind" "$identity"
  app_store_require_sha256 "$kind certificate" "$expected_sha256"
  expected_sha256="$(app_store_uppercase_sha256 "$expected_sha256")"
  matching_hashes="$(security find-certificate -a -c "$identity" -Z 2>/dev/null \
    | awk '/SHA-256 hash:/ {print toupper($3)}')"
  match_count="$(printf '%s\n' "$matching_hashes" | awk -v expected="$expected_sha256" \
    '$0 == expected { count++ } END { print count + 0 }')"
  [[ "$match_count" == 1 ]] \
    || app_store_die "exactly one $kind certificate must match fingerprint $expected_sha256"
}

app_store_profile_certificate_matches_identity() {
  local profile_plist="$1" identity="$2" expected_sha256="$3"
  local encoded profile_hash identity_hashes
  app_store_require_sha256 "application certificate" "$expected_sha256"
  expected_sha256="$(app_store_uppercase_sha256 "$expected_sha256")"
  encoded="$(plutil -extract DeveloperCertificates.0 raw -o - "$profile_plist")" \
    || app_store_die "profile has no distribution certificate"
  profile_hash="$(printf '%s' "$encoded" | base64 --decode | shasum -a 256 | awk '{print toupper($1)}')" \
    || app_store_die "could not fingerprint the profile distribution certificate"
  identity_hashes="$(security find-certificate -a -c "$identity" -Z 2>/dev/null \
    | awk '/SHA-256 hash:/ {print toupper($3)}')"
  [[ "$profile_hash" == "$expected_sha256" ]] \
    || app_store_die "the provisioning profile certificate fingerprint is unexpected"
  printf '%s\n' "$identity_hashes" | grep -Fx -- "$expected_sha256" >/dev/null \
    || app_store_die "the provisioning profile does not contain the exact application signing certificate"
}
