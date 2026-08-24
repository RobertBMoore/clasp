#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "public HTTPS URL validation failed: $*" >&2
  exit 1
}

validate_shape() {
  local url="$1"
  local rest authority host label tld
  local label_count=0

  [[ -n "$url" && "$url" != *[[:space:]]* && "$url" != *[[:cntrl:]]* ]] \
    || return 1
  [[ "$url" == https://* && "$url" != *'#'* ]] || return 1
  rest="${url#https://}"
  authority="${rest%%[/?#]*}"
  [[ -n "$authority" && "$authority" != *'@'* && "$authority" != *':'* ]] || return 1
  host="$(printf '%s' "$authority" | /usr/bin/tr '[:upper:]' '[:lower:]')"
  [[ ${#host} -le 253 && "$host" == *.* ]] || return 1
  case "$host" in
    localhost|*.localhost|*.local|*.internal|*.invalid|*.test|example|*.example|\
    example.com|*.example.com|example.net|*.example.net|example.org|*.example.org) return 1 ;;
  esac

  OLD_IFS="$IFS"
  IFS='.'
  # Intentional word splitting validates each DNS label on Bash 3.2.
  # shellcheck disable=SC2086
  set -- $host
  IFS="$OLD_IFS"
  (($# >= 2)) || return 1
  for label in "$@"; do
    label_count=$((label_count + 1))
    [[ ${#label} -ge 1 && ${#label} -le 63 ]] || return 1
    [[ "$label" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ || "$label" =~ ^[a-z0-9]$ ]] || return 1
  done
  ((label_count >= 2)) || return 1
  tld="${host##*.}"
  [[ "$tld" =~ ^[a-z]{2,63}$ ]] || return 1
}

run_self_test() {
  local candidate
  validate_shape 'https://privacy.claspnotes.com/clasp'
  validate_shape 'https://support.claspnotes.app/'
  for candidate in \
    'http://privacy.example.com/clasp' \
    'https://' \
    'https://localhost/privacy' \
    'https://privacy.local/clasp' \
    'https://example.invalid/privacy' \
    'https://privacy.example.com/clasp' \
    'https://user@example.com/privacy' \
    'https://privacy.example.com:443/clasp' \
    'https://privacy.example.com/clasp#draft' \
    'https://127.0.0.1/privacy'; do
    ! validate_shape "$candidate" || fail "self-test accepted $candidate"
  done
  echo "public HTTPS URL validator self-test passed"
}

if [[ "${1:-}" == "--self-test" ]]; then
  [[ "$#" == 1 ]] || fail "--self-test accepts no other arguments"
  run_self_test
  exit 0
fi

URL="${1:-}"
REQUIRE_REACHABLE=0
[[ "$#" -ge 1 && "$#" -le 2 ]] || fail "usage: $0 URL [--require-reachable]"
if [[ "$#" == 2 ]]; then
  [[ "$2" == "--require-reachable" ]] || fail "unknown option: $2"
  REQUIRE_REACHABLE=1
fi

validate_shape "$URL" || fail "URL must use HTTPS with a public DNS host and no credentials, port, fragment, whitespace, or reserved hostname"

if [[ "$REQUIRE_REACHABLE" == 1 ]]; then
  command -v curl >/dev/null 2>&1 || fail "curl is required for reachability validation"
  CURL_RESULT="$(curl \
    --fail \
    --silent \
    --show-error \
    --location \
    --proto '=https' \
    --proto-redir '=https' \
    --connect-timeout 15 \
    --max-time 30 \
    --output /dev/null \
    --write-out '%{http_code}\n%{url_effective}' \
    "$URL")" || fail "URL is not anonymously reachable"
  HTTP_STATUS="${CURL_RESULT%%$'\n'*}"
  EFFECTIVE_URL="${CURL_RESULT#*$'\n'}"
  [[ "$HTTP_STATUS" =~ ^2[0-9][0-9]$ ]] || fail "URL did not return a successful final response"
  validate_shape "$EFFECTIVE_URL" || fail "URL redirected outside the accepted public HTTPS shape"
fi

echo "validated public HTTPS URL: $URL"
