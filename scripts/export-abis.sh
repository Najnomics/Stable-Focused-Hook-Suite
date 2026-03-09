#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p shared/abis shared/types

contracts=(
  StableSuiteHook
  StablePolicyController
  StickyLiquidityIncentives
  RewardsVault
  MockStablecoin
  MockRewardToken
)

for c in "${contracts[@]}"; do
  src="out/${c}.sol/${c}.json"
  dst="shared/abis/${c}.abi.json"
  if [[ ! -f "$src" ]]; then
    echo "missing artifact: $src" >&2
    exit 1
  fi
  jq '.abi' "$src" > "$dst"
  echo "wrote $dst"
done

cat > shared/types/contracts.ts <<'TS'
export type Regime = 0 | 1 | 2;

export interface RuntimeState {
  initialized: boolean;
  regime: Regime;
  lastObservedTick: bigint;
  smoothedVolatility: bigint;
  flowSkew: bigint;
  lastObservationTimestamp: bigint;
  regimeSince: bigint;
  lastHardSwapTimestamp: bigint;
  lastSyncedPolicyNonce: bigint;
}

export interface Claimable {
  amount: bigint;
  penalty: bigint;
}
TS

echo "ABI/type export complete"
