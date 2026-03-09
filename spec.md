# Stable-Focused Hook Suite Specification

## 1. Objective

Build a deterministic stablecoin market primitive on Uniswap v4 with three pillars:

1. Stable-focused liquidity execution policy
2. Regime-based fee behavior
3. Sticky-liquidity incentive accounting

No offchain keeper/oracle dependency is required for correctness.

## 2. Scope and Non-Goals

### In Scope

- Uniswap v4 hook with before/after swap plus liquidity hooks
- Policy controller with bounded governance updates
- Regime/guard modules with deterministic constraints
- O(1) rewards with warm-up and cooldown penalty
- Local + testnet deploy/demo scripts

### Out of Scope

- Offchain rebalancing bots
- Oracle-required regime correctness
- Iterative LP reward distribution loops

## 3. On-Chain Components

- `StableSuiteHook`
- `StablePolicyController`
- `DynamicFeeModule`
- `PegGuardrailsModule`
- `StickyLiquidityIncentives`
- `RewardsVault`
- Optional mocks: `MockStablecoin`, `MockRewardToken`

## 4. Data Model

`StableTypes.Policy` includes:

- Peg model: `pegTick`, `band1Ticks`, `band2Ticks`
- Anti-flap: `hysteresisTicks`, `minTimeInRegime`
- Stress proxies: volatility thresholds, flow-skew thresholds
- Per-regime controls: `feePips`, `maxSwapAmount`, `maxImpactTicks`, `cooldownSeconds`
- Incentives: `warmupSeconds`, `cooldownSeconds`, `cooldownPenaltyBps`, `emissionRate`

Runtime state tracks:

- current regime
- last observed tick
- smoothed volatility proxy
- bounded flow skew proxy
- hard-regime cooldown timestamp

## 5. Regime Engine

Raw regime selection:

- `HARD` when distance > band2 OR hard volatility OR hard skew
- `SOFT` when distance > band1 OR soft volatility OR soft skew
- `NORMAL` otherwise

Hysteresis logic:

- Minimum time in regime gate
- Exit thresholds tightened by `hysteresisTicks`

## 6. Guardrail Engine

Per swap:

- reject when `abs(amountSpecified) > maxSwapAmount`
- enforce `maxImpactTicks` for custom price-limit swaps
- enforce hard-regime cooldown when configured

## 7. Fee Behavior

When pool fee is dynamic (`0x800000`) and policy enables dynamic fee:

- hook returns per-regime fee override with override flag

If pool is static-fee:

- fee override is not applied
- guardrails and regime logic still enforce deterministic protection

## 8. Incentive Engine

Global accumulator model:

- `accRewardPerWeightX18`
- per-user `rewardDebt`
- no loops over users

Anti-gaming:

- liquidity enters as `pendingWeight`
- warm-up required before activation
- quick withdrawal triggers cooldown penalty window

Funding model:

- sponsor funds pulled into `RewardsVault`
- program accrues emissions from bounded reward budget
- invariant: disbursed rewards cannot exceed funded rewards

## 9. Security Model

### Access Control

- Hook entrypoints: `onlyPoolManager`
- Policy updates: owner + optional timelock
- Vault payout/funding operations: incentives contract only

### Main Attack Classes

- micro-swap regime griefing
- guardrail misconfiguration DoS
- liquidity in/out farming
- reward math precision drift
- permission-flag/address mismatch

### Mitigation Highlights

- hysteresis + min-time
- bounded policy validation
- accumulator checkpoints and budget cap
- reentrancy guard on transfer paths
- hook address permission validation in constructor

## 10. Reproducibility and Dependency Pinning

Bootstrap enforces pinned v4 commit state:

- v4-periphery commit: `3779387e5d296f39df543d23524b050f89a62917`
- nested v4-core commit is derived and checked from that periphery commit

Command:

```bash
make bootstrap
```

## 11. Testing Requirements Mapping

Implemented suites:

- Unit tests for controller/hook/incentives
- Edge tests for band boundaries, cooldown, invalid updates, unauthorized access
- Fuzz tests for regime determinism and funding invariants
- Integration lifecycle test for normal and depeg stress paths

## 12. Known Assumptions

- `/context/uniswap_docs` used as primary protocol reference.
- `/context/atrium` content not present in this repo.
- Liquidity-account attribution uses hookData fallback mechanics for generic periphery integration.
