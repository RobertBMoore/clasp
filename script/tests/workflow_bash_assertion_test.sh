#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"

fail() {
  echo "workflow Bash assertion contract failed: $*" >&2
  exit 1
}

scan_workflow() {
  local workflow="$1"
  awk '
    function last_index(text, needle, offset, found, result) {
      offset = 1
      result = 0
      while ((found = index(substr(text, offset), needle)) > 0) {
        result = offset + found - 1
        offset = result + length(needle)
      }
      return result
    }

    function reject(message) {
      printf "%s:%d: %s\n", FILENAME, assertion_line, message > "/dev/stderr"
      invalid = 1
    }

    function validate_assertion(terminator, closing, tail) {
      terminator = assertion_kind == "bracket" ? "]]" : "))"
      closing = last_index(assertion, terminator)
      if (closing == 0) {
        reject("standalone assertion is not syntactically complete")
        return
      }
      tail = substr(assertion, closing + length(terminator))
      if (tail !~ /^[[:space:]]*\|\|[[:space:]]*\{/ \
          || tail !~ /(\{|;)[[:space:]]*exit[[:space:]]+1/ \
          || tail !~ /exit[[:space:]]+1[[:space:]]*;?[[:space:]]*\}[[:space:]]*$/) {
        reject("standalone assertion requires an explicit brace handler whose final command is exit 1")
      }
    }

    {
      raw = $0
      if (!in_assertion) {
        logical = raw
        sub(/^[[:space:]]+/, "", logical)
        sub(/\\[[:space:]]*$/, "", logical)
        if (logical ~ /^![[:space:]]*(\[\[|\(\()/ \
            || logical ~ /;[[:space:]]*!?[[:space:]]*(\[\[|\(\()/) {
          assertion_line = NR
          reject("standalone assertions must begin their own logical line without negation")
          next
        }
        if (logical ~ /^\[\[/) {
          in_assertion = 1
          assertion_kind = "bracket"
        } else if (logical ~ /^\(\(/) {
          in_assertion = 1
          assertion_kind = "arithmetic"
        } else {
          next
        }
        assertion_line = NR
        assertion = logical
      } else {
        logical = raw
        sub(/^[[:space:]]+/, "", logical)
        sub(/\\[[:space:]]*$/, "", logical)
        assertion = assertion " " logical
      }

      if (raw !~ /\\[[:space:]]*$/) {
        validate_assertion()
        in_assertion = 0
        assertion = ""
        assertion_kind = ""
      }
    }

    END {
      if (in_assertion) {
        reject("standalone assertion has an unterminated continuation")
      }
      exit invalid
    }
  ' "$workflow"
}

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/clasp-workflow-assertions.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

expect_pass() {
  local name="$1"
  local content="$2"
  local fixture="$TEMP_DIR/$name.yml"
  printf '%s\n' "$content" > "$fixture"
  scan_workflow "$fixture" || fail "expected fixture to pass: $name"
}

expect_fail() {
  local name="$1"
  local content="$2"
  local fixture="$TEMP_DIR/$name.yml"
  printf '%s\n' "$content" > "$fixture"
  if scan_workflow "$fixture" >/dev/null 2>&1; then
    fail "expected fixture to fail: $name"
  fi
}

expect_pass guarded_bracket $'run: |\n  [[ "$VALUE" == expected ]] \\\n    || { echo "invalid value" >&2; exit 1; }'
expect_pass guarded_arithmetic $'run: |\n  ((10#$NEW > 10#$OLD)) \\\n    || { echo "value did not increase" >&2; exit 1; }'
expect_pass control_flow_predicate $'run: |\n  if [[ "$VALUE" == expected ]]; then\n    echo ok\n  fi'
expect_fail unguarded_bracket $'run: |\n  [[ "$VALUE" == expected ]]'
expect_fail internal_or_only $'run: |\n  [[ "$VALUE" == first || "$VALUE" == second ]]'
expect_fail unguarded_arithmetic $'run: |\n  ((10#$NEW > 10#$OLD))'
expect_fail true_handler $'run: |\n  [[ "$VALUE" == expected ]] || true'
expect_fail echo_only_handler $'run: |\n  [[ "$VALUE" == expected ]] || { echo ignored; }'
expect_fail echoed_exit_text $'run: |\n  [[ "$VALUE" == expected ]] || { echo "exit 1"; true; }'
expect_fail echoed_exit_arguments $'run: |\n  [[ "$VALUE" == expected ]] || { echo exit 1; }'
expect_fail conditional_exit $'run: |\n  [[ "$VALUE" == expected ]] || { if false; then exit 1; fi; }'
expect_fail subshell_exit $'run: |\n  [[ "$VALUE" == expected ]] || { (exit 1); }'
expect_fail negated_assertion $'run: |\n  ! [[ "$VALUE" == expected ]] || { echo invalid >&2; exit 1; }'
expect_fail same_line_assertion $'run: |\n  set -e; [[ "$VALUE" == expected ]] || { echo invalid >&2; exit 1; }'

WORKFLOW_MANIFEST=(
  "$ROOT_DIR/.github/workflows/ci.yml" \
  "$ROOT_DIR/.github/workflows/app-store-package.yml" \
  "$ROOT_DIR/.github/workflows/direct-release-draft.yml" \
  "$ROOT_DIR/.github/workflows/direct-release-published-acceptance.yml"
)

is_manifested() {
  local candidate="$1"
  local workflow
  for workflow in "${WORKFLOW_MANIFEST[@]}"; do
    [[ "$candidate" == "$workflow" ]] && return 0
  done
  return 1
}

workflow_uses_macos_26() {
  grep -F 'macos-26' "$1" >/dev/null
}

printf '%s\n' 'runs-on: "macos-26"' > "$TEMP_DIR/double-quoted-runner.yml"
printf '%s\n' "runs-on: 'macos-26'" > "$TEMP_DIR/single-quoted-runner.yml"
printf '%s\n' 'runs-on:' '  - self-hosted' '  - macos-26' > "$TEMP_DIR/sequence-runner.yml"
workflow_uses_macos_26 "$TEMP_DIR/double-quoted-runner.yml" \
  || fail "double-quoted macos-26 runner must be discovered"
workflow_uses_macos_26 "$TEMP_DIR/single-quoted-runner.yml" \
  || fail "single-quoted macos-26 runner must be discovered"
workflow_uses_macos_26 "$TEMP_DIR/sequence-runner.yml" \
  || fail "sequence macos-26 runner must be discovered"

while IFS= read -r workflow; do
  if workflow_uses_macos_26 "$workflow" && ! is_manifested "$workflow"; then
    fail "macos-26 workflow is missing from the assertion manifest: $workflow"
  fi
done < <(find "$ROOT_DIR/.github/workflows" -type f \( -name '*.yml' -o -name '*.yaml' \) -print)

for workflow in "${WORKFLOW_MANIFEST[@]}"; do
  workflow_uses_macos_26 "$workflow" \
    || fail "assertion manifest entry no longer contains a macos-26 job: $workflow"
  scan_workflow "$workflow"
done

echo "workflow Bash assertion contracts passed"
