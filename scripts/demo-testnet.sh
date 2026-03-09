#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

: "${RPC_URL:?RPC_URL is required}"
: "${PRIVATE_KEY:?PRIVATE_KEY is required}"
: "${TOKEN0:?TOKEN0 is required}"
: "${TOKEN1:?TOKEN1 is required}"
: "${REWARD_TOKEN:?REWARD_TOKEN is required}"

echo "[demo-testnet] deploying suite"
DEPLOY_MOCKS=false TOKEN0="$TOKEN0" TOKEN1="$TOKEN1" REWARD_TOKEN="$REWARD_TOKEN" \
forge script script/DeployStableSuite.s.sol \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  --slow

CHAIN_ID="$(cast chain-id --rpc-url "$RPC_URL")"
RUN_FILE="broadcast/DeployStableSuite.s.sol/${CHAIN_ID}/run-latest.json"

HOOK="$(jq -r '.transactions[] | select(.contractName == "StableSuiteHook") | .contractAddress // empty' "$RUN_FILE" | tail -n 1)"
CONTROLLER="$(jq -r '.transactions[] | select(.contractName == "StablePolicyController") | .contractAddress // empty' "$RUN_FILE" | tail -n 1)"
INCENTIVES="$(jq -r '.transactions[] | select(.contractName == "StickyLiquidityIncentives") | .contractAddress // empty' "$RUN_FILE" | tail -n 1)"
VAULT="$(jq -r '.transactions[] | select(.contractName == "RewardsVault") | .contractAddress // empty' "$RUN_FILE" | tail -n 1)"

if [[ -z "$HOOK" || -z "$CONTROLLER" || -z "$INCENTIVES" ]]; then
  echo "[demo-testnet] failed to extract deployment addresses from $RUN_FILE" >&2
  exit 1
fi

cat > ".demo.${CHAIN_ID}.env" <<ENV
HOOK=$HOOK
CONTROLLER=$CONTROLLER
INCENTIVES=$INCENTIVES
VAULT=$VAULT
REWARD_TOKEN=$REWARD_TOKEN
TOKEN0=$TOKEN0
TOKEN1=$TOKEN1
TICK_SPACING=60
ENV

echo "[demo-testnet] running demo-all"
HOOK="$HOOK" \
CONTROLLER="$CONTROLLER" \
INCENTIVES="$INCENTIVES" \
TOKEN0="$TOKEN0" \
TOKEN1="$TOKEN1" \
DEMO_MODE=all \
forge script script/DemoStableSuite.s.sol \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  --slow

EXPLORER_TX_PREFIX="${EXPLORER_TX_PREFIX:-}"
if [[ -z "$EXPLORER_TX_PREFIX" ]]; then
  case "$CHAIN_ID" in
    84532) EXPLORER_TX_PREFIX="https://sepolia.basescan.org/tx/" ;;
    11155111) EXPLORER_TX_PREFIX="https://sepolia.etherscan.io/tx/" ;;
    *) EXPLORER_TX_PREFIX="TBD" ;;
  esac
fi

echo "[demo-testnet] deployment tx hashes"
jq -r '.transactions[] | .hash // empty' "$RUN_FILE" | while read -r h; do
  if [[ -n "$h" ]]; then
    if [[ "$EXPLORER_TX_PREFIX" == "TBD" ]]; then
      echo "  hash: $h | explorer: TBD"
    else
      echo "  hash: $h | explorer: ${EXPLORER_TX_PREFIX}${h}"
    fi
  fi
done
