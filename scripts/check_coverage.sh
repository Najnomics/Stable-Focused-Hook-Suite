#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

forge coverage --exclude-tests --no-match-coverage '^script/' "$@" | tee "$TMP_FILE"

TOTAL_LINE="$(grep -E '^\| Total[[:space:]]+\|' "$TMP_FILE" | tail -n 1 || true)"
if [[ -z "$TOTAL_LINE" ]]; then
  echo "[coverage] failed to locate Total row in coverage output" >&2
  exit 1
fi

for col in 3 4 5 6; do
  metric="$(echo "$TOTAL_LINE" | awk -F'|' -v c="$col" '{gsub(/^[ \t]+|[ \t]+$/, "", $c); print $c}')"
  if [[ "$metric" != 100.00%* ]]; then
    echo "[coverage] expected 100% source coverage, got: $TOTAL_LINE" >&2
    exit 1
  fi
done

echo "[coverage] source coverage is 100% for lines/statements/branches/functions"
