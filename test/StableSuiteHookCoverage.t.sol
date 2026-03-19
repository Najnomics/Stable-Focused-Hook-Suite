// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

import {StableSuiteBase} from "./utils/StableSuiteBase.sol";
import {StableSuiteHook} from "../src/core/StableSuiteHook.sol";
import {StickyLiquidityIncentives} from "../src/incentives/StickyLiquidityIncentives.sol";
import {IStablePolicyController} from "../src/interfaces/IStablePolicyController.sol";

contract StableSuiteHookCoverageTest is StableSuiteBase {
    using PoolIdLibrary for PoolKey;

    function setUp() public {
        setUpSuite();
    }

    function testBeforeAddLiquidityEarlyReturnForNonPositiveDelta() public {
        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: 0, tickUpper: 1, liquidityDelta: 0, salt: bytes32(0)});

        vm.prank(address(poolManager));
        bytes4 selector = hook.beforeAddLiquidity(address(this), poolKey, params, bytes(""));

        assertEq(selector, hook.beforeAddLiquidity.selector);
    }

    function testBeforeRemoveLiquidityEarlyReturnForNonNegativeDelta() public {
        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: 0, tickUpper: 1, liquidityDelta: 1, salt: bytes32(0)});

        vm.prank(address(poolManager));
        bytes4 selector = hook.beforeRemoveLiquidity(address(this), poolKey, params, bytes(""));

        assertEq(selector, hook.beforeRemoveLiquidity.selector);
    }

    function testBeforeAddLiquidityUses20ByteHookDataAccount() public {
        address beneficiary = address(0xBEEF);

        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: 0, tickUpper: 1, liquidityDelta: 5, salt: bytes32(0)});

        vm.prank(address(poolManager));
        hook.beforeAddLiquidity(address(this), poolKey, params, abi.encodePacked(beneficiary));

        StickyLiquidityIncentives.UserState memory user = incentives.getUserState(poolId, beneficiary);
        assertEq(user.pendingWeight, 5);
    }

    function testBeforeAddLiquidityNoIncentivesStillReturnsSelector() public {
        address noIncentivesHookAddress = address(
            uint160(
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG
                    | Hooks.AFTER_SWAP_FLAG
            ) ^ (0x6666 << 144)
        );

        bytes memory constructorArgs = abi.encode(poolManager, IStablePolicyController(controller), address(0));
        deployCodeTo("StableSuiteHook.sol:StableSuiteHook", constructorArgs, noIncentivesHookAddress);
        StableSuiteHook noIncentivesHook = StableSuiteHook(noIncentivesHookAddress);

        PoolKey memory noIncentivesPoolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(address(noIncentivesHook))
        });

        controller.configurePoolPolicy(noIncentivesPoolKey, defaultPolicyInput());

        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: 0, tickUpper: 1, liquidityDelta: 5, salt: bytes32(0)});

        vm.prank(address(poolManager));
        bytes4 selector = noIncentivesHook.beforeAddLiquidity(address(this), noIncentivesPoolKey, params, bytes(""));
        assertEq(selector, noIncentivesHook.beforeAddLiquidity.selector);
    }

    function testBeforeRemoveLiquidityNoIncentivesStillReturnsSelector() public {
        address noIncentivesHookAddress = address(
            uint160(
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG
                    | Hooks.AFTER_SWAP_FLAG
            ) ^ (0x7777 << 144)
        );

        bytes memory constructorArgs = abi.encode(poolManager, IStablePolicyController(controller), address(0));
        deployCodeTo("StableSuiteHook.sol:StableSuiteHook", constructorArgs, noIncentivesHookAddress);
        StableSuiteHook noIncentivesHook = StableSuiteHook(noIncentivesHookAddress);

        PoolKey memory noIncentivesPoolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(address(noIncentivesHook))
        });

        controller.configurePoolPolicy(noIncentivesPoolKey, defaultPolicyInput());

        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: 0, tickUpper: 1, liquidityDelta: -int256(uint256(3)), salt: bytes32(0)});

        vm.prank(address(poolManager));
        bytes4 selector = noIncentivesHook.beforeRemoveLiquidity(address(this), noIncentivesPoolKey, params, bytes(""));
        assertEq(selector, noIncentivesHook.beforeRemoveLiquidity.selector);
    }

    function testBeforeAddLiquidityFallsBackToSenderWhenHookDataEmpty() public {
        address sender = address(0xCAFE);

        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: 0, tickUpper: 1, liquidityDelta: 7, salt: bytes32(0)});

        vm.prank(address(poolManager));
        hook.beforeAddLiquidity(sender, poolKey, params, bytes(""));

        StickyLiquidityIncentives.UserState memory user = incentives.getUserState(poolId, sender);
        assertEq(user.pendingWeight, 7);
    }

    function testBeforeRemoveLiquidityClampPathRevertsOnInsufficientWeight() public {
        int256 largeNegative = -int256(uint256(type(uint128).max) + 1);
        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: 0, tickUpper: 1, liquidityDelta: largeNegative, salt: bytes32(0)});

        vm.prank(address(poolManager));
        vm.expectRevert();
        hook.beforeRemoveLiquidity(address(this), poolKey, params, abi.encode(address(this)));
    }

    function testBeforeRemoveLiquiditySuccessfulPathReturnsSelector() public {
        address account = address(0xC0FFEE);

        ModifyLiquidityParams memory addParams =
            ModifyLiquidityParams({tickLower: 0, tickUpper: 1, liquidityDelta: 9, salt: bytes32(0)});

        vm.prank(address(poolManager));
        hook.beforeAddLiquidity(account, poolKey, addParams, bytes(""));

        ModifyLiquidityParams memory removeParams =
            ModifyLiquidityParams({tickLower: 0, tickUpper: 1, liquidityDelta: -int256(uint256(9)), salt: bytes32(0)});

        vm.prank(address(poolManager));
        bytes4 selector = hook.beforeRemoveLiquidity(account, poolKey, removeParams, abi.encode(account));
        assertEq(selector, hook.beforeRemoveLiquidity.selector);
    }

    function testBeforeSwapRevertsWhenPolicyMissing() public {
        PoolKey memory unknownKey = PoolKey({
            currency0: Currency.wrap(address(0x1111)),
            currency1: Currency.wrap(address(0x2222)),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        SwapParams memory params =
            SwapParams({zeroForOne: true, amountSpecified: 1e18, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1});

        vm.prank(address(poolManager));
        vm.expectRevert();
        hook.beforeSwap(address(this), unknownKey, params, bytes(""));
    }

    function testAfterSwapIntMinPathAndPositiveClamp() public {
        SwapParams memory params =
            SwapParams({zeroForOne: false, amountSpecified: type(int256).min, sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1});

        vm.prank(address(poolManager));
        hook.afterSwap(address(this), poolKey, params, BalanceDelta.wrap(0), bytes(""));

        (,,, uint32 smoothedVolatility, int64 flowSkew,,,,) = hook.runtime(poolId);
        assertEq(smoothedVolatility, 0);
        assertGt(flowSkew, 0);
        assertLe(uint64(uint256(int256(flowSkew))), uint64(2_400_000));
    }

    function testBeforeSwapVolatilityWindowResetBranch() public {
        SwapParams memory params =
            SwapParams({zeroForOne: true, amountSpecified: 1e18, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1});

        vm.prank(address(poolManager));
        hook.beforeSwap(address(this), poolKey, params, bytes(""));

        vm.warp(block.timestamp + 31);

        vm.prank(address(poolManager));
        hook.beforeSwap(address(this), poolKey, params, bytes(""));

        (,,, uint32 smoothedVolatility,,,,,) = hook.runtime(poolId);
        assertEq(smoothedVolatility, 0);
    }
}
