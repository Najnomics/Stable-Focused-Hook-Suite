// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2 as console} from "forge-std/Script.sol";

import {Deployers} from "test/utils/Deployers.sol";

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
        uint256 normalSwapAmount = vm.envOr("DEMO_NORMAL_SWAP_AMOUNT", uint256(1_000_000));
        uint256 depegSwapAmount = vm.envOr("DEMO_DEPEG_SWAP_AMOUNT", uint256(2_000_000));
        uint256 depegSecondSwapAmount = vm.envOr("DEMO_DEPEG_SECOND_SWAP_AMOUNT", uint256(1_000_000));

        vm.startBroadcast();
        _ensureSwapApprovals(token0, token1);

        console.log("=== Stable Suite End-to-End Demo ===");
        console.log("mode", mode);
        console.log("poolId");
        console.logBytes32(PoolId.unwrap(poolId));
        console.log("token0", token0 < token1 ? token0 : token1);
        console.log("token1", token0 < token1 ? token1 : token0);
        _logPolicy(controller, poolId);
        _logProgram(incentives, poolId, msg.sender);

        if (_equals(mode, "all") || _equals(mode, "normal")) {
            _runNormalDemo(key, hook, controller, incentives, poolId, normalSwapAmount);
        }

        if (_equals(mode, "all") || _equals(mode, "depeg")) {
            _runDepegDemo(key, hook, controller, incentives, poolId, depegSwapAmount, depegSecondSwapAmount);
        }

        if (_equals(mode, "all") || _equals(mode, "incentives")) {
            _runIncentivesDemo(incentives, poolId);
        }

        vm.stopBroadcast();
    }

    function _runNormalDemo(
        PoolKey memory key,
        StableSuiteHook hook,
        StablePolicyController controller,
        StickyLiquidityIncentives incentives,
        PoolId poolId,
        uint256 amountIn
    ) internal {
        console.log("=== Normal Peg Demo ===");
        console.log("user-action: swap in normal conditions");
        _logPolicy(controller, poolId);
        _logProgram(incentives, poolId, msg.sender);
        _logRegime(hook, poolId);

        swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: key,
            hookData: bytes(""),
            receiver: msg.sender,
            deadline: block.timestamp + 120
        });

        console.log("result: swap executed under normal regime checks");
        _logRegime(hook, poolId);
        _logProgram(incentives, poolId, msg.sender);
    }

    function _runDepegDemo(
        PoolKey memory key,
        StableSuiteHook hook,
        StablePolicyController controller,
        StickyLiquidityIncentives incentives,
        PoolId poolId,
        uint256 firstSwapAmount,
        uint256 secondSwapAmount
    ) internal {
        console.log("=== Depeg Stress Demo ===");
        console.log("admin-action: tighten policy to force hard depeg regime selection");

        StableTypes.PolicyInput memory policy = _stressPolicy();
        controller.configurePoolPolicy(key, policy);
        _logPolicy(controller, poolId);

        (bool cooldownActiveBefore,,) = _cooldownStatus(hook, controller, poolId);
        if (cooldownActiveBefore) {
            console.log("depeg.swap.skippedBecauseCooldownAlreadyActive", true);
            _logCooldownProjection(hook, controller, poolId, secondSwapAmount);
            return;
        }

        swapRouter.swapExactTokensForTokens({
            amountIn: firstSwapAmount,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: key,
            hookData: bytes(""),
            receiver: msg.sender,
            deadline: block.timestamp + 120
        });

        _logRegime(hook, poolId);
        _logProgram(incentives, poolId, msg.sender);
        _logCooldownProjection(hook, controller, poolId, secondSwapAmount);
    }

    function _runIncentivesDemo(StickyLiquidityIncentives incentives, PoolId poolId) internal {
        console.log("=== Incentives Demo ===");
        console.log("user-action: query and claim sticky-liquidity rewards");

        (uint256 claimableAmount, uint256 penaltyAmount) = incentives.claimable(poolId, msg.sender);
        console.log("claimable", claimableAmount);
        console.log("penaltyIfClaimed", penaltyAmount);

        (uint256 claimed, uint256 penalty) = incentives.claim(poolId, msg.sender);
        console.log("claimed", claimed);
        console.log("penalty", penalty);
        _logProgram(incentives, poolId, msg.sender);
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

    function _logPolicy(StablePolicyController controller, PoolId poolId) internal view {
        StableTypes.Policy memory policy = controller.getPolicy(poolId);
        if (!policy.exists) {
            console.log("policy: not configured");
            return;
        }

        console.log("policy.dynamicFeeEnabled", policy.dynamicFeeEnabled);
        console.log("policy.pegTick", int256(policy.pegTick));
        console.log("policy.band1Ticks", uint256(policy.band1Ticks));
        console.log("policy.band2Ticks", uint256(policy.band2Ticks));
        console.log("policy.hysteresisTicks", uint256(policy.hysteresisTicks));
        console.log("policy.minTimeInRegime", uint256(policy.minTimeInRegime));
        console.log("policy.policyNonce", uint256(policy.policyNonce));
    }

    function _logProgram(StickyLiquidityIncentives incentives, PoolId poolId, address account) internal view {
        StickyLiquidityIncentives.ProgramState memory program = incentives.getProgram(poolId);
        StickyLiquidityIncentives.UserState memory user = incentives.getUserState(poolId, account);

        console.log("program.enabled", program.enabled);
        console.log("program.warmupSeconds", uint256(program.warmupSeconds));
        console.log("program.cooldownSeconds", uint256(program.cooldownSeconds));
        console.log("program.cooldownPenaltyBps", uint256(program.cooldownPenaltyBps));
        console.log("program.emissionRate", uint256(program.emissionRate));
        console.log("program.totalActiveWeight", uint256(program.totalActiveWeight));
        console.log("program.totalPendingWeight", uint256(program.totalPendingWeight));
        console.log("program.rewardBudget", program.rewardBudget);
        console.log("program.totalFunded", program.totalFunded);
        console.log("program.totalClaimed", program.totalClaimed);
        console.log("program.penaltyRetained", program.penaltyRetained);

        console.log("user.activeWeight", uint256(user.activeWeight));
        console.log("user.pendingWeight", uint256(user.pendingWeight));
        console.log("user.accrued", user.accrued);
        console.log("user.pendingActivationTime", uint256(user.pendingActivationTime));
        console.log("user.penaltyEndsAt", uint256(user.penaltyEndsAt));
    }

    function _logCooldownProjection(StableSuiteHook hook, StablePolicyController controller, PoolId poolId, uint256 amount)
        internal
        view
    {
        (bool cooldownActive, uint256 cooldownEndsAt, uint40 lastHardSwapTimestamp) =
            _cooldownStatus(hook, controller, poolId);
        (, StableTypes.Regime regime,,,,,,,) = hook.runtime(poolId);
        StableTypes.Policy memory policy = controller.getPolicy(poolId);
        bool amountWithinHardCap = amount <= policy.hard.maxSwapAmount;

        console.log("cooldown.check.amount", amount);
        console.log("cooldown.check.lastHardSwapTimestamp", uint256(lastHardSwapTimestamp));
        console.log("cooldown.check.cooldownSeconds", uint256(policy.hard.cooldownSeconds));
        console.log("cooldown.check.cooldownEndsAt", cooldownEndsAt);
        console.log("cooldown.check.now", block.timestamp);
        console.log("cooldown.check.cooldownActive", cooldownActive);
        console.log("cooldown.check.amountWithinHardCap", amountWithinHardCap);
        console.log("cooldown.check.regime", uint256(uint8(regime)));
    }

    function _cooldownStatus(StableSuiteHook hook, StablePolicyController controller, PoolId poolId)
        internal
        view
        returns (bool cooldownActive, uint256 cooldownEndsAt, uint40 lastHardSwapTimestamp)
    {
        StableTypes.Policy memory policy = controller.getPolicy(poolId);
        (,,,,,,, lastHardSwapTimestamp,) = hook.runtime(poolId);
        cooldownEndsAt = uint256(lastHardSwapTimestamp) + uint256(policy.hard.cooldownSeconds);
        cooldownActive = lastHardSwapTimestamp != 0 && block.timestamp < cooldownEndsAt;
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
            StableTypes.RegimeConfig({feePips: 3_000, maxSwapAmount: 1e18, maxImpactTicks: 200, cooldownSeconds: 0});
        policy.hard =
            StableTypes.RegimeConfig({feePips: 10_000, maxSwapAmount: 2_000_000, maxImpactTicks: 120, cooldownSeconds: 120});

        policy.incentives = StableTypes.IncentiveConfig({
            warmupSeconds: 15, cooldownSeconds: 180, cooldownPenaltyBps: 2000, emissionRate: 1e18
        });
    }

    function _equals(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function _ensureSwapApprovals(address token0, address token1) internal {
        IERC20(token0).approve(address(swapRouter), type(uint256).max);
        IERC20(token1).approve(address(swapRouter), type(uint256).max);
    }

    function _etch(address target, bytes memory bytecode) internal override {
        if (block.chainid == 31337) {
            vm.rpc("anvil_setCode", string.concat('["', vm.toString(target), '",', '"', vm.toString(bytecode), '"]'));
        } else {
            revert("Unsupported etch");
        }
    }
}
