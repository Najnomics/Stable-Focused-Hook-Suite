# Architecture

## System View

```mermaid
flowchart LR
  UI[Frontend Console] --> Controller[StablePolicyController]
  UI --> Incentives[StickyLiquidityIncentives]
  UI --> Hook[StableSuiteHook]
  Hook --> PM[Uniswap v4 PoolManager]
  Hook --> Dynamic[DynamicFeeModule]
  Hook --> Guards[PegGuardrailsModule]
  Hook --> Incentives
  Incentives --> Vault[RewardsVault]
```

## Design Rules

- Only `PoolManager` can call hook entrypoints
- Policy config is owner/timelock guarded
- Incentive accounting is O(1) per user action/claim
- Reward distribution cannot exceed funded amount
