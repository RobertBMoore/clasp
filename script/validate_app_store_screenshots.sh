#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCREENSHOT_DIR="${1:-$ROOT_DIR/release/AppStore/Screenshots}"

fail() {
  echo "App Store screenshot validation failed: $*" >&2
  exit 1
}

[[ -d "$SCREENSHOT_DIR" && ! -L "$SCREENSHOT_DIR" ]] \
  || fail "screenshot directory is missing or unsafe: $SCREENSHOT_DIR"

if find "$SCREENSHOT_DIR" -mindepth 1 -maxdepth 1 -type l -print -quit | grep -q .; then
  fail "symbolic links are not allowed"
fi

if find "$SCREENSHOT_DIR" -mindepth 1 -maxdepth 1 -type d -print -quit | grep -q .; then
  fail "nested directories are not allowed"
fi

images=()
while IFS= read -r -d '' path; do
  images+=("$path")
done < <(find "$SCREENSHOT_DIR" -mindepth 1 -maxdepth 1 -type f \
  \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) -print0)

count="${#images[@]}"
((count >= 1 && count <= 10)) \
  || fail "expected 1–10 JPEG or PNG files, found $count"

while IFS= read -r -d '' path; do
  case "$(basename "$path")" in
    README.md|SHA256SUMS|*.jpg|*.JPG|*.jpeg|*.JPEG|*.png|*.PNG) ;;
    *) fail "unexpected file: $path" ;;
  esac
done < <(find "$SCREENSHOT_DIR" -mindepth 1 -maxdepth 1 -type f -print0)

for image in "${images[@]}"; do
  [[ -f "$image" && ! -L "$image" ]] || fail "unsafe screenshot path: $image"

  properties="$(sips -g pixelWidth -g pixelHeight -g hasAlpha -g format "$image" 2>/dev/null)" \
    || fail "could not inspect image: $image"
  width="$(awk '/pixelWidth:/ {print $2}' <<<"$properties")"
  height="$(awk '/pixelHeight:/ {print $2}' <<<"$properties")"
  alpha="$(awk '/hasAlpha:/ {print $2}' <<<"$properties")"
  format="$(awk '/format:/ {print $2}' <<<"$properties")"

  case "${width}x${height}" in
    1280x800|1440x900|2560x1600|2880x1800) ;;
    *) fail "unsupported dimensions for $(basename "$image"): ${width}x${height}" ;;
  esac
  [[ "$alpha" == no ]] || fail "transparency is not allowed: $image"
  [[ "$format" == jpeg || "$format" == png ]] \
    || fail "unsupported image format for $image: $format"
done

manifest="$SCREENSHOT_DIR/SHA256SUMS"
[[ -f "$manifest" && ! -L "$manifest" ]] || fail "SHA256SUMS is missing or unsafe"
[[ "$(wc -l < "$manifest" | tr -d ' ')" == "$count" ]] \
  || fail "SHA256SUMS entry count does not match the screenshot count"
while IFS= read -r line; do
  grep -Eq '^[0-9a-f]{64}  [A-Za-z0-9._-]+\.(jpg|jpeg|png)$' <<<"$line" \
    || fail "malformed SHA256SUMS entry"
done < "$manifest"

manifest_names="$(awk '{print $2}' "$manifest" | LC_ALL=C sort)"
image_names="$(for image in "${images[@]}"; do basename "$image"; done | LC_ALL=C sort)"
[[ "$manifest_names" == "$image_names" ]] \
  || fail "SHA256SUMS does not name the exact screenshot set"
(cd "$SCREENSHOT_DIR" && shasum -a 256 -c SHA256SUMS >/dev/null) \
  || fail "screenshot checksum mismatch"

printf 'validated %s App Store screenshot(s): %s\n' "$count" "$SCREENSHOT_DIR"
