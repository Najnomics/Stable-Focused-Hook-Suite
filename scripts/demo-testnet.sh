#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/demo-common.sh
source "$ROOT_DIR/scripts/demo-common.sh"

cd "$ROOT_DIR"
load_dotenv "$ROOT_DIR/.env"

RPC_URL="${RPC_URL:-${UNICHAIN_SEPOLIA_RPC_URL:-${unichain_SEPOLIA_RPC_URL:-${SEPOLIA_RPC_URL:-}}}}"
PRIVATE_KEY="${PRIVATE_KEY:-${SEPOLIA_PRIVATE_KEY:-}}"
FORCE_DEPLOY="${FORCE_DEPLOY:-0}"
DEPLOY_MOCKS="${DEPLOY_MOCKS:-true}"
DEPLOY_MOCKS_LC="$(printf '%s' "$DEPLOY_MOCKS" | tr '[:upper:]' '[:lower:]')"
WARMUP_WAIT_SECONDS="${WARMUP_WAIT_SECONDS:-20}"
NORMAL_SWAP_AMOUNT="${DEMO_NORMAL_SWAP_AMOUNT:-1000000}"
DEPEG_SWAP_AMOUNT="${DEMO_DEPEG_SWAP_AMOUNT:-2000000}"
DEPEG_COOLDOWN_SECONDS="120"
MAX_UINT="115792089237316195423570985008687907853269984665640564039457584007913129639935"
DEMO_ONLY_PHASE="${DEMO_ONLY_PHASE:-all}"

require_var RPC_URL
require_var PRIVATE_KEY
require_var OWNER_ADDRESS

CHAIN_ID="$(cast chain-id --rpc-url "$RPC_URL")"
EXPECTED_CHAIN_ID="${SEPOLIA_CHAIN_ID:-1301}"
EXPLORER_TX_PREFIX="${EXPLORER_TX_PREFIX:-$(explorer_tx_prefix_for_chain "$CHAIN_ID")}" 
SWAP_ROUTER_ADDRESS="${SWAP_ROUTER_ADDRESS:-0x9cD2b0a732dd5e023a5539921e0FD1c30E198Dba}"

if [[ "$CHAIN_ID" != "$EXPECTED_CHAIN_ID" ]]; then
  echo "[demo-testnet] warning: expected chain $EXPECTED_CHAIN_ID, got $CHAIN_ID"
fi

ENV_FILE="$ROOT_DIR/.env"
DEMO_ENV_FILE="$ROOT_DIR/.demo.${CHAIN_ID}.env"

run_deploy=1
if [[ "$FORCE_DEPLOY" != "1" \
  && -n "${HOOK:-}" \
  && -n "${CONTROLLER:-}" \
  && -n "${INCENTIVES:-}" \
  && -n "${VAULT:-}" \
  && -n "${TOKEN0:-}" \
  && -n "${TOKEN1:-}" \
  && -n "${REWARD_TOKEN:-}" ]]; then
  if require_contract_deployed "$RPC_URL" "$HOOK" "StableSuiteHook" \
    && require_contract_deployed "$RPC_URL" "$CONTROLLER" "StablePolicyController" \
    && require_contract_deployed "$RPC_URL" "$INCENTIVES" "StickyLiquidityIncentives" \
    && require_contract_deployed "$RPC_URL" "$VAULT" "RewardsVault"; then
    run_deploy=0
  fi
fi

