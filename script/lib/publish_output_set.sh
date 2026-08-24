#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck source=output_custody.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/script/lib/output_custody.sh"

[[ "${1:-}" == --mover && -n "${2:-}" ]] || {
  echo "usage: $0 --mover MOVER --preserve-marker MARKER LABEL SOURCE DESTINATION [...]" >&2
  exit 2
}
MOVER="$2"
shift 2
[[ "${1:-}" == --preserve-marker && -n "${2:-}" ]] || {
  echo "missing --preserve-marker" >&2
  exit 2
}
PRESERVE_MARKER="$2"
shift 2
(("$#" >= 3 && "$#" % 3 == 0)) || {
  echo "publication entries must be LABEL SOURCE DESTINATION triples" >&2
  exit 2
}

[[ -x "$MOVER" && ! -L "$MOVER" ]] || {
  echo "publication mover is missing or unsafe" >&2
  exit 1
}
clasp_require_canonical_absolute_path "$PRESERVE_MARKER" "publication preservation marker"
clasp_require_physical_directory "$(dirname "$PRESERVE_MARKER")" "publication staging root"
[[ ! -e "$PRESERVE_MARKER" && ! -L "$PRESERVE_MARKER" ]] || {
  echo "publication preservation marker already exists" >&2
  exit 1
}

LABELS=()
SOURCES=()
DESTINATIONS=()
PUBLISHED=()
while (($#)); do
  label="$1"
  source_path="$2"
  destination="$3"
  shift 3
  [[ "$label" =~ ^[A-Za-z0-9_-]+$ ]] || {
    echo "unsafe publication label: $label" >&2
    exit 1
  }
  clasp_require_canonical_absolute_path "$source_path" "$label publication source"
  clasp_require_canonical_absolute_path "$destination" "$label publication destination"
  clasp_require_physical_directory "$(dirname "$source_path")" "$label publication source parent"
  clasp_require_physical_directory "$(dirname "$destination")" "$label publication destination parent"
  [[ -e "$source_path" && ! -L "$source_path" ]] || {
    echo "$label publication source is missing or unsafe: $source_path" >&2
    exit 1
  }
  [[ ! -e "$destination" && ! -L "$destination" ]] || {
    echo "refusing to overwrite existing $label publication destination: $destination" >&2
    exit 1
  }
  LABELS+=("$label")
  SOURCES+=("$source_path")
  DESTINATIONS+=("$destination")
  PUBLISHED+=(0)
done

CURRENT_INDEX=-1
PUBLICATION_COMPLETE=0
cleanup() {
  local status=$?
  local rollback_failed=0
  local index

  if ((PUBLICATION_COMPLETE == 0)); then
    if ((CURRENT_INDEX >= 0)) \
      && [[ ! -e "${SOURCES[$CURRENT_INDEX]}" && ! -L "${SOURCES[$CURRENT_INDEX]}" ]]; then
      PUBLISHED[CURRENT_INDEX]=1
    fi
    for ((index=${#SOURCES[@]} - 1; index >= 0; index--)); do
      if ((PUBLISHED[index])); then
        if ! "$MOVER" "${DESTINATIONS[$index]}" "${SOURCES[$index]}"; then
          echo "failed to roll back ${LABELS[$index]} publication" >&2
          rollback_failed=1
        fi
      fi
    done
    if ((rollback_failed)); then
      (set -o noclobber; : >"$PRESERVE_MARKER") 2>/dev/null || true
      status=1
    fi
  fi
  return "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

for ((index=0; index < ${#SOURCES[@]}; index++)); do
  CURRENT_INDEX=$index
  "$MOVER" "${SOURCES[$index]}" "${DESTINATIONS[$index]}"
  PUBLISHED[index]=1
  CURRENT_INDEX=-1
done
PUBLICATION_COMPLETE=1
