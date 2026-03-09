#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TARGET_PERIPHERY_COMMIT="3779387e5d296f39df543d23524b050f89a62917"
PERIPHERY_DIR="lib/uniswap-hooks/lib/v4-periphery"

echo "[bootstrap] initializing submodules..."
git submodule update --init --recursive

if [[ ! -d "$PERIPHERY_DIR/.git" && ! -f "$PERIPHERY_DIR/.git" ]]; then
  echo "[bootstrap] missing $PERIPHERY_DIR" >&2
  exit 1
fi

if ! git -C "$PERIPHERY_DIR" rev-parse --verify "${TARGET_PERIPHERY_COMMIT}^{commit}" >/dev/null 2>&1; then
  echo "[bootstrap] target commit $TARGET_PERIPHERY_COMMIT is not present in $PERIPHERY_DIR" >&2
  exit 1
fi

CURRENT_PERIPHERY_COMMIT="$(git -C "$PERIPHERY_DIR" rev-parse HEAD)"
if [[ "$CURRENT_PERIPHERY_COMMIT" != "$TARGET_PERIPHERY_COMMIT" ]]; then
  echo "[bootstrap] checking out v4-periphery commit $TARGET_PERIPHERY_COMMIT"
  git -C "$PERIPHERY_DIR" checkout "$TARGET_PERIPHERY_COMMIT"
fi

EXPECTED_CORE_COMMIT="$(git -C "$PERIPHERY_DIR" ls-tree "$TARGET_PERIPHERY_COMMIT" lib/v4-core | awk '{print $3}')"
if [[ -z "$EXPECTED_CORE_COMMIT" ]]; then
  echo "[bootstrap] failed to resolve expected v4-core commit from v4-periphery" >&2
  exit 1
fi

CORE_DIR="$PERIPHERY_DIR/lib/v4-core"
git -C "$PERIPHERY_DIR" submodule update --init --recursive
CURRENT_CORE_COMMIT="$(git -C "$CORE_DIR" rev-parse HEAD)"
if [[ "$CURRENT_CORE_COMMIT" != "$EXPECTED_CORE_COMMIT" ]]; then
  echo "[bootstrap] checking out v4-core commit $EXPECTED_CORE_COMMIT"
  git -C "$CORE_DIR" checkout "$EXPECTED_CORE_COMMIT"
fi

ACTUAL_PERIPHERY_COMMIT="$(git -C "$PERIPHERY_DIR" rev-parse HEAD)"
ACTUAL_CORE_COMMIT="$(git -C "$CORE_DIR" rev-parse HEAD)"

if [[ "$ACTUAL_PERIPHERY_COMMIT" != "$TARGET_PERIPHERY_COMMIT" ]]; then
  echo "[bootstrap] mismatch: v4-periphery expected $TARGET_PERIPHERY_COMMIT got $ACTUAL_PERIPHERY_COMMIT" >&2
  exit 1
fi

if [[ "$ACTUAL_CORE_COMMIT" != "$EXPECTED_CORE_COMMIT" ]]; then
  echo "[bootstrap] mismatch: v4-core expected $EXPECTED_CORE_COMMIT got $ACTUAL_CORE_COMMIT" >&2
  exit 1
fi

echo "[bootstrap] pinned commits"
echo "  v4-periphery: $ACTUAL_PERIPHERY_COMMIT"
echo "  v4-core:      $ACTUAL_CORE_COMMIT"

echo "[bootstrap] running forge build"
forge build

echo "[bootstrap] done"
