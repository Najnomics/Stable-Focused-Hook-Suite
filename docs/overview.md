# Stable-Focused Hook Suite Overview

![Uniswap v4](../assets/uniswap-v4-mark.svg)
![Stable Suite](../assets/stable-suite-mark.svg)
![Incentives](../assets/incentives-mark.svg)

Stable-Focused Hook Suite is a Uniswap v4 hook system for stablecoin pools that combines:

- Deterministic regime-based policy (normal, soft depeg, hard depeg)
- Deterministic fee/guard behavior with no offchain keepers
- Sticky-liquidity incentives with warm-up and cooldown penalties

The suite is designed for reproducible deployments and deterministic behavior under stress.

## Core Components

- `StableSuiteHook`: executes swap and liquidity callbacks
- `StablePolicyController`: governance-safe per-pool policy registry
- `DynamicFeeModule`: deterministic regime + fee selection
- `PegGuardrailsModule`: max swap, impact bounds, cooldown
- `StickyLiquidityIncentives`: O(1) accumulator rewards
- `RewardsVault`: reward custody and disbursement

## Determinism Constraints

- Regimes use only on-chain signals: tick distance, rolling volatility proxy, flow skew proxy
- No external oracle dependency for correctness
- No keeper-triggered state progression required
