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
