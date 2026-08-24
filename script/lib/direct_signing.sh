#!/usr/bin/env bash

clasp_direct_signing_error() {
  echo "direct signing check failed: $*" >&2
  return 1
}

clasp_direct_is_valid_sha256() {
  [[ "${1-}" =~ ^[A-Fa-f0-9]{64}$ ]]
}

clasp_direct_uppercase_sha256() {
  printf '%s' "$1" | /usr/bin/tr '[:lower:]' '[:upper:]'
}

clasp_direct_is_valid_identity() {
  local identity="${1-}"
  [[ -n "$identity" && "$identity" != *$'\n'* && "$identity" != *'"'* ]] || return 1
  [[ "$identity" =~ ^Developer[[:space:]]ID[[:space:]]Application:.+[[:space:]]\(([A-Z0-9]{10})\)$ ]]
}

clasp_direct_team_id_from_identity() {
  local identity="${1-}"
  clasp_direct_is_valid_identity "$identity" || return 1
  [[ "$identity" =~ \(([A-Z0-9]{10})\)$ ]] || return 1
  printf '%s\n' "${BASH_REMATCH[1]}"
}

clasp_direct_is_valid_sha1() {
  [[ "${1-}" =~ ^[A-Fa-f0-9]{40}$ ]]
}

clasp_direct_identity_records_from_details() {
  /usr/bin/awk '
    /^[[:space:]]*[0-9]+\)[[:space:]]+[[:xdigit:]]+[[:space:]]+".*"$/ {
      line = $0
      sub(/^[[:space:]]*[0-9]+\)[[:space:]]*/, "", line)
      hash = line
      sub(/[[:space:]].*$/, "", hash)
      sub(/^[[:xdigit:]]+[[:space:]]+"/, "", line)
      sub(/"$/, "", line)
      if (length(hash) == 40 && hash ~ /^[[:xdigit:]]+$/) {
        printf "%s\t%s\n", toupper(hash), line
      }
    }
  '
}

clasp_direct_select_certificate_sha1() {
  local expected_sha256="$1" certificate_records="$2" selected_sha1

  clasp_direct_is_valid_sha256 "$expected_sha256" \
    || { clasp_direct_signing_error "certificate pin must be an exact 64-character SHA-256 fingerprint"; return 1; }
  expected_sha256="$(clasp_direct_uppercase_sha256 "$expected_sha256")"
  if ! selected_sha1="$(printf '%s\n' "$certificate_records" | /usr/bin/awk -F '\t' \
    -v expected="$expected_sha256" '
      NF == 0 { next }
      NF != 2 || length($1) != 64 || $1 !~ /^[[:xdigit:]]+$/ \
        || length($2) != 40 || $2 !~ /^[[:xdigit:]]+$/ { invalid = 1; next }
      toupper($1) == expected { count++; selected = toupper($2) }
      END {
        if (invalid || count != 1) exit 1
        print selected
      }
    ')"; then
    clasp_direct_signing_error "exactly one certificate with the requested SHA-256 fingerprint must match the Developer ID label"
    return 1
  fi
  clasp_direct_is_valid_sha1 "$selected_sha1" \
    || { clasp_direct_signing_error "selected Developer ID identity hash is malformed"; return 1; }
  printf '%s\n' "$selected_sha1"
}

clasp_direct_validate_selected_identity_details() {
  local identity="$1" selected_sha1="$2" identity_details="$3" match_count

  clasp_direct_is_valid_identity "$identity" \
    || { clasp_direct_signing_error "identity is not an exact Developer ID Application label"; return 1; }
  clasp_direct_is_valid_sha1 "$selected_sha1" \
    || { clasp_direct_signing_error "selected Developer ID identity hash is malformed"; return 1; }
  selected_sha1="$(clasp_direct_uppercase_sha256 "$selected_sha1")"
  match_count="$(printf '%s\n' "$identity_details" \
    | clasp_direct_identity_records_from_details \
    | /usr/bin/awk -F '\t' -v hash="$selected_sha1" -v identity="$identity" \
      '$1 == hash && $2 == identity { count++ } END { print count + 0 }')"
  [[ "$match_count" == 1 ]] \
    || { clasp_direct_signing_error "the pinned certificate must have exactly one matching valid identity and private key"; return 1; }
}