if [[ "$run_deploy" == "1" ]]; then
  print_demo_phase "PHASE 1/5: Deploy + Bootstrap" "Protocol owner deploys Stable Suite modules, hook, and stable pool on Unichain Sepolia."

  if [[ "$DEPLOY_MOCKS_LC" != "true" ]]; then
    require_var TOKEN0
    require_var TOKEN1
    require_var REWARD_TOKEN
  fi

  DEPLOY_MOCKS="$DEPLOY_MOCKS" \
  TOKEN0="${TOKEN0:-}" \
  TOKEN1="${TOKEN1:-}" \
  REWARD_TOKEN="${REWARD_TOKEN:-}" \
  forge script script/DeployStableSuite.s.sol \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --broadcast \
    --slow

  DEPLOY_RUN="broadcast/DeployStableSuite.s.sol/${CHAIN_ID}/run-latest.json"

  HOOK="$(extract_deploy_value "$DEPLOY_RUN" "StableSuiteHook")"
  CONTROLLER="$(extract_deploy_value "$DEPLOY_RUN" "StablePolicyController")"
  INCENTIVES="$(extract_deploy_value "$DEPLOY_RUN" "StickyLiquidityIncentives")"
  VAULT="$(extract_deploy_value "$DEPLOY_RUN" "RewardsVault")"

  if [[ "$DEPLOY_MOCKS_LC" == "true" ]]; then
    TOKEN_LINES="$(jq -r '.transactions[] | select(.contractName == "MockStablecoin") | .contractAddress // empty' "$DEPLOY_RUN")"
    TOKEN0="$(echo "$TOKEN_LINES" | sed -n '1p')"
    TOKEN1="$(echo "$TOKEN_LINES" | sed -n '2p')"
    REWARD_TOKEN="$(extract_deploy_value "$DEPLOY_RUN" "MockRewardToken")"
  fi

  if [[ -z "$HOOK" || -z "$CONTROLLER" || -z "$INCENTIVES" || -z "$VAULT" || -z "${TOKEN0:-}" || -z "${TOKEN1:-}" || -z "${REWARD_TOKEN:-}" ]]; then
    echo "[demo-testnet] failed to resolve deployed addresses from $DEPLOY_RUN" >&2
    exit 1
  fi

  print_tx_urls_from_run_file "deploy" "$DEPLOY_RUN" "$EXPLORER_TX_PREFIX"

  upsert_env_var "$ENV_FILE" "RPC_URL" "$RPC_URL"
  upsert_env_var "$ENV_FILE" "PRIVATE_KEY" "$PRIVATE_KEY"
  upsert_env_var "$ENV_FILE" "HOOK" "$HOOK"
  upsert_env_var "$ENV_FILE" "CONTROLLER" "$CONTROLLER"
  upsert_env_var "$ENV_FILE" "INCENTIVES" "$INCENTIVES"
  upsert_env_var "$ENV_FILE" "VAULT" "$VAULT"
  upsert_env_var "$ENV_FILE" "TOKEN0" "$TOKEN0"
  upsert_env_var "$ENV_FILE" "TOKEN1" "$TOKEN1"
  upsert_env_var "$ENV_FILE" "REWARD_TOKEN" "$REWARD_TOKEN"
else
  print_demo_phase "PHASE 1/5: Reuse Existing Deployment" "Using previously deployed contracts found in .env."
fi

TOKEN0_LC="$(printf '%s' "$TOKEN0" | tr '[:upper:]' '[:lower:]')"
TOKEN1_LC="$(printf '%s' "$TOKEN1" | tr '[:upper:]' '[:lower:]')"
if [[ "$TOKEN0_LC" < "$TOKEN1_LC" ]]; then
  C0="$TOKEN0"
  C1="$TOKEN1"
else
  C0="$TOKEN1"
  C1="$TOKEN0"
fi

POOL_KEY_TUPLE="($C0,$C1,8388608,60,$HOOK)"
POOL_KEY_ENCODED="$(cast abi-encode "f((address,address,uint24,int24,address))" "$POOL_KEY_TUPLE")"
POOL_ID="$(cast keccak "$POOL_KEY_ENCODED")"

upsert_env_var "$ENV_FILE" "POOL_ID" "$POOL_ID"
upsert_env_var "$ENV_FILE" "SWAP_ROUTER_ADDRESS" "$SWAP_ROUTER_ADDRESS"

cat > "$DEMO_ENV_FILE" <<ENV
CHAIN_ID=$CHAIN_ID
RPC_URL=$RPC_URL
HOOK=$HOOK
CONTROLLER=$CONTROLLER
INCENTIVES=$INCENTIVES
VAULT=$VAULT
TOKEN0=$TOKEN0
TOKEN1=$TOKEN1
REWARD_TOKEN=$REWARD_TOKEN
POOL_ID=$POOL_ID
SWAP_ROUTER_ADDRESS=$SWAP_ROUTER_ADDRESS
EXPLORER_TX_PREFIX=$EXPLORER_TX_PREFIX
ENV

RUN_NORMAL=true
RUN_DEPEG=true
RUN_INCENTIVES=true
case "$DEMO_ONLY_PHASE" in
  all) ;;
  normal)
    RUN_DEPEG=false
    RUN_INCENTIVES=false
    ;;
  depeg)
    RUN_NORMAL=false
    RUN_INCENTIVES=false
    ;;
  incentives)
    RUN_NORMAL=false
    RUN_DEPEG=false
    ;;
  *)
    echo "[demo-testnet] invalid DEMO_ONLY_PHASE: $DEMO_ONLY_PHASE (expected: all|normal|depeg|incentives)" >&2
    exit 1
    ;;
esac

