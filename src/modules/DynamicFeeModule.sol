// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {StableTypes} from "../libraries/StableTypes.sol";

library DynamicFeeModule {
    function selectRawRegime(
        uint24 absTickDistance,
        uint32 volatility,
        uint64 absFlowSkew,
        StableTypes.Policy memory policy
    ) internal pure returns (StableTypes.Regime) {
        if (
            absTickDistance > policy.band2Ticks || volatility >= policy.hardVolatilityThreshold
                || absFlowSkew >= uint64(uint256(int256(policy.hardFlowSkewThreshold)))
        ) {
            return StableTypes.Regime.HARD_DEPEG;
        }

        if (
            absTickDistance > policy.band1Ticks || volatility >= policy.softVolatilityThreshold
                || absFlowSkew >= uint64(uint256(int256(policy.softFlowSkewThreshold)))
        ) {
            return StableTypes.Regime.SOFT_DEPEG;
        }

        return StableTypes.Regime.NORMAL;
    }

    function applyHysteresis(
        StableTypes.Regime candidate,
        StableTypes.Regime current,
        uint24 absTickDistance,
        StableTypes.Policy memory policy,
        uint40 regimeSince,
        uint40 timestamp
    ) internal pure returns (StableTypes.Regime) {
        if (candidate == current) {
            return current;
        }

        if (timestamp < regimeSince + policy.minTimeInRegime) {
            return current;
        }

        uint24 hysteresis = policy.hysteresisTicks;

        if (current == StableTypes.Regime.HARD_DEPEG && candidate != StableTypes.Regime.HARD_DEPEG) {
            uint24 hardExitBand = policy.band2Ticks > hysteresis ? policy.band2Ticks - hysteresis : 0;
            if (absTickDistance > hardExitBand) {
                return StableTypes.Regime.HARD_DEPEG;
            }
        }

        if (current == StableTypes.Regime.SOFT_DEPEG && candidate == StableTypes.Regime.NORMAL) {
            uint24 softExitBand = policy.band1Ticks > hysteresis ? policy.band1Ticks - hysteresis : 0;
            if (absTickDistance > softExitBand) {
                return StableTypes.Regime.SOFT_DEPEG;
            }
        }

        return candidate;
    }

    function configForRegime(StableTypes.Policy memory policy, StableTypes.Regime regime)
        internal
        pure
        returns (StableTypes.RegimeConfig memory)
    {
        if (regime == StableTypes.Regime.NORMAL) {
            return policy.normal;
        }

        if (regime == StableTypes.Regime.SOFT_DEPEG) {
            return policy.soft;
        }

        return policy.hard;
    }
}
