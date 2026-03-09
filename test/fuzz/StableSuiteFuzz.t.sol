// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {StableSuiteBase} from "../utils/StableSuiteBase.sol";
import {StableTypes} from "../../src/libraries/StableTypes.sol";
import {DynamicFeeModule} from "../../src/modules/DynamicFeeModule.sol";

contract StableSuiteFuzzTest is StableSuiteBase {
    function setUp() public {
        setUpSuite();
        rewardToken.approve(address(vault), type(uint256).max);
        incentives.fundProgram(poolId, 200_000e18);
    }

    function testFuzzBandOrderingInvariant(uint24 band1, uint24 band2) public {
        StableTypes.PolicyInput memory policyInput = defaultPolicyInput();
        policyInput.band1Ticks = band1;
        policyInput.band2Ticks = band2;

        if (band1 == 0 || band2 <= band1) {
            vm.expectRevert();
            controller.configurePoolPolicy(poolKey, policyInput);
        } else {
            // Keep hysteresis valid for accepted configs.
            policyInput.hysteresisTicks = band1 > 1 ? band1 - 1 : 0;
            controller.configurePoolPolicy(poolKey, policyInput);
            StableTypes.Policy memory stored = controller.getPolicy(poolId);
            assertGt(stored.band1Ticks, 0);
            assertGt(stored.band2Ticks, stored.band1Ticks);
        }
    }

    function testFuzzRegimeSelectionDeterministic(uint24 distance, uint24 volatility, uint64 skew) public pure {
        StableTypes.Policy memory policy;
        policy.band1Ticks = 80;
        policy.band2Ticks = 240;
        policy.softVolatilityThreshold = 100;
        policy.hardVolatilityThreshold = 220;
        policy.softFlowSkewThreshold = 50_000;
        policy.hardFlowSkewThreshold = 120_000;

        StableTypes.Regime first = DynamicFeeModule.selectRawRegime(distance, volatility, skew, policy);
        StableTypes.Regime second = DynamicFeeModule.selectRawRegime(distance, volatility, skew, policy);
        assertEq(uint8(first), uint8(second));
    }

    function testFuzzRewardsClaimedLeFunded(uint96 fundAmount, uint40 warpSeconds) public {
        uint256 boundedFund = uint256(bound(fundAmount, 1e18, 10_000e18));
        uint256 boundedWarp = bound(uint256(warpSeconds), 1, 10 days);

        incentives.fundProgram(poolId, boundedFund);

        vm.warp(block.timestamp + boundedWarp);
        incentives.claim(poolId, address(this));

        assertLe(vault.totalDisbursed(), vault.totalFunded());
    }

    function testFuzzNoUnexpectedRevertsOnValidSwap(uint64 amountIn) public {
        StableTypes.Policy memory policy = controller.getPolicy(poolId);
        uint256 boundedAmount = bound(uint256(amountIn), 1, policy.normal.maxSwapAmount);

        _swapExactIn(boundedAmount, true);
    }
}
