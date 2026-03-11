// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

import {StableSuiteBase} from "./utils/StableSuiteBase.sol";
import {StableSuiteHook} from "../src/core/StableSuiteHook.sol";
import {StickyLiquidityIncentives} from "../src/incentives/StickyLiquidityIncentives.sol";

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
}