LAST_TX_HASH=""
send_with_retry() {
  local label="$1"
  local to="$2"
  local signature="$3"
  shift 3
  local args=("$@")
  local nonce out hash

  for attempt in 1 2 3; do
    nonce="$(cast nonce "$OWNER_ADDRESS" --rpc-url "$RPC_URL")"
    if out=$(cast send "$to" "$signature" "${args[@]}" --nonce "$nonce" --private-key "$PRIVATE_KEY" --rpc-url "$RPC_URL" 2>&1); then
      echo "$out"
      hash="$(printf '%s\n' "$out" | awk '/transactionHash/{print $2}' | tail -n 1)"
      if [[ -z "$hash" ]]; then
        echo "[$label] transaction hash not found in output" >&2
        exit 1
      fi
      LAST_TX_HASH="$hash"
      return 0
    fi

    if [[ "$out" != *"nonce too low"* && "$out" != *"EOA nonce changed unexpectedly"* ]]; then
      echo "$out" >&2
      return 1
    fi

    echo "[$label] nonce drift detected, retrying..."
    sleep 1
  done

  echo "$out" >&2
  return 1
}

print_tx_line() {
  local label="$1"
  local hash="$2"
  if [[ "$EXPLORER_TX_PREFIX" == "TBD" ]]; then
    echo "  - $label: $hash | explorer: TBD"
  else
    echo "  - $label: $hash | explorer: ${EXPLORER_TX_PREFIX}${hash}"
  fi
}

APPROVE0_HASH=""
APPROVE1_HASH=""
if [[ "$RUN_NORMAL" == true || "$RUN_DEPEG" == true ]]; then
  send_with_retry "approve-token0" "$C0" "approve(address,uint256)" "$SWAP_ROUTER_ADDRESS" "$MAX_UINT"
  APPROVE0_HASH="$LAST_TX_HASH"
  send_with_retry "approve-token1" "$C1" "approve(address,uint256)" "$SWAP_ROUTER_ADDRESS" "$MAX_UINT"
  APPROVE1_HASH="$LAST_TX_HASH"
fi

if [[ "$RUN_NORMAL" == true ]]; then
  print_demo_phase "PHASE 2/5: User Normal-Peg Flow" "User executes a normal swap under deterministic NORMAL regime policy."
  NORMAL_DEADLINE=$(( $(date +%s) + 600 ))
  send_with_retry "normal-swap" "$SWAP_ROUTER_ADDRESS" \
    "swapExactTokensForTokens(uint256,uint256,bool,(address,address,uint24,int24,address),bytes,address,uint256)" \
    "$NORMAL_SWAP_AMOUNT" "0" "true" "$POOL_KEY_TUPLE" "0x" "$OWNER_ADDRESS" "$NORMAL_DEADLINE"
  NORMAL_SWAP_HASH="$LAST_TX_HASH"

  echo "[normal] tx hashes"
  print_tx_line "approve token0" "$APPROVE0_HASH"
  print_tx_line "approve token1" "$APPROVE1_HASH"
  print_tx_line "swap normal" "$NORMAL_SWAP_HASH"
fi

if [[ "$RUN_DEPEG" == true ]]; then
  print_demo_phase "PHASE 3/5: User Depeg-Stress Flow" "Operator enforces depeg stress policy and user executes/observes hard-regime behavior with cooldown projection."
  STRESS_POLICY="(true,-500,10,20,1,0,30,10,20,10,20,(500,50000000000000000000,400,0),(3000,1000000000000000000,200,0),(10000,2000000,120,120),(15,180,2000,1000000000000000000))"
  send_with_retry "depeg-configure-policy" "$CONTROLLER" \
    "configurePoolPolicy((address,address,uint24,int24,address),(bool,int24,uint24,uint24,uint24,uint32,uint32,uint24,uint24,int64,int64,(uint24,uint128,uint24,uint32),(uint24,uint128,uint24,uint32),(uint24,uint128,uint24,uint32),(uint32,uint32,uint16,uint128)))" \
    "$POOL_KEY_TUPLE" "$STRESS_POLICY"
  DEPEG_POLICY_HASH="$LAST_TX_HASH"

  RUNTIME_BEFORE="$(cast call "$HOOK" "runtime(bytes32)(bool,uint8,int24,uint32,int64,uint40,uint40,uint40,uint64)" "$POOL_ID" --rpc-url "$RPC_URL")"
  LAST_HARD_BEFORE="$(echo "$RUNTIME_BEFORE" | sed -n '8p' | awk '{print $1}')"
  NOW_TS="$(cast block latest --rpc-url "$RPC_URL" | awk '/timestamp/{print $2}')"
  COOLDOWN_END=$((LAST_HARD_BEFORE + DEPEG_COOLDOWN_SECONDS))

  DEPEG_SWAP_HASH=""
  if (( LAST_HARD_BEFORE == 0 || NOW_TS >= COOLDOWN_END )); then
    DEPEG_DEADLINE=$(( $(date +%s) + 600 ))
    send_with_retry "depeg-swap" "$SWAP_ROUTER_ADDRESS" \
      "swapExactTokensForTokens(uint256,uint256,bool,(address,address,uint24,int24,address),bytes,address,uint256)" \
      "$DEPEG_SWAP_AMOUNT" "0" "true" "$POOL_KEY_TUPLE" "0x" "$OWNER_ADDRESS" "$DEPEG_DEADLINE"
    DEPEG_SWAP_HASH="$LAST_TX_HASH"
  else
    echo "[depeg] swap skipped because hard cooldown was already active"
  fi

  RUNTIME_AFTER="$(cast call "$HOOK" "runtime(bytes32)(bool,uint8,int24,uint32,int64,uint40,uint40,uint40,uint64)" "$POOL_ID" --rpc-url "$RPC_URL")"
  LAST_HARD_AFTER="$(echo "$RUNTIME_AFTER" | sed -n '8p' | awk '{print $1}')"
  NOW_AFTER="$(cast block latest --rpc-url "$RPC_URL" | awk '/timestamp/{print $2}')"
  COOLDOWN_END_AFTER=$((LAST_HARD_AFTER + DEPEG_COOLDOWN_SECONDS))
  COOLDOWN_ACTIVE_AFTER=false
  if (( LAST_HARD_AFTER != 0 && NOW_AFTER < COOLDOWN_END_AFTER )); then
    COOLDOWN_ACTIVE_AFTER=true
  fi

  echo "[depeg] tx hashes"
  print_tx_line "configure stress policy" "$DEPEG_POLICY_HASH"
  if [[ -n "$DEPEG_SWAP_HASH" ]]; then
    print_tx_line "swap depeg" "$DEPEG_SWAP_HASH"
  else
    echo "  - swap depeg: skipped (cooldown already active)"
  fi
  echo "[depeg] cooldown projection"
  echo "  - lastHardSwapTimestamp: $LAST_HARD_AFTER"
  echo "  - cooldownEndsAt:        $COOLDOWN_END_AFTER"
  echo "  - currentTimestamp:      $NOW_AFTER"
  echo "  - cooldownActive:        $COOLDOWN_ACTIVE_AFTER"
