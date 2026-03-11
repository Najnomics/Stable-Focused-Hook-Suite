// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";

import {StablePolicyController} from "../src/core/StablePolicyController.sol";
import {StableTypes} from "../src/libraries/StableTypes.sol";

contract StablePolicyControllerCoverageTest is Test {
    using PoolIdLibrary for PoolKey;

    StablePolicyController internal controller;
    PoolKey internal poolKey;

    function setUp() public {
        controller = new StablePolicyController(address(this), 0);

        address token0 = address(0x1001);
        address token1 = address(0x2002);
        poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 0x800000,
            tickSpacing: 60,
            hooks: IHooks(address(0x4444))
        });
    }

    function testConstructorRejectsLargeInitialTimelock() public {
        vm.expectRevert(StablePolicyController.InvalidRegimeConfig.selector);
        new StablePolicyController(address(this), uint32(31 days));
    }

    function testViewGettersForNonceAndQueuedPolicy() public {
        PoolId poolId = poolKey.toId();
        assertEq(controller.getPolicyNonce(poolId), 0);

        controller.setPolicyTimelock(30);
        StableTypes.PolicyInput memory policyInput = _validPolicy();
        controller.queuePolicyUpdate(poolKey, policyInput);

        StablePolicyController.QueuedPolicy memory queued = controller.getQueuedPolicy(poolId);
        assertEq(queued.policyHash, keccak256(abi.encode(policyInput)));
        assertGt(queued.executeAfter, block.timestamp);

        vm.warp(block.timestamp + 31);
        controller.executePolicyUpdate(poolKey, policyInput);
        assertEq(controller.getPolicyNonce(poolId), 1);
    }

    function testConfigureRevertsWhenTimelockEnabled() public {
        controller.setPolicyTimelock(1);
        vm.expectRevert(StablePolicyController.TimelockEnabled.selector);
        controller.configurePoolPolicy(poolKey, _validPolicy());
    }

    function testQueueRevertsWhenTimelockDisabled() public {
        vm.expectRevert(StablePolicyController.TimelockDisabled.selector);
        controller.queuePolicyUpdate(poolKey, _validPolicy());
    }

    function testExecuteRevertsWhenTimelockDisabledOrNotQueued() public {
        vm.expectRevert(StablePolicyController.TimelockDisabled.selector);
        controller.executePolicyUpdate(poolKey, _validPolicy());

        controller.setPolicyTimelock(1);
        vm.expectRevert(StablePolicyController.PolicyNotQueued.selector);
        controller.executePolicyUpdate(poolKey, _validPolicy());
    }

    function testSetPolicyTimelockUpperBoundReverts() public {
        vm.expectRevert(StablePolicyController.InvalidRegimeConfig.selector);
        controller.setPolicyTimelock(uint32(31 days));
    }

    function testInvalidHysteresisReverts() public {
        StableTypes.PolicyInput memory policyInput = _validPolicy();
        policyInput.hysteresisTicks = policyInput.band1Ticks;

        vm.expectRevert(StablePolicyController.InvalidHysteresis.selector);
        controller.configurePoolPolicy(poolKey, policyInput);
    }

    function testInvalidRegimeTimeReverts() public {
        StableTypes.PolicyInput memory policyInput = _validPolicy();
        policyInput.minTimeInRegime = 8 days;

        vm.expectRevert(StablePolicyController.InvalidRegimeConfig.selector);
        controller.configurePoolPolicy(poolKey, policyInput);
    }

    function testInvalidVolatilityWindowReverts() public {
        StableTypes.PolicyInput memory policyInput = _validPolicy();
        policyInput.volatilityWindow = 0;

        vm.expectRevert(StablePolicyController.InvalidVolatilityConfig.selector);
        controller.configurePoolPolicy(poolKey, policyInput);

        policyInput = _validPolicy();
        policyInput.volatilityWindow = uint32(3 hours + 1);

        vm.expectRevert(StablePolicyController.InvalidVolatilityConfig.selector);
        controller.configurePoolPolicy(poolKey, policyInput);
    }

    function testInvalidVolatilityThresholdsRevert() public {
        StableTypes.PolicyInput memory policyInput = _validPolicy();
        policyInput.softVolatilityThreshold = 0;

        vm.expectRevert(StablePolicyController.InvalidVolatilityConfig.selector);
        controller.configurePoolPolicy(poolKey, policyInput);

        policyInput = _validPolicy();
        policyInput.hardVolatilityThreshold = policyInput.softVolatilityThreshold - 1;

        vm.expectRevert(StablePolicyController.InvalidVolatilityConfig.selector);
        controller.configurePoolPolicy(poolKey, policyInput);
    }

    function testInvalidSkewThresholdsRevert() public {
        StableTypes.PolicyInput memory policyInput = _validPolicy();
        policyInput.softFlowSkewThreshold = 0;

        vm.expectRevert(StablePolicyController.InvalidSkewConfig.selector);
        controller.configurePoolPolicy(poolKey, policyInput);

        policyInput = _validPolicy();
        policyInput.hardFlowSkewThreshold = policyInput.softFlowSkewThreshold - 1;

        vm.expectRevert(StablePolicyController.InvalidSkewConfig.selector);
        controller.configurePoolPolicy(poolKey, policyInput);
    }

    function testInvalidRegimeConfigsRevert() public {
        StableTypes.PolicyInput memory policyInput = _validPolicy();
        policyInput.normal.feePips = 1_000_001;

        vm.expectRevert(StablePolicyController.InvalidRegimeConfig.selector);
        controller.configurePoolPolicy(poolKey, policyInput);

        policyInput = _validPolicy();
        policyInput.normal.maxSwapAmount = 0;
        vm.expectRevert(StablePolicyController.InvalidRegimeConfig.selector);
        controller.configurePoolPolicy(poolKey, policyInput);

        policyInput = _validPolicy();
        policyInput.normal.maxImpactTicks = 0;
        vm.expectRevert(StablePolicyController.InvalidRegimeConfig.selector);
        controller.configurePoolPolicy(poolKey, policyInput);

        policyInput = _validPolicy();
        policyInput.normal.cooldownSeconds = 1;
        vm.expectRevert(StablePolicyController.InvalidRegimeConfig.selector);
        controller.configurePoolPolicy(poolKey, policyInput);

        policyInput = _validPolicy();
        policyInput.hard.cooldownSeconds = uint32(3 days + 1);
        vm.expectRevert(StablePolicyController.InvalidRegimeConfig.selector);
        controller.configurePoolPolicy(poolKey, policyInput);
    }

    function testInvalidIncentiveConfigsRevert() public {
        StableTypes.PolicyInput memory policyInput = _validPolicy();
        policyInput.incentives.cooldownPenaltyBps = 10_001;

        vm.expectRevert(StablePolicyController.InvalidIncentiveConfig.selector);
        controller.configurePoolPolicy(poolKey, policyInput);

        policyInput = _validPolicy();
        policyInput.incentives.cooldownSeconds = uint32(3 days + 1);

        vm.expectRevert(StablePolicyController.InvalidIncentiveConfig.selector);
        controller.configurePoolPolicy(poolKey, policyInput);
    }

    function _validPolicy() internal pure returns (StableTypes.PolicyInput memory policy) {
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
            warmupSeconds: 60,
            cooldownSeconds: 120,
            cooldownPenaltyBps: 1500,
            emissionRate: 1e18
        });
    }
}
