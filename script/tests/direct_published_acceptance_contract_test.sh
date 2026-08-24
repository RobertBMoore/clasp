#!/usr/bin/env bash
# The GitHub expressions and shell-variable text below are intentionally literal.
# shellcheck disable=SC2016
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/direct-release-published-acceptance.yml"

require_literal() {
  local expected="$1"
  grep -F -- "$expected" "$WORKFLOW" >/dev/null || {
    echo "published-release workflow is missing: $expected" >&2
    exit 1
  }
}

[[ -f "$WORKFLOW" ]] || {
  echo "published-release workflow is missing" >&2
  exit 1
}

if grep -F 'ref: ${{ github.event.release.tag_name }}' "$WORKFLOW" >/dev/null; then
  echo "published-release verifier must never execute from the release tag" >&2
  exit 1
fi

require_literal 'ref: ${{ github.workflow_sha }}'
require_literal 'persist-credentials: false'
require_literal 'path: trusted-source'
require_literal "--jq '.protected'"
require_literal 'git -C trusted-source merge-base --is-ancestor'
require_literal './trusted-source/script/verify_direct_release.sh'
require_literal '--require-notarization --archive-only'
require_literal '--arg verifier_sha "$TRUSTED_WORKFLOW_SHA"'
require_literal 'PUBLIC_ARCHIVE_URL="https://github.com/$GITHUB_REPOSITORY/releases/download/$RELEASE_TAG/${ARCHIVE##*/}"'
require_literal 'cmp -s "$ARCHIVE" "$RUNNER_TEMP/public-archive.zip"'
require_literal 'cmp -s "$ARCHIVE.sha256" "$RUNNER_TEMP/public-archive.zip.sha256"'

echo "published direct-release acceptance contract passed"
