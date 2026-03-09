#!/usr/bin/env bash
set -euo pipefail

CHAIN_ID="${1:-31337}"
RUN_FILE="broadcast/DeployStableSuite.s.sol/${CHAIN_ID}/run-latest.json"
OUT_FILE=".demo.${CHAIN_ID}.env"

if [[ ! -f "$RUN_FILE" ]]; then
  echo "missing deployment file: $RUN_FILE" >&2
  exit 1
fi

extract_single() {
  local name="$1"
  jq -r --arg n "$name" '.transactions[] | select(.contractName == $n) | .contractAddress // empty' "$RUN_FILE" | tail -n 1
}

HOOK="$(extract_single "StableSuiteHook")"
CONTROLLER="$(extract_single "StablePolicyController")"
INCENTIVES="$(extract_single "StickyLiquidityIncentives")"
VAULT="$(extract_single "RewardsVault")"
REWARD_TOKEN="$(extract_single "MockRewardToken")"

TOKEN_LINES="$(jq -r '.transactions[] | select(.contractName == "MockStablecoin") | .contractAddress // empty' "$RUN_FILE")"
TOKEN0="$(echo "$TOKEN_LINES" | sed -n '1p')"
TOKEN1="$(echo "$TOKEN_LINES" | sed -n '2p')"

if [[ -z "$HOOK" || -z "$CONTROLLER" || -z "$INCENTIVES" ]]; then
  echo "missing required deployment addresses in $RUN_FILE" >&2
  exit 1
fi

cat > "$OUT_FILE" <<ENV
HOOK=$HOOK
CONTROLLER=$CONTROLLER
INCENTIVES=$INCENTIVES
VAULT=$VAULT
REWARD_TOKEN=$REWARD_TOKEN
TOKEN0=$TOKEN0
TOKEN1=$TOKEN1
TICK_SPACING=60
ENV

echo "wrote $OUT_FILE"
cat "$OUT_FILE"
