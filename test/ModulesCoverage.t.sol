// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

import {StableTypes} from "../src/libraries/StableTypes.sol";
import {DynamicFeeModule} from "../src/modules/DynamicFeeModule.sol";
import {PegGuardrailsModule} from "../src/modules/PegGuardrailsModule.sol";

contract PegGuardrailsHarness {
    function enforce(
        SwapParams calldata params,
        int24 currentTick,
        StableTypes.RegimeConfig memory config,
        uint40 lastHardSwapTimestamp,
        uint40 timestamp
    ) external pure {
        PegGuardrailsModule.enforceSwap(params, currentTick, config, lastHardSwapTimestamp, timestamp);
    }
}

contract ModulesCoverageTest is Test {
    PegGuardrailsHarness internal guardrails;
    StableTypes.Policy internal policy;

    function setUp() public {
        guardrails = new PegGuardrailsHarness();

        policy.band1Ticks = 80;
        policy.band2Ticks = 240;
        policy.hysteresisTicks = 20;
        policy.minTimeInRegime = 60;
        policy.softVolatilityThreshold = 100;
        policy.hardVolatilityThreshold = 220;
        policy.softFlowSkewThreshold = 50_000;
        policy.hardFlowSkewThreshold = 120_000;

        policy.normal =
            StableTypes.RegimeConfig({feePips: 500, maxSwapAmount: 100e18, maxImpactTicks: 300, cooldownSeconds: 0});
        policy.soft =
            StableTypes.RegimeConfig({feePips: 3_000, maxSwapAmount: 50e18, maxImpactTicks: 180, cooldownSeconds: 0});
        policy.hard = StableTypes.RegimeConfig({
            feePips: 10_000,
            maxSwapAmount: 10e18,
            maxImpactTicks: 90,
            cooldownSeconds: 120
        });
    }

    function testSelectRawRegimePaths() public view {
        StableTypes.Regime hardByDistance = DynamicFeeModule.selectRawRegime(300, 0, 0, policy);
        assertEq(uint8(hardByDistance), uint8(StableTypes.Regime.HARD_DEPEG));

        StableTypes.Regime hardByVol = DynamicFeeModule.selectRawRegime(0, 220, 0, policy);
        assertEq(uint8(hardByVol), uint8(StableTypes.Regime.HARD_DEPEG));

        StableTypes.Regime hardBySkew = DynamicFeeModule.selectRawRegime(0, 0, 120_000, policy);
        assertEq(uint8(hardBySkew), uint8(StableTypes.Regime.HARD_DEPEG));

        StableTypes.Regime softByDistance = DynamicFeeModule.selectRawRegime(90, 0, 0, policy);
        assertEq(uint8(softByDistance), uint8(StableTypes.Regime.SOFT_DEPEG));

        StableTypes.Regime softByVol = DynamicFeeModule.selectRawRegime(0, 100, 0, policy);
        assertEq(uint8(softByVol), uint8(StableTypes.Regime.SOFT_DEPEG));

        StableTypes.Regime softBySkew = DynamicFeeModule.selectRawRegime(0, 0, 50_000, policy);
        assertEq(uint8(softBySkew), uint8(StableTypes.Regime.SOFT_DEPEG));

        StableTypes.Regime normal = DynamicFeeModule.selectRawRegime(10, 10, 10, policy);
        assertEq(uint8(normal), uint8(StableTypes.Regime.NORMAL));
    }

    function testApplyHysteresisCandidateEqualsCurrent() public view {
        StableTypes.Regime regime = DynamicFeeModule.applyHysteresis(
            StableTypes.Regime.SOFT_DEPEG,
            StableTypes.Regime.SOFT_DEPEG,
            100,
            policy,
            100,
            200
        );
        assertEq(uint8(regime), uint8(StableTypes.Regime.SOFT_DEPEG));
    }

    function testApplyHysteresisMinTimeGate() public view {
        StableTypes.Regime regime = DynamicFeeModule.applyHysteresis(
            StableTypes.Regime.HARD_DEPEG,
            StableTypes.Regime.NORMAL,
            300,
            policy,
            100,
            150
        );
        assertEq(uint8(regime), uint8(StableTypes.Regime.NORMAL));
    }

    function testApplyHysteresisHardExitBlockedAndAllowed() public view {
        StableTypes.Regime blocked = DynamicFeeModule.applyHysteresis(
            StableTypes.Regime.SOFT_DEPEG,
            StableTypes.Regime.HARD_DEPEG,
            230,
            policy,
            100,
            1000
        );
        assertEq(uint8(blocked), uint8(StableTypes.Regime.HARD_DEPEG));

        StableTypes.Regime allowed = DynamicFeeModule.applyHysteresis(
            StableTypes.Regime.SOFT_DEPEG,
            StableTypes.Regime.HARD_DEPEG,
            200,
            policy,
            100,
            1000
        );
        assertEq(uint8(allowed), uint8(StableTypes.Regime.SOFT_DEPEG));

        StableTypes.Policy memory zeroBandPolicy = policy;
        zeroBandPolicy.hysteresisTicks = zeroBandPolicy.band2Ticks;
        StableTypes.Regime zeroBand = DynamicFeeModule.applyHysteresis(
            StableTypes.Regime.SOFT_DEPEG,
            StableTypes.Regime.HARD_DEPEG,
            0,
            zeroBandPolicy,
            100,
            1000
        );
        assertEq(uint8(zeroBand), uint8(StableTypes.Regime.SOFT_DEPEG));
    }

    function testApplyHysteresisSoftExitBlockedAndAllowed() public view {
        StableTypes.Regime blocked = DynamicFeeModule.applyHysteresis(
            StableTypes.Regime.NORMAL,
            StableTypes.Regime.SOFT_DEPEG,
            70,
            policy,
            100,
            1000
        );
        assertEq(uint8(blocked), uint8(StableTypes.Regime.SOFT_DEPEG));

        StableTypes.Regime allowed = DynamicFeeModule.applyHysteresis(
            StableTypes.Regime.NORMAL,
            StableTypes.Regime.SOFT_DEPEG,
            40,
            policy,
            100,
            1000
        );
        assertEq(uint8(allowed), uint8(StableTypes.Regime.NORMAL));

        StableTypes.Policy memory zeroBandPolicy = policy;
        zeroBandPolicy.hysteresisTicks = zeroBandPolicy.band1Ticks;
        StableTypes.Regime zeroBand = DynamicFeeModule.applyHysteresis(
            StableTypes.Regime.NORMAL,
            StableTypes.Regime.SOFT_DEPEG,
            0,
            zeroBandPolicy,
            100,
            1000
        );
        assertEq(uint8(zeroBand), uint8(StableTypes.Regime.NORMAL));
    }

    function testConfigForRegime() public view {
        StableTypes.RegimeConfig memory normal = DynamicFeeModule.configForRegime(policy, StableTypes.Regime.NORMAL);
        StableTypes.RegimeConfig memory soft = DynamicFeeModule.configForRegime(policy, StableTypes.Regime.SOFT_DEPEG);
        StableTypes.RegimeConfig memory hard = DynamicFeeModule.configForRegime(policy, StableTypes.Regime.HARD_DEPEG);

        assertEq(normal.feePips, policy.normal.feePips);
        assertEq(soft.feePips, policy.soft.feePips);
        assertEq(hard.feePips, policy.hard.feePips);
    }

    function testGuardrailsMaxSwapExceeded() public {
        StableTypes.RegimeConfig memory cfg = policy.normal;
        SwapParams memory params =
            SwapParams({
                zeroForOne: true,
                amountSpecified: int256(uint256(cfg.maxSwapAmount) + 1),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            });

        vm.expectRevert();
        guardrails.enforce(params, 0, cfg, 0, uint40(block.timestamp));
    }

    function testGuardrailsPassesWithDefaultPriceLimitsBothDirections() public {
        StableTypes.RegimeConfig memory cfg = policy.normal;

        SwapParams memory zfo =
            SwapParams({zeroForOne: true, amountSpecified: 1e18, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1});
        guardrails.enforce(zfo, 0, cfg, 0, uint40(block.timestamp));

        SwapParams memory ofz =
            SwapParams({zeroForOne: false, amountSpecified: 1e18, sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1});
        guardrails.enforce(ofz, 0, cfg, 0, uint40(block.timestamp));
    }

    function testGuardrailsMaxImpactExceeded() public {
        StableTypes.RegimeConfig memory cfg = policy.normal;
        cfg.maxImpactTicks = 10;

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 1e18,
            sqrtPriceLimitX96: TickMath.getSqrtPriceAtTick(200)
        });

        vm.expectRevert();
        guardrails.enforce(params, 0, cfg, 0, uint40(block.timestamp));
    }

    function testGuardrailsCustomLimitPassesWhenImpactWithinBoundAndNegativeDeltaPath() public {
        StableTypes.RegimeConfig memory cfg = policy.normal;
        cfg.maxImpactTicks = 500;

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 1e18,
            sqrtPriceLimitX96: TickMath.getSqrtPriceAtTick(20)
        });

        guardrails.enforce(params, 100, cfg, 0, uint40(block.timestamp));
    }

    function testGuardrailsCooldownPaths() public {
        StableTypes.RegimeConfig memory cfg = policy.hard;
        vm.expectRevert();
        guardrails.enforce(
            SwapParams({zeroForOne: true, amountSpecified: 1e18, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            0,
            cfg,
            100,
            150
        );

        guardrails.enforce(
            SwapParams({zeroForOne: true, amountSpecified: 1e18, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            0,
            cfg,
            100,
            220
        );
    }

    function testGuardrailsAbsAmountSpecifiedIntMinPath() public {
        StableTypes.RegimeConfig memory cfg = policy.normal;
        cfg.maxSwapAmount = type(uint128).max;

        SwapParams memory params =
            SwapParams({zeroForOne: true, amountSpecified: type(int256).min, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1});

        vm.expectRevert();
        guardrails.enforce(params, 0, cfg, 0, uint40(block.timestamp));
    }
}
