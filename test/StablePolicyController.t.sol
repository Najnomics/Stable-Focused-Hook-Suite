// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";

import {StablePolicyController} from "../src/core/StablePolicyController.sol";
import {StableTypes} from "../src/libraries/StableTypes.sol";

contract StablePolicyControllerTest is Test {
    using PoolIdLibrary for PoolKey;

    StablePolicyController internal controller;
    PoolKey internal poolKey;

    function setUp() public {
        controller = new StablePolicyController(address(this), 0);

        address token0 = address(0x1000);
        address token1 = address(0x2000);
        poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 0x800000,
            tickSpacing: 60,
            hooks: IHooks(address(0x4444))
        });
    }

    function testConfigurePolicyStoresNonceAndConfig() public {
        StableTypes.PolicyInput memory policyInput = _defaultPolicyInput();

        controller.configurePoolPolicy(poolKey, policyInput);
        PoolId poolId = poolKey.toId();

        StableTypes.Policy memory policy = controller.getPolicy(poolId);
        assertTrue(policy.exists);
        assertEq(policy.policyNonce, 1);
        assertEq(policy.band1Ticks, policyInput.band1Ticks);
        assertEq(policy.band2Ticks, policyInput.band2Ticks);
        assertEq(policy.normal.feePips, policyInput.normal.feePips);
        assertEq(policy.hard.maxSwapAmount, policyInput.hard.maxSwapAmount);
    }

    function testInvalidBandOrderingReverts() public {
        StableTypes.PolicyInput memory policyInput = _defaultPolicyInput();
        policyInput.band2Ticks = policyInput.band1Ticks;

        vm.expectRevert(StablePolicyController.InvalidBandOrdering.selector);
        controller.configurePoolPolicy(poolKey, policyInput);
    }

    function testUnauthorizedUpdateReverts() public {
        StableTypes.PolicyInput memory policyInput = _defaultPolicyInput();

        vm.prank(address(0xBEEF));
        vm.expectRevert();
        controller.configurePoolPolicy(poolKey, policyInput);
    }

    function testQueueAndExecutePolicyWithTimelock() public {
        controller.setPolicyTimelock(60);

        StableTypes.PolicyInput memory policyInput = _defaultPolicyInput();
        policyInput.hard.cooldownSeconds = 180;

        controller.queuePolicyUpdate(poolKey, policyInput);

        vm.expectRevert(StablePolicyController.TimelockNotElapsed.selector);
        controller.executePolicyUpdate(poolKey, policyInput);

        vm.warp(block.timestamp + 61);
        controller.executePolicyUpdate(poolKey, policyInput);

        StableTypes.Policy memory policy = controller.getPolicy(poolKey.toId());
        assertEq(policy.hard.cooldownSeconds, 180);
        assertEq(policy.policyNonce, 1);
    }

    function testExecuteRevertsOnHashMismatch() public {
        controller.setPolicyTimelock(10);

        StableTypes.PolicyInput memory queuedInput = _defaultPolicyInput();
        StableTypes.PolicyInput memory executeInput = _defaultPolicyInput();
        executeInput.soft.feePips = queuedInput.soft.feePips + 1;

        controller.queuePolicyUpdate(poolKey, queuedInput);
        vm.warp(block.timestamp + 11);

        vm.expectRevert(StablePolicyController.PolicyHashMismatch.selector);
        controller.executePolicyUpdate(poolKey, executeInput);
    }

    function _defaultPolicyInput() internal pure returns (StableTypes.PolicyInput memory policy) {
        policy.dynamicFeeEnabled = true;
        policy.pegTick = 0;
        policy.band1Ticks = 80;
        policy.band2Ticks = 220;
        policy.hysteresisTicks = 20;
        policy.minTimeInRegime = 300;
        policy.volatilityWindow = 30;
        policy.softVolatilityThreshold = 120;
        policy.hardVolatilityThreshold = 220;
        policy.softFlowSkewThreshold = 50_000;
        policy.hardFlowSkewThreshold = 100_000;

        policy.normal =
            StableTypes.RegimeConfig({feePips: 500, maxSwapAmount: 100e18, maxImpactTicks: 400, cooldownSeconds: 0});
        policy.soft =
            StableTypes.RegimeConfig({feePips: 3_000, maxSwapAmount: 40e18, maxImpactTicks: 250, cooldownSeconds: 0});
        policy.hard =
            StableTypes.RegimeConfig({feePips: 10_000, maxSwapAmount: 5e18, maxImpactTicks: 120, cooldownSeconds: 120});

        policy.incentives = StableTypes.IncentiveConfig({
            warmupSeconds: 60, cooldownSeconds: 120, cooldownPenaltyBps: 1500, emissionRate: 1e18
        });
    }
}