fi

if [[ "$RUN_INCENTIVES" == true ]]; then
  print_demo_phase "PHASE 4/5: Warmup Window" "Waiting ${WARMUP_WAIT_SECONDS}s so sticky-liquidity accrual advances before claim."
  sleep "$WARMUP_WAIT_SECONDS"

  print_demo_phase "PHASE 5/5: Incentives Fairness Flow" "User checks claimable amount and claims rewards from RewardsVault using O(1) checkpoints."
  CLAIMABLE_RAW="$(cast call "$INCENTIVES" "claimable(bytes32,address)(uint256,uint256)" "$POOL_ID" "$OWNER_ADDRESS" --rpc-url "$RPC_URL")"
  CLAIMABLE_AMOUNT="$(echo "$CLAIMABLE_RAW" | sed -n '1p' | awk '{print $1}')"
  CLAIMABLE_PENALTY="$(echo "$CLAIMABLE_RAW" | sed -n '2p' | awk '{print $1}')"

  send_with_retry "incentives-claim" "$INCENTIVES" "claim(bytes32,address)" "$POOL_ID" "$OWNER_ADDRESS"
  CLAIM_HASH="$LAST_TX_HASH"

  PROGRAM_RAW="$(cast call "$INCENTIVES" "getProgram(bytes32)(bool,uint32,uint32,uint16,uint128,uint128,uint128,uint40,uint256,uint256,uint256,uint256,uint256)" "$POOL_ID" --rpc-url "$RPC_URL")"
  TOTAL_FUNDED="$(echo "$PROGRAM_RAW" | sed -n '11p' | awk '{print $1}')"
  TOTAL_CLAIMED="$(echo "$PROGRAM_RAW" | sed -n '12p' | awk '{print $1}')"

  echo "[incentives] pre-claim"
  echo "  - claimableAmount: $CLAIMABLE_AMOUNT"
  echo "  - penaltyIfClaimed: $CLAIMABLE_PENALTY"
  echo "[incentives] tx hashes"
  print_tx_line "claim rewards" "$CLAIM_HASH"
  echo "[incentives] accounting"
  echo "  - totalFunded: $TOTAL_FUNDED"
  echo "  - totalClaimed: $TOTAL_CLAIMED"
fi

print_demo_phase "DEMO SUMMARY" "End-to-end owner/user flow completed with deterministic policy enforcement and reward accounting." 
echo "chainId:      $CHAIN_ID"
echo "hook:         $HOOK"
echo "controller:   $CONTROLLER"
echo "incentives:   $INCENTIVES"
echo "vault:        $VAULT"
echo "token0:       $C0"
echo "token1:       $C1"
echo "rewardToken:  $REWARD_TOKEN"
echo "poolId:       $POOL_ID"
echo "demo env:     $DEMO_ENV_FILE"
echo "explorer tx:  $EXPLORER_TX_PREFIX<tx_hash>"
