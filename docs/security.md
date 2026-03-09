# Security

## Trust Model

- Uniswap v4 `PoolManager` correctness is assumed.
- Policy owner is trusted but constrained by on-chain validation and optional timelock.

## Key Controls

- Hook callbacks gated by `onlyPoolManager`
- Policy bounds checks on bands, thresholds, fees, cooldowns
- Rewards vault disbursement restricted to incentives contract
- Reentrancy guards on reward transfer paths

## Main Attack Surfaces

- Regime toggling grief via tiny swaps
- Admin misconfiguration DoS (overly strict guardrails)
- Incentive farming via rapid add/remove
- Arithmetic edge cases in reward accumulator

## Mitigations

- Hysteresis + minimum regime time
- Bounded config ranges
- Warm-up + cooldown penalties
- Funded-budget accounting cap
