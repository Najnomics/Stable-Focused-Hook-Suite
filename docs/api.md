# API Summary

## StablePolicyController

- `configurePoolPolicy(PoolKey, PolicyInput)`
- `queuePolicyUpdate(PoolKey, PolicyInput)`
- `executePolicyUpdate(PoolKey, PolicyInput)`
- `getPolicy(PoolId)`

## StableSuiteHook

- v4 callbacks: `beforeAddLiquidity`, `beforeRemoveLiquidity`, `beforeSwap`, `afterSwap`
- `runtime(PoolId)` view for regime/runtime state

## StickyLiquidityIncentives

- `syncPolicy(PoolId, IncentiveConfig)`
- `fundProgram(PoolId, amount)`
- `claim(PoolId, to)`
- `claimable(PoolId, account)`

## RewardsVault

- `fundFrom(sponsor, amount)` (incentives-only)
- `disburse(recipient, amount)` (incentives-only)
