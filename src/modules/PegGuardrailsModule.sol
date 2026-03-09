// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

import {StableTypes} from "../libraries/StableTypes.sol";

library PegGuardrailsModule {
    error MaxSwapExceeded(uint256 requestedAmount, uint128 maxSwapAmount);
    error MaxImpactExceeded(uint24 requestedImpact, uint24 maxImpactTicks);
    error HardCooldownActive(uint40 cooldownEndsAt);

    function enforceSwap(
        SwapParams calldata params,
        int24 currentTick,
        StableTypes.RegimeConfig memory config,
        uint40 lastHardSwapTimestamp,
        uint40 timestamp
    ) internal pure {
        uint256 requestedAmount = _absAmountSpecified(params.amountSpecified);
        if (requestedAmount > config.maxSwapAmount) {
            revert MaxSwapExceeded(requestedAmount, config.maxSwapAmount);
        }

        // Many routers default to global min/max limits. Only enforce impact when the caller sets
        // a non-default slippage bound so the cap remains deterministic and composable.
        bool hasCustomPriceLimit = params.zeroForOne
            ? params.sqrtPriceLimitX96 > TickMath.MIN_SQRT_PRICE + 1
            : params.sqrtPriceLimitX96 < TickMath.MAX_SQRT_PRICE - 1;

        if (hasCustomPriceLimit) {
            int24 limitTick = TickMath.getTickAtSqrtPrice(params.sqrtPriceLimitX96);
            uint24 requestedImpact = _absTickDelta(currentTick, limitTick);
            if (requestedImpact > config.maxImpactTicks) {
                revert MaxImpactExceeded(requestedImpact, config.maxImpactTicks);
            }
        }

        if (config.cooldownSeconds != 0 && lastHardSwapTimestamp != 0) {
            uint40 cooldownEndsAt = lastHardSwapTimestamp + config.cooldownSeconds;
            if (timestamp < cooldownEndsAt) {
                revert HardCooldownActive(cooldownEndsAt);
            }
        }
    }

    function _absAmountSpecified(int256 value) private pure returns (uint256) {
        if (value == type(int256).min) {
            return uint256(type(int256).max) + 1;
        }
        return uint256(value < 0 ? -value : value);
    }

    function _absTickDelta(int24 a, int24 b) private pure returns (uint24) {
        int256 delta = int256(a) - int256(b);
        if (delta < 0) {
            delta = -delta;
        }
        return uint24(uint256(delta));
    }
}
