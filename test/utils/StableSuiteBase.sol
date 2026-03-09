// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BaseTest} from "./BaseTest.sol";
import {EasyPosm} from "./libraries/EasyPosm.sol";

import {StablePolicyController} from "../../src/core/StablePolicyController.sol";
import {StableSuiteHook} from "../../src/core/StableSuiteHook.sol";
import {StickyLiquidityIncentives} from "../../src/incentives/StickyLiquidityIncentives.sol";
import {RewardsVault} from "../../src/incentives/RewardsVault.sol";
import {MockRewardToken} from "../../src/mocks/MockRewardToken.sol";
import {StableTypes} from "../../src/libraries/StableTypes.sol";

abstract contract StableSuiteBase is BaseTest {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    Currency internal currency0;
    Currency internal currency1;

    StablePolicyController internal controller;
    StableSuiteHook internal hook;
    StickyLiquidityIncentives internal incentives;
    RewardsVault internal vault;
    MockRewardToken internal rewardToken;

    PoolKey internal poolKey;
    PoolId internal poolId;

    int24 internal tickLower;
    int24 internal tickUpper;

    function setUpSuite() internal {
        deployArtifactsAndLabel();
        (currency0, currency1) = deployCurrencyPair();

        controller = new StablePolicyController(address(this), 0);
        rewardToken = new MockRewardToken();
        vault = new RewardsVault(IERC20(address(rewardToken)), address(this));
        incentives = new StickyLiquidityIncentives(vault, address(this));

        address flags = address(
            uint160(
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG
                    | Hooks.AFTER_SWAP_FLAG
            ) ^ (0x5555 << 144)
        );

        bytes memory constructorArgs = abi.encode(poolManager, controller, incentives);
        deployCodeTo("StableSuiteHook.sol:StableSuiteHook", constructorArgs, flags);
        hook = StableSuiteHook(flags);

        incentives.setHook(address(hook));
        vault.setIncentives(address(incentives));

        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        poolId = poolKey.toId();

        controller.configurePoolPolicy(poolKey, defaultPolicyInput());
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);

        _mintLiquidity(address(this), 200e18);

        rewardToken.mint(address(this), 2_000_000e18);
        incentives.setProgramEnabled(poolId, true);
    }

    function defaultPolicyInput() internal pure returns (StableTypes.PolicyInput memory policy) {
        policy.dynamicFeeEnabled = true;
        policy.pegTick = 0;
        policy.band1Ticks = 80;
        policy.band2Ticks = 240;
        policy.hysteresisTicks = 20;
        policy.minTimeInRegime = 5 minutes;
        policy.volatilityWindow = 30;
        policy.softVolatilityThreshold = 100;
        policy.hardVolatilityThreshold = 220;
        policy.softFlowSkewThreshold = 100_000;
        policy.hardFlowSkewThreshold = 300_000;

        policy.normal =
            StableTypes.RegimeConfig({feePips: 500, maxSwapAmount: 50e18, maxImpactTicks: 300, cooldownSeconds: 0});

        policy.soft =
            StableTypes.RegimeConfig({feePips: 3_000, maxSwapAmount: 20e18, maxImpactTicks: 180, cooldownSeconds: 0});

        policy.hard =
            StableTypes.RegimeConfig({feePips: 10_000, maxSwapAmount: 5e18, maxImpactTicks: 90, cooldownSeconds: 120});

        policy.incentives = StableTypes.IncentiveConfig({
            warmupSeconds: 60, cooldownSeconds: 180, cooldownPenaltyBps: 2_000, emissionRate: 1e18
        });
    }

    function _mintLiquidity(address owner, uint128 liquidityAmount) internal returns (uint256 tokenId) {
        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        (tokenId,) = positionManager.mint(
            poolKey,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            owner,
            block.timestamp,
            abi.encode(owner)
        );
    }

    function _swapExactIn(uint256 amountIn, bool zeroForOne) internal returns (BalanceDelta delta) {
        delta = swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: zeroForOne,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 10
        });
    }
}