clasp_direct_resolve_identity_sha1() {
  local identity="$1" expected_sha256="$2" scratch="$3"
  local identity_details certificate_pems resolution_dir line pem_file der_file
  local certificate_count=0 in_certificate=0 certificate_records=""
  local certificate_sha256 certificate_sha1 selected_sha1

  clasp_direct_is_valid_identity "$identity" \
    || { clasp_direct_signing_error "identity is not an exact Developer ID Application label"; return 1; }
  clasp_direct_is_valid_sha256 "$expected_sha256" \
    || { clasp_direct_signing_error "certificate pin must be an exact 64-character SHA-256 fingerprint"; return 1; }
  /bin/mkdir -p "$scratch"
  [[ -d "$scratch" && ! -L "$scratch" ]] \
    || { clasp_direct_signing_error "identity-resolution scratch directory is unsafe"; return 1; }
  resolution_dir="$(/usr/bin/mktemp -d "$scratch/identity-resolution.XXXXXX")" \
    || { clasp_direct_signing_error "could not create identity-resolution directory"; return 1; }

  if ! identity_details="$(/usr/bin/security find-identity -p codesigning -v 2>&1)"; then
    printf '%s\n' "$identity_details" >&2
    clasp_direct_signing_error "could not inspect available code-signing identities"
    return 1
  fi
  if ! certificate_pems="$(/usr/bin/security find-certificate -a -c "$identity" -p 2>&1)"; then
    printf '%s\n' "$certificate_pems" >&2
    clasp_direct_signing_error "could not inspect Developer ID certificates"
    return 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      '-----BEGIN CERTIFICATE-----')
        [[ "$in_certificate" == 0 ]] \
          || { clasp_direct_signing_error "certificate output contains nested PEM blocks"; return 1; }
        certificate_count=$((certificate_count + 1))
        pem_file="$resolution_dir/candidate-$certificate_count.pem"
        printf '%s\n' "$line" > "$pem_file"
        in_certificate=1
        ;;
      '-----END CERTIFICATE-----')
        [[ "$in_certificate" == 1 ]] \
          || { clasp_direct_signing_error "certificate output contains an unmatched PEM terminator"; return 1; }
        printf '%s\n' "$line" >> "$pem_file"
        in_certificate=0
        der_file="$resolution_dir/candidate-$certificate_count.der"
        /usr/bin/openssl x509 -in "$pem_file" -inform PEM -outform DER -out "$der_file" \
          || { clasp_direct_signing_error "could not decode a Developer ID certificate"; return 1; }
        certificate_sha256="$(/usr/bin/shasum -a 256 "$der_file" \
          | /usr/bin/awk '{print toupper($1)}')"
        certificate_sha1="$(/usr/bin/shasum -a 1 "$der_file" \
          | /usr/bin/awk '{print toupper($1)}')"
        if ! clasp_direct_is_valid_sha256 "$certificate_sha256" \
          || ! clasp_direct_is_valid_sha1 "$certificate_sha1"; then
          clasp_direct_signing_error "could not fingerprint a Developer ID certificate"
          return 1
        fi
        [[ -z "$certificate_records" ]] || certificate_records+=$'\n'
        certificate_records+="$certificate_sha256"$'\t'"$certificate_sha1"
        ;;
      '') ;;
      *)
        if [[ "$in_certificate" == 1 ]]; then
          printf '%s\n' "$line" >> "$pem_file"
        else
          clasp_direct_signing_error "certificate output contains unexpected non-PEM data"
          return 1
        fi
        ;;
    esac
  done <<< "$certificate_pems"

  [[ "$in_certificate" == 0 && "$certificate_count" -gt 0 ]] \
    || { clasp_direct_signing_error "certificate output is empty or incomplete"; return 1; }
  selected_sha1="$(clasp_direct_select_certificate_sha1 \
    "$expected_sha256" "$certificate_records")" || return 1
  clasp_direct_validate_selected_identity_details \
    "$identity" "$selected_sha1" "$identity_details" || return 1
  printf '%s\n' "$selected_sha1"
}

clasp_direct_signed_path_certificate_sha256() {
  local path="$1" scratch="$2" absolute_path extract_dir fingerprint

  [[ -e "$path" && ! -L "$path" ]] \
    || { clasp_direct_signing_error "signed path is missing or unsafe: $path"; return 1; }
  /bin/mkdir -p "$scratch"
  [[ -d "$scratch" && ! -L "$scratch" ]] \
    || { clasp_direct_signing_error "certificate scratch directory is unsafe"; return 1; }
  absolute_path="$(cd "$(/usr/bin/dirname "$path")" && pwd -P)/$(/usr/bin/basename "$path")"
  extract_dir="$(/usr/bin/mktemp -d "$scratch/leaf-certificate.XXXXXX")" \
    || { clasp_direct_signing_error "could not create certificate extraction directory"; return 1; }
  if ! (cd "$extract_dir" \
    && /usr/bin/codesign --display --extract-certificates "$absolute_path" >/dev/null 2>&1); then
    clasp_direct_signing_error "could not extract the signing certificate from $path"
    return 1
  fi
  [[ -f "$extract_dir/codesign0" && ! -L "$extract_dir/codesign0" ]] \
    || { clasp_direct_signing_error "signing leaf certificate is missing from $path"; return 1; }
  fingerprint="$(/usr/bin/shasum -a 256 "$extract_dir/codesign0" \
    | /usr/bin/awk '{print toupper($1)}')"
  clasp_direct_is_valid_sha256 "$fingerprint" \
    || { clasp_direct_signing_error "could not fingerprint the signing certificate on $path"; return 1; }
  printf '%s\n' "$fingerprint"
}

clasp_direct_require_signed_path_certificate() {
  local path="$1" expected_sha256="$2" scratch="$3" actual_sha256

  clasp_direct_is_valid_sha256 "$expected_sha256" \
    || { clasp_direct_signing_error "certificate pin must be an exact 64-character SHA-256 fingerprint"; return 1; }
  expected_sha256="$(clasp_direct_uppercase_sha256 "$expected_sha256")"
  actual_sha256="$(clasp_direct_signed_path_certificate_sha256 "$path" "$scratch")" || return 1
  [[ "$actual_sha256" == "$expected_sha256" ]] \
    || { clasp_direct_signing_error "signed leaf certificate fingerprint mismatch on $path"; return 1; }
}
