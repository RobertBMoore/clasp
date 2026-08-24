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

if grep -Eq '^[[:space:]]+environment:' "$WORKFLOW"; then
  echo "tag-triggered published acceptance must not bind to the protected-branches-only release environment" >&2
  exit 1
fi

if grep -F 'ref: ${{ github.event.release.tag_name }}' "$WORKFLOW" >/dev/null; then
  echo "published-release verifier must never execute from the release tag" >&2
  exit 1
fi

require_literal 'ref: ${{ github.workflow_sha }}'
require_literal 'cancel-in-progress: false'
require_literal 'queue: max'
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
for repository_variable in \
  CLASP_PUBLISHED_UPDATE_FEED_URL \
  CLASP_PUBLISHED_SPARKLE_PUBLIC_KEY \
  CLASP_PUBLISHED_DEVELOPER_ID_APPLICATION_IDENTITY \
  CLASP_PUBLISHED_DEVELOPER_ID_APPLICATION_CERTIFICATE_SHA256; do
  [[ "$(grep -Fc "vars.$repository_variable" "$WORKFLOW")" == 1 ]] || {
    echo "published-release workflow must read repository variable: $repository_variable" >&2
    exit 1
  }
done
for protected_environment_variable in \
  CLASP_UPDATE_FEED_URL \
  CLASP_SPARKLE_PUBLIC_KEY \
  DEVELOPER_ID_APPLICATION_IDENTITY \
  DEVELOPER_ID_APPLICATION_CERTIFICATE_SHA256; do
  if grep -F "vars.$protected_environment_variable" "$WORKFLOW" >/dev/null; then
    echo "published-release repository variables must not shadow protected environment variable: $protected_environment_variable" >&2
    exit 1
  fi
done
require_literal 'source trusted-source/script/lib/direct_signing.sh'
require_literal 'clasp_direct_is_valid_sha256 "$DEVELOPER_ID_CERTIFICATE_SHA256"'
require_literal 'CLASP_DEVELOPER_ID_APPLICATION_CERTIFICATE_SHA256="$DEVELOPER_ID_CERTIFICATE_SHA256"'
require_literal '--arg developer_id_application_certificate_sha256 "$DEVELOPER_ID_CERTIFICATE_SHA256"'

echo "published direct-release acceptance contract passed"
