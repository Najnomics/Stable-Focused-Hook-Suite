// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

import {StableSuiteBase} from "./utils/StableSuiteBase.sol";
import {StableSuiteHook} from "../src/core/StableSuiteHook.sol";
import {StableTypes} from "../src/libraries/StableTypes.sol";
import {PegGuardrailsModule} from "../src/modules/PegGuardrailsModule.sol";

contract StableSuiteHookTest is StableSuiteBase {
    function setUp() public {
        setUpSuite();
    }

    function testPermissionBitMismatchExpectations() public {
        vm.expectRevert();
        new StableSuiteHook(poolManager, controller, incentives);
    }

    function testRegimeAtBand1BoundaryIsNormal() public {
        StableTypes.PolicyInput memory policyInput = defaultPolicyInput();
        policyInput.pegTick = -int24(uint24(policyInput.band1Ticks));
        policyInput.minTimeInRegime = 0;

        controller.configurePoolPolicy(poolKey, policyInput);
        _swapExactIn(1e18, true);

        assertEq(uint8(_currentRegime()), uint8(StableTypes.Regime.NORMAL));
    }

    function testRegimeAtBand2BoundaryIsSoft() public {
        StableTypes.PolicyInput memory policyInput = defaultPolicyInput();
        policyInput.pegTick = -int24(uint24(policyInput.band2Ticks));
        policyInput.minTimeInRegime = 0;

        controller.configurePoolPolicy(poolKey, policyInput);
        _swapExactIn(1e18, true);

        assertEq(uint8(_currentRegime()), uint8(StableTypes.Regime.SOFT_DEPEG));
    }

    function testRegimeOutsideBand2IsHard() public {
        StableTypes.PolicyInput memory policyInput = defaultPolicyInput();
        policyInput.pegTick = -int24(uint24(policyInput.band2Ticks + 1));
        policyInput.minTimeInRegime = 0;

        controller.configurePoolPolicy(poolKey, policyInput);
        _swapExactIn(1e18, true);

        assertEq(uint8(_currentRegime()), uint8(StableTypes.Regime.HARD_DEPEG));
    }

    function testMaxSwapBoundary() public {
        StableTypes.Policy memory policy = controller.getPolicy(poolId);

        _swapExactIn(policy.normal.maxSwapAmount, true);

        vm.expectRevert();
        _swapExactIn(uint256(policy.normal.maxSwapAmount) + 1, true);
    }

    function testHardCooldownBoundary() public {
        StableTypes.PolicyInput memory policyInput = defaultPolicyInput();
        policyInput.pegTick = -500;
        policyInput.band1Ticks = 10;
        policyInput.band2Ticks = 20;
        policyInput.hysteresisTicks = 1;
        policyInput.minTimeInRegime = 0;
        policyInput.hard.cooldownSeconds = 100;
        controller.configurePoolPolicy(poolKey, policyInput);

        _swapExactIn(1e18, true);

        vm.expectRevert();
        _swapExactIn(1e18, true);

        vm.warp(block.timestamp + 101);
        _swapExactIn(1e18, true);
    }

    function testOnlyPoolManagerCanCallHookEntrypoints() public {
        SwapParams memory params =
            SwapParams({zeroForOne: true, amountSpecified: -1e18, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1});

        vm.expectRevert();
        hook.beforeSwap(address(this), poolKey, params, bytes(""));
    }

    function _currentRegime() internal view returns (StableTypes.Regime regime) {
        (, regime,,,,,,,) = hook.runtime(poolId);
    }
}
