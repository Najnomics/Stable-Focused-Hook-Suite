// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library StableTypes {
    enum Regime {
        NORMAL,
        SOFT_DEPEG,
        HARD_DEPEG
    }

    struct RegimeConfig {
        uint24 feePips;
        uint128 maxSwapAmount;
        uint24 maxImpactTicks;
        uint32 cooldownSeconds;
    }

    struct IncentiveConfig {
        uint32 warmupSeconds;
        uint32 cooldownSeconds;
        uint16 cooldownPenaltyBps;
        uint128 emissionRate;
    }

    struct Policy {
        bool exists;
        bool dynamicFeeEnabled;
        int24 pegTick;
        uint24 band1Ticks;
        uint24 band2Ticks;
        uint24 hysteresisTicks;
        uint32 minTimeInRegime;
        uint32 volatilityWindow;
        uint24 softVolatilityThreshold;
        uint24 hardVolatilityThreshold;
        int64 softFlowSkewThreshold;
        int64 hardFlowSkewThreshold;
        uint64 policyNonce;
        RegimeConfig normal;
        RegimeConfig soft;
        RegimeConfig hard;
        IncentiveConfig incentives;
    }

    struct PolicyInput {
        bool dynamicFeeEnabled;
        int24 pegTick;
        uint24 band1Ticks;
        uint24 band2Ticks;
        uint24 hysteresisTicks;
        uint32 minTimeInRegime;
        uint32 volatilityWindow;
        uint24 softVolatilityThreshold;
        uint24 hardVolatilityThreshold;
        int64 softFlowSkewThreshold;
        int64 hardFlowSkewThreshold;
        RegimeConfig normal;
        RegimeConfig soft;
        RegimeConfig hard;
        IncentiveConfig incentives;
    }
}
