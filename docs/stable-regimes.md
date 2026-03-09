# Stable Regimes

Regime selection inputs:

- `abs(currentTick - pegTick)`
- smoothed rolling tick movement proxy
- bounded rolling flow-skew proxy

Regimes:

1. `NORMAL`: inside band1 and below soft stress thresholds
2. `SOFT_DEPEG`: outside band1 or above soft stress thresholds
3. `HARD_DEPEG`: outside band2 or above hard stress thresholds

Hysteresis is enforced via:

- `hysteresisTicks`
- `minTimeInRegime`

This blocks rapid regime flapping from micro-swaps.
