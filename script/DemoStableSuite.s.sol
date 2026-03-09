// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2 as console} from "forge-std/Script.sol";

import {Deployers} from "test/utils/Deployers.sol";

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";

import {StableSuiteHook} from "../src/core/StableSuiteHook.sol";
import {StablePolicyController} from "../src/core/StablePolicyController.sol";
import {StickyLiquidityIncentives} from "../src/incentives/StickyLiquidityIncentives.sol";
import {StableTypes} from "../src/libraries/StableTypes.sol";

contract DemoStableSuiteScript is Script, Deployers {
    using PoolIdLibrary for PoolKey;

    function run() external {
        deployArtifacts();

        address hookAddress = vm.envAddress("HOOK");
        address controllerAddress = vm.envAddress("CONTROLLER");
        address incentivesAddress = vm.envAddress("INCENTIVES");

        address token0 = vm.envAddress("TOKEN0");
        address token1 = vm.envAddress("TOKEN1");
        int24 tickSpacing = int24(int256(vm.envOr("TICK_SPACING", uint256(60))));

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(token0 < token1 ? token0 : token1),
            currency1: Currency.wrap(token0 < token1 ? token1 : token0),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: tickSpacing,
            hooks: IHooks(hookAddress)
        });
        PoolId poolId = key.toId();

        StableSuiteHook hook = StableSuiteHook(hookAddress);
        StablePolicyController controller = StablePolicyController(controllerAddress);
        StickyLiquidityIncentives incentives = StickyLiquidityIncentives(incentivesAddress);

        string memory mode = vm.envOr("DEMO_MODE", string("all"));

        vm.startBroadcast();

        if (_equals(mode, "all") || _equals(mode, "normal")) {
            _runNormalDemo(key, hook, poolId);
        }

        if (_equals(mode, "all") || _equals(mode, "depeg")) {
            _runDepegDemo(key, hook, controller, poolId);
        }

        if (_equals(mode, "all") || _equals(mode, "incentives")) {
            _runIncentivesDemo(incentives, poolId);
        }

        vm.stopBroadcast();
    }

    function _runNormalDemo(PoolKey memory key, StableSuiteHook hook, PoolId poolId) internal {
        console.log("=== Normal Peg Demo ===");

        swapRouter.swapExactTokensForTokens({
            amountIn: 5e16,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: key,
            hookData: bytes(""),
            receiver: msg.sender,
            deadline: block.timestamp + 120
        });

        _logRegime(hook, poolId);
    }

    function _runDepegDemo(PoolKey memory key, StableSuiteHook hook, StablePolicyController controller, PoolId poolId)
        internal
    {
        console.log("=== Depeg Stress Demo ===");

        StableTypes.PolicyInput memory policy = _stressPolicy();
        controller.configurePoolPolicy(key, policy);

        swapRouter.swapExactTokensForTokens({
            amountIn: 1e16,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: key,
            hookData: bytes(""),
            receiver: msg.sender,
            deadline: block.timestamp + 120
        });

        _logRegime(hook, poolId);

        try swapRouter.swapExactTokensForTokens({
            amountIn: 1e16,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: key,
            hookData: bytes(""),
            receiver: msg.sender,
            deadline: block.timestamp + 120
        }) {
            console.log("unexpected: second stress swap was not blocked");
        } catch {
            console.log("expected: cooldown blocked immediate second stress swap");
        }
    }

    function _runIncentivesDemo(StickyLiquidityIncentives incentives, PoolId poolId) internal {
        console.log("=== Incentives Demo ===");

        (uint256 claimableAmount, uint256 penaltyAmount) = incentives.claimable(poolId, msg.sender);
        console.log("claimable", claimableAmount);
        console.log("penaltyIfClaimed", penaltyAmount);

        (uint256 claimed, uint256 penalty) = incentives.claim(poolId, msg.sender);
        console.log("claimed", claimed);
        console.log("penalty", penalty);
    }

    function _logRegime(StableSuiteHook hook, PoolId poolId) internal view {
        (
            bool initialized,
            StableTypes.Regime regime,
            int24 lastObservedTick,
            uint32 smoothedVolatility,
            int64 flowSkew,
            uint40 lastObservationTimestamp,
            uint40 regimeSince,
            uint40 lastHardSwapTimestamp,
            uint64 policyNonce
        ) = hook.runtime(poolId);

        console.log("initialized", initialized);
        console.log("regime", uint256(uint8(regime)));
        console.log("lastObservedTick", int256(lastObservedTick));
        console.log("smoothedVolatility", uint256(smoothedVolatility));
        console.log("flowSkew", int256(flowSkew));
        console.log("lastObservationTimestamp", uint256(lastObservationTimestamp));
        console.log("regimeSince", uint256(regimeSince));
        console.log("lastHardSwapTimestamp", uint256(lastHardSwapTimestamp));
        console.log("policyNonce", uint256(policyNonce));
    }

    function _stressPolicy() internal pure returns (StableTypes.PolicyInput memory policy) {
        policy.dynamicFeeEnabled = true;
        policy.pegTick = -500;
        policy.band1Ticks = 10;
        policy.band2Ticks = 20;
        policy.hysteresisTicks = 1;
        policy.minTimeInRegime = 0;
        policy.volatilityWindow = 30;
        policy.softVolatilityThreshold = 10;
        policy.hardVolatilityThreshold = 20;
        policy.softFlowSkewThreshold = 10;
        policy.hardFlowSkewThreshold = 20;

        policy.normal =
            StableTypes.RegimeConfig({feePips: 500, maxSwapAmount: 50e18, maxImpactTicks: 400, cooldownSeconds: 0});
        policy.soft =
            StableTypes.RegimeConfig({feePips: 3_000, maxSwapAmount: 10e18, maxImpactTicks: 200, cooldownSeconds: 0});
        policy.hard =
            StableTypes.RegimeConfig({feePips: 10_000, maxSwapAmount: 2e18, maxImpactTicks: 120, cooldownSeconds: 120});

        policy.incentives = StableTypes.IncentiveConfig({
            warmupSeconds: 60, cooldownSeconds: 180, cooldownPenaltyBps: 2000, emissionRate: 1e18
        });
    }

    function _equals(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function _etch(address target, bytes memory bytecode) internal override {
        if (block.chainid == 31337) {
            vm.rpc("anvil_setCode", string.concat('["', vm.toString(target), '",', '"', vm.toString(bytecode), '"]'));
        } else {
            revert("Unsupported etch");
        }
    }
}
