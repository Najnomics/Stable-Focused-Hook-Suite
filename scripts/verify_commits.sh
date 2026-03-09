#!/usr/bin/env bash
set -euo pipefail

EXPECTED_COUNT="${1:-300}"
ACTUAL_COUNT="$(git rev-list --count HEAD)"

if [[ "$ACTUAL_COUNT" != "$EXPECTED_COUNT" ]]; then
  echo "commit count mismatch: expected=$EXPECTED_COUNT actual=$ACTUAL_COUNT" >&2
  exit 1
fi

echo "commit count verified: $ACTUAL_COUNT"
