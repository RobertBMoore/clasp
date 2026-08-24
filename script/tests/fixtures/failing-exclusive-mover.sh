#!/usr/bin/env bash
set -euo pipefail

: "${CLASP_TEST_REAL_MOVER:?missing real mover}"
: "${CLASP_TEST_MOVER_STATE:?missing mover state file}"
: "${CLASP_TEST_MOVER_MODE:?missing mover mode}"
[[ "$#" == 2 ]] || exit 2

count=0
[[ ! -f "$CLASP_TEST_MOVER_STATE" ]] || read -r count <"$CLASP_TEST_MOVER_STATE"
count=$((count + 1))
printf '%s\n' "$count" >"$CLASP_TEST_MOVER_STATE"

case "$CLASP_TEST_MOVER_MODE:$count" in
  destination-race:2)
    mkdir "$2"
    touch "$2/late-destination"
    exit 75
    ;;
  restore-failure:2|restore-failure:3)
    exit 75
    ;;
  publish-second-failure:2)
    exit 75
    ;;
  publish-third-failure:3)
    exit 75
    ;;
  publish-rollback-failure:2|publish-rollback-failure:3)
    exit 75
    ;;
esac

exec "$CLASP_TEST_REAL_MOVER" "$1" "$2"
