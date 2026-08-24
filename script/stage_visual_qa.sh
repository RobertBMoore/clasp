#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../release/config.env
# shellcheck disable=SC1091
source "$ROOT_DIR/release/config.env"

OUTPUT="${1:-$ROOT_DIR/dist/Clasp Visual QA.app}"
[[ "$OUTPUT" == *.app && "$OUTPUT" != / ]] || {
  echo "visual-QA output must be a specific .app path" >&2
  exit 2
}
[[ ! -e "$OUTPUT" && ! -L "$OUTPUT" ]] || {
  echo "refusing to overwrite existing visual-QA output: $OUTPUT" >&2
  exit 1
}
[[ "$CLASP_ARCH" == arm64 ]] || {
  echo "unsupported visual-QA architecture: $CLASP_ARCH" >&2
  exit 1
}

SCRATCH_PATH="$ROOT_DIR/.build-visual-qa"
OUT_PARENT="$(dirname "$OUTPUT")"
mkdir -p "$OUT_PARENT"
OUT_PARENT="$(cd "$OUT_PARENT" && pwd -P)"
OUTPUT="$OUT_PARENT/$(basename "$OUTPUT")"
STAGE_DIR="$(mktemp -d "$OUT_PARENT/.clasp-visual-qa.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT

cd "$ROOT_DIR"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.cache/clang"
CLASP_DIRECT_DISTRIBUTION=0 swift build \
  --scratch-path "$SCRATCH_PATH" \
  --configuration debug \
  --arch "$CLASP_ARCH" \
  -Xswiftc -DCLASP_VISUAL_QA
BIN_DIR="$(CLASP_DIRECT_DISTRIBUTION=0 swift build \
  --scratch-path "$SCRATCH_PATH" \
  --configuration debug \
  --arch "$CLASP_ARCH" \
  -Xswiftc -DCLASP_VISUAL_QA \
  --show-bin-path)"

APP="$STAGE_DIR/Clasp Visual QA.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$CLASP_APP_NAME" "$APP/Contents/MacOS/Clasp Visual QA"
cp "$ROOT_DIR/Assets/AppIcon/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/Assets/AppIcon/Clasp-AppIcon.png" "$APP/Contents/Resources/VisualQA-Sample.png"
cp "$ROOT_DIR/release/PrivacyInfo.xcprivacy" "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
cp "$ROOT_DIR/release/Info.plist" "$APP/Contents/Info.plist"

plutil -replace CFBundleExecutable -string "Clasp Visual QA" "$APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "com.robertmoore.personalnotepad.visualqa" "$APP/Contents/Info.plist"
plutil -replace CFBundleName -string "Clasp Visual QA" "$APP/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string "Clasp Visual QA" "$APP/Contents/Info.plist"
plutil -remove NSServices "$APP/Contents/Info.plist"
plutil -insert CLASPVisualQABuild -bool true "$APP/Contents/Info.plist"

codesign --force --deep --sign - "$APP"
plutil -lint "$APP/Contents/Info.plist" "$APP/Contents/Resources/PrivacyInfo.xcprivacy" >/dev/null
codesign --verify --deep --strict --verbose=2 "$APP"
[[ "$(defaults read "$APP/Contents/Info" CFBundleIdentifier)" == "com.robertmoore.personalnotepad.visualqa" ]]
[[ "$(lipo -archs "$APP/Contents/MacOS/Clasp Visual QA")" == "$CLASP_ARCH" ]]
if find "$APP" -iname '*Sparkle*' -print -quit | grep -q .; then
  echo "visual-QA app unexpectedly contains Sparkle" >&2
  exit 1
fi

mv "$APP" "$OUTPUT"
echo "$OUTPUT"
