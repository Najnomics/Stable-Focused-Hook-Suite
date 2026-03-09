#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-all}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
PRIVATE_KEY="${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
CHAIN_ID="$(cast chain-id --rpc-url "$RPC_URL")"
ENV_FILE=".demo.${CHAIN_ID}.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "missing $ENV_FILE. run scripts/demo-local.sh or scripts/demo-testnet.sh first" >&2
  exit 1
fi

source "$ENV_FILE"

HOOK="$HOOK" \
CONTROLLER="$CONTROLLER" \
INCENTIVES="$INCENTIVES" \
TOKEN0="$TOKEN0" \
TOKEN1="$TOKEN1" \
DEMO_MODE="$MODE" \
forge script script/DemoStableSuite.s.sol \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  --slow

RUN_FILE="broadcast/DemoStableSuite.s.sol/${CHAIN_ID}/run-latest.json"
echo "[demo-${MODE}] tx hashes"
jq -r '.transactions[] | "  " + (.contractName // "call") + " " + (.hash // "")' "$RUN_FILE"
