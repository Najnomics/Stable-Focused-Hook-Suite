# Incentives

`StickyLiquidityIncentives` implements an O(1) reward model:

- Global accumulator: `accRewardPerWeightX18`
- Per-user checkpoint: `rewardDebt`
- No loops over LPs during claims

Anti-gaming controls:

- Warm-up (`pendingWeight` -> `activeWeight`)
- Cooldown penalty on rapid withdrawal
- Bounded emission from funded reward budget

Funding:

- `fundProgram(poolId, amount)` pulls sponsor funds into `RewardsVault`

Safety invariant:

- `totalDisbursed <= totalFunded`
