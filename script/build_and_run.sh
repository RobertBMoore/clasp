#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Clasp"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
INSTALL_DESTINATION="/Applications/$APP_NAME.app"

case "$MODE" in
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify|--install|install|--build-only|build-only) ;;
  *) echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--install|--build-only]" >&2; exit 2 ;;
esac

cd "$ROOT_DIR"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.cache/clang"
[[ ! -e Package.resolved ]] || {
  echo "root Package.resolved is forbidden for the offline local channel" >&2
  exit 1
}
CLASP_DIRECT_DISTRIBUTION=0 swift test
[[ ! -e Package.resolved ]] || {
  echo "offline local tests unexpectedly created Package.resolved" >&2
  exit 1
}
CONFIGURATION=debug
if [[ "$MODE" == --install || "$MODE" == install ]]; then
  CONFIGURATION=release
fi
"$ROOT_DIR/script/stage_app.sh" \
  --channel local \
  --configuration "$CONFIGURATION" \
  --output "$APP_BUNDLE" \
  --replace-existing-local-output >/dev/null
"$ROOT_DIR/script/validate_app.sh" local "$APP_BUNDLE"

quit_existing_app() {
  pkill -TERM -x "$APP_NAME" >/dev/null 2>&1 || true
  pkill -TERM -x "Personal Notepad" >/dev/null 2>&1 || true
}
open_app() { quit_existing_app; /usr/bin/open -n "$APP_BUNDLE"; }
case "$MODE" in
  run) open_app ;;
  --debug|debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
  --logs|logs) open_app; /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\"" ;;
  --telemetry|telemetry) open_app; /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.robertmoore.personalnotepad"' ;;
  --verify|verify)
    open_app
    for _ in {1..20}; do pgrep -x "$APP_NAME" >/dev/null && { echo "$APP_NAME launched successfully from $APP_BUNDLE"; exit 0; }; sleep 0.25; done
    echo "$APP_NAME did not remain running" >&2; exit 1
    ;;
  --install|install)
    [[ -w /Applications ]] || { echo "/Applications is not writable; rerun from an administrator account" >&2; exit 1; }
    quit_existing_app
    "$ROOT_DIR/script/install_local_app.sh" >/dev/null
    /usr/bin/open -n "$INSTALL_DESTINATION"
    echo "$APP_NAME installed at $INSTALL_DESTINATION"
    ;;
  --build-only|build-only) echo "$APP_NAME built at $APP_BUNDLE" ;;
esac
