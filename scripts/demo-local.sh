#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/demo-common.sh
source "$ROOT_DIR/scripts/demo-common.sh"

cd "$ROOT_DIR"
load_dotenv "$ROOT_DIR/.env"

RPC_URL="${LOCAL_RPC_URL:-http://127.0.0.1:8545}"
PRIVATE_KEY="${LOCAL_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
WARMUP_WAIT_SECONDS="${WARMUP_WAIT_SECONDS:-20}"

if ! curl -s "$RPC_URL" >/dev/null 2>&1; then
  echo "[demo-local] anvil not detected at $RPC_URL, starting background anvil"
  anvil --host 127.0.0.1 --port 8545 >/tmp/stable-suite-anvil.log 2>&1 &
  ANVIL_PID=$!
  trap 'kill ${ANVIL_PID:-0} >/dev/null 2>&1 || true' EXIT
  sleep 2
fi

CHAIN_ID="$(cast chain-id --rpc-url "$RPC_URL")"
EXPLORER_TX_PREFIX="TBD"
ENV_FILE="$ROOT_DIR/.demo.${CHAIN_ID}.env"

print_demo_phase "PHASE 1/5: Deploy + Bootstrap" "Local protocol owner deploys mocks + suite + seeded liquidity."
DEPLOY_MOCKS=true forge script script/DeployStableSuite.s.sol \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  --slow

DEPLOY_RUN="broadcast/DeployStableSuite.s.sol/${CHAIN_ID}/run-latest.json"
HOOK="$(extract_deploy_value "$DEPLOY_RUN" "StableSuiteHook")"
CONTROLLER="$(extract_deploy_value "$DEPLOY_RUN" "StablePolicyController")"
INCENTIVES="$(extract_deploy_value "$DEPLOY_RUN" "StickyLiquidityIncentives")"
VAULT="$(extract_deploy_value "$DEPLOY_RUN" "RewardsVault")"
REWARD_TOKEN="$(extract_deploy_value "$DEPLOY_RUN" "MockRewardToken")"
TOKEN_LINES="$(jq -r '.transactions[] | select(.contractName == "MockStablecoin") | .contractAddress // empty' "$DEPLOY_RUN")"
TOKEN0="$(echo "$TOKEN_LINES" | sed -n '1p')"
TOKEN1="$(echo "$TOKEN_LINES" | sed -n '2p')"

if [[ -z "$HOOK" || -z "$CONTROLLER" || -z "$INCENTIVES" || -z "$VAULT" || -z "$TOKEN0" || -z "$TOKEN1" || -z "$REWARD_TOKEN" ]]; then
  echo "[demo-local] failed to resolve deployment artifacts" >&2
  exit 1
fi

cat > "$ENV_FILE" <<ENV
CHAIN_ID=$CHAIN_ID
RPC_URL=$RPC_URL
HOOK=$HOOK
CONTROLLER=$CONTROLLER
INCENTIVES=$INCENTIVES
VAULT=$VAULT
REWARD_TOKEN=$REWARD_TOKEN
TOKEN0=$TOKEN0
TOKEN1=$TOKEN1
TICK_SPACING=60
EXPLORER_TX_PREFIX=TBD
ENV

print_tx_urls_from_run_file "deploy-local" "$DEPLOY_RUN" "$EXPLORER_TX_PREFIX"

run_mode() {
  local mode="$1"
  local title="$2"
  local detail="$3"

  print_demo_phase "$title" "$detail"

  HOOK="$HOOK" \
  CONTROLLER="$CONTROLLER" \
  INCENTIVES="$INCENTIVES" \
  TOKEN0="$TOKEN0" \
  TOKEN1="$TOKEN1" \
  DEMO_MODE="$mode" \
  forge script script/DemoStableSuite.s.sol \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --broadcast \
    --slow

  local run_file="broadcast/DemoStableSuite.s.sol/${CHAIN_ID}/run-latest.json"
  print_tx_urls_from_run_file "demo-local-${mode}" "$run_file" "$EXPLORER_TX_PREFIX"
}

run_mode "normal" \
  "PHASE 2/5: User Normal-Peg Flow" \
  "User executes a normal swap and observes baseline regime behavior."

run_mode "depeg" \
  "PHASE 3/5: User Depeg-Stress Flow" \
  "Policy stress mode triggers tighter constraints and cooldown behavior."

print_demo_phase "PHASE 4/5: Warmup Window" "Waiting ${WARMUP_WAIT_SECONDS}s before incentives claim path."
sleep "$WARMUP_WAIT_SECONDS"

run_mode "incentives" \
  "PHASE 5/5: Incentives Fairness Flow" \
  "User checks claimable rewards and claims through the rewards vault."

print_demo_phase "DEMO SUMMARY" "Local end-to-end flow completed."
echo "hook:        $HOOK"
echo "controller:  $CONTROLLER"
echo "incentives:  $INCENTIVES"
echo "vault:       $VAULT"
echo "token0:      $TOKEN0"
echo "token1:      $TOKEN1"
echo "rewardToken: $REWARD_TOKEN"
echo "env file:    $ENV_FILE"
