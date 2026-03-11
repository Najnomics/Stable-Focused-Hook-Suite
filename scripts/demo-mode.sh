#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-all}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/demo-common.sh
source "$ROOT_DIR/scripts/demo-common.sh"

cd "$ROOT_DIR"
load_dotenv "$ROOT_DIR/.env"

RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
PRIVATE_KEY="${PRIVATE_KEY:-${SEPOLIA_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}}"
CHAIN_ID="$(cast chain-id --rpc-url "$RPC_URL")"
ENV_FILE=".demo.${CHAIN_ID}.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "missing $ENV_FILE. run scripts/demo-local.sh or scripts/demo-testnet.sh first" >&2
  exit 1
fi

load_dotenv "$ENV_FILE"

require_var HOOK
require_var CONTROLLER
require_var INCENTIVES
require_var TOKEN0
require_var TOKEN1

EXPLORER_TX_PREFIX="${EXPLORER_TX_PREFIX:-$(explorer_tx_prefix_for_chain "$CHAIN_ID")}"

print_demo_phase "MODE: ${MODE}" "Running targeted demo mode against existing deployed contracts."
HOOK="$HOOK" \
CONTROLLER="$CONTROLLER" \
INCENTIVES="$INCENTIVES" \
TOKEN0="$TOKEN0" \
TOKEN1="$TOKEN1" \
TICK_SPACING="${TICK_SPACING:-60}" \
DEMO_MODE="$MODE" \
forge script script/DemoStableSuite.s.sol \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  --slow

RUN_FILE="broadcast/DemoStableSuite.s.sol/${CHAIN_ID}/run-latest.json"
print_tx_urls_from_run_file "demo-${MODE}" "$RUN_FILE" "$EXPLORER_TX_PREFIX"
