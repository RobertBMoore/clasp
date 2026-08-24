#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
VALIDATOR="$ROOT_DIR/script/validate_app_store_screenshots.sh"
VALID_SET="$ROOT_DIR/release/AppStore/Screenshots"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

fail() {
  echo "App Store screenshot fixture failed: $*" >&2
  exit 1
}

write_manifest() {
  local directory="$1"
  (cd "$directory" && shasum -a 256 ./*.jpg > SHA256SUMS)
  sed -i '' 's#  \./#  #' "$directory/SHA256SUMS"
}

"$VALIDATOR" "$VALID_SET"

mkdir "$TEMP_DIR/wrong-size"
cp "$VALID_SET/01-clasp-editor-light-2560x1600.jpg" "$TEMP_DIR/wrong-size/shot.jpg"
sips -z 100 100 "$TEMP_DIR/wrong-size/shot.jpg" >/dev/null
write_manifest "$TEMP_DIR/wrong-size"
if "$VALIDATOR" "$TEMP_DIR/wrong-size" >/dev/null 2>&1; then
  fail "wrong-size screenshot was accepted"
fi

mkdir "$TEMP_DIR/too-many"
for index in {01..11}; do
  cp "$VALID_SET/01-clasp-editor-light-2560x1600.jpg" "$TEMP_DIR/too-many/$index.jpg"
done
write_manifest "$TEMP_DIR/too-many"
if "$VALIDATOR" "$TEMP_DIR/too-many" >/dev/null 2>&1; then
  fail "an 11-image set was accepted"
fi

mkdir "$TEMP_DIR/symlink"
ln -s "$VALID_SET/01-clasp-editor-light-2560x1600.jpg" "$TEMP_DIR/symlink/shot.jpg"
if "$VALIDATOR" "$TEMP_DIR/symlink" >/dev/null 2>&1; then
  fail "a symbolic-link screenshot was accepted"
fi

echo "App Store screenshot fixtures passed"
