#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
PRIVATE_KEY="${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"

if ! curl -s "$RPC_URL" >/dev/null 2>&1; then
  echo "[demo-local] anvil not detected at $RPC_URL, starting background anvil"
  anvil --host 127.0.0.1 --port 8545 >/tmp/stable-suite-anvil.log 2>&1 &
  ANVIL_PID=$!
  trap 'kill ${ANVIL_PID:-0} >/dev/null 2>&1 || true' EXIT
  sleep 2
fi

echo "[demo-local] deploying suite"
DEPLOY_MOCKS=true forge script script/DeployStableSuite.s.sol \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  --slow

CHAIN_ID="$(cast chain-id --rpc-url "$RPC_URL")"
"$ROOT_DIR/scripts/extract_deploy_env.sh" "$CHAIN_ID"
source ".demo.${CHAIN_ID}.env"

echo "[demo-local] running full demo"
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

DEPLOY_RUN="broadcast/DeployStableSuite.s.sol/${CHAIN_ID}/run-latest.json"
DEMO_RUN="broadcast/DemoStableSuite.s.sol/${CHAIN_ID}/run-latest.json"

echo "[demo-local] deployed addresses"
echo "  hook:        $HOOK"
echo "  controller:  $CONTROLLER"
echo "  incentives:  $INCENTIVES"
echo "  vault:       $VAULT"
echo "  rewardToken: $REWARD_TOKEN"
echo "  token0:      $TOKEN0"
echo "  token1:      $TOKEN1"

echo "[demo-local] deployment tx hashes"
jq -r '.transactions[] | "  " + (.transactionType // "tx") + " " + (.contractName // "call") + " " + (.hash // "")' "$DEPLOY_RUN"

echo "[demo-local] demo tx hashes"
jq -r '.transactions[] | "  " + (.transactionType // "tx") + " " + (.contractName // "call") + " " + (.hash // "")' "$DEMO_RUN"

echo "[demo-local] explorer URLs: TBD (local chain)"
