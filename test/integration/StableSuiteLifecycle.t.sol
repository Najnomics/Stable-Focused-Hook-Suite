// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {StableSuiteBase} from "../utils/StableSuiteBase.sol";
import {StableTypes} from "../../src/libraries/StableTypes.sol";

contract StableSuiteLifecycleTest is StableSuiteBase {
    function setUp() public {
        setUpSuite();
        rewardToken.approve(address(vault), type(uint256).max);
        incentives.fundProgram(poolId, 250_000e18);
    }

    function testLifecycleNormalThenDepegStress() public {
        // Normal peg behavior.
        _swapExactIn(1e18, true);
        assertEq(uint8(_regime()), uint8(StableTypes.Regime.NORMAL));

        // Warm-up + accrual.
        vm.warp(block.timestamp + 90);
        incentives.claim(poolId, address(this)); // activates pending weight
        vm.warp(block.timestamp + 30);
        (uint256 normalClaimable,) = incentives.claimable(poolId, address(this));
        assertGt(normalClaimable, 0);

        (uint256 claimedNormal,) = incentives.claim(poolId, address(this));
        assertGt(claimedNormal, 0);

        // Force hard regime by policy (deterministic on-chain, no oracle).
        StableTypes.PolicyInput memory stressPolicy = defaultPolicyInput();
        stressPolicy.minTimeInRegime = 0;
        stressPolicy.band1Ticks = 10;
        stressPolicy.band2Ticks = 20;
        stressPolicy.hysteresisTicks = 1;
        stressPolicy.pegTick = -500;
        stressPolicy.hard.cooldownSeconds = 120;
        controller.configurePoolPolicy(poolKey, stressPolicy);

        _swapExactIn(1e18, true);
        assertEq(uint8(_regime()), uint8(StableTypes.Regime.HARD_DEPEG));

        // Cooldown enforced.
        vm.expectRevert();
        _swapExactIn(1e18, true);

        vm.warp(block.timestamp + 121);
        _swapExactIn(1e18, true);

        // Invariants for reward accounting.
        assertLe(vault.totalDisbursed(), vault.totalFunded());
    }

    function _regime() internal view returns (StableTypes.Regime regime) {
        (, regime,,,,,,,) = hook.runtime(poolId);
    }
}
