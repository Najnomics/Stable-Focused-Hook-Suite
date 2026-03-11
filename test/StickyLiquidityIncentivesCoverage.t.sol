// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";

import {StableSuiteBase} from "./utils/StableSuiteBase.sol";
import {StickyLiquidityIncentives} from "../src/incentives/StickyLiquidityIncentives.sol";
import {StableTypes} from "../src/libraries/StableTypes.sol";
import {EasyPosm} from "./utils/libraries/EasyPosm.sol";

contract StickyLiquidityIncentivesCoverageTest is StableSuiteBase {
    using EasyPosm for IPositionManager;

    function setUp() public {
        setUpSuite();
        rewardToken.approve(address(vault), type(uint256).max);
        incentives.fundProgram(poolId, 200_000e18);
    }

    function testAccessControlRevertsForHookAndOwnerOrHook() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert(StickyLiquidityIncentives.NotHook.selector);
        incentives.onLiquidityAdded(poolId, address(this), 1);

        vm.prank(address(0xDEAD));
        vm.expectRevert(StickyLiquidityIncentives.NotHook.selector);
        incentives.onLiquidityRemoved(poolId, address(this), 1);

        StableTypes.IncentiveConfig memory cfg = defaultPolicyInput().incentives;
        vm.prank(address(0xBEEF));
        vm.expectRevert(StickyLiquidityIncentives.NotOwnerOrHook.selector);
        incentives.syncPolicy(poolId, cfg);
    }

    function testSetProgramEnabledTimestampInitAndSecondToggle() public {
        PoolId otherPool = PoolId.wrap(bytes32(uint256(12345)));

        incentives.setProgramEnabled(otherPool, true);
        StickyLiquidityIncentives.ProgramState memory first = incentives.getProgram(otherPool);
        assertGt(first.lastAccrualTimestamp, 0);

        vm.warp(block.timestamp + 30);
        incentives.setProgramEnabled(otherPool, false);
        StickyLiquidityIncentives.ProgramState memory second = incentives.getProgram(otherPool);
        assertEq(second.lastAccrualTimestamp, first.lastAccrualTimestamp);
    }

    function testSyncPolicyByHookIsAllowed() public {
        StableTypes.IncentiveConfig memory cfg = defaultPolicyInput().incentives;
        cfg.cooldownPenaltyBps = 999;

        vm.prank(address(hook));
        incentives.syncPolicy(poolId, cfg);

        StickyLiquidityIncentives.ProgramState memory program = incentives.getProgram(poolId);
        assertEq(program.warmupSeconds, cfg.warmupSeconds);
        assertEq(program.cooldownSeconds, cfg.cooldownSeconds);
        assertEq(program.cooldownPenaltyBps, cfg.cooldownPenaltyBps);
    }

    function testGettersAndEmptyClaimablePath() public view {
        PoolId otherPool = PoolId.wrap(bytes32(uint256(777)));
        (uint256 amount, uint256 penalty) = incentives.claimable(otherPool, address(this));
        assertEq(amount, 0);
        assertEq(penalty, 0);

        incentives.getProgram(poolId);
        incentives.getUserState(poolId, address(this));
    }

    function testOnLiquidityRemovedInsufficientWeightReverts() public {
        vm.prank(address(hook));
        vm.expectRevert(StickyLiquidityIncentives.InsufficientWeight.selector);
        incentives.onLiquidityRemoved(poolId, address(this), type(uint128).max);
    }

    function testOnLiquidityRemovedHitsActiveWeightPath() public {
        uint256 tokenId = _mintLiquidity(address(this), 40e18);

        vm.warp(block.timestamp + 61);
        incentives.claim(poolId, address(this));

        StickyLiquidityIncentives.UserState memory beforeState = incentives.getUserState(poolId, address(this));

        positionManager.decreaseLiquidity(tokenId, 10e18, 0, 0, address(this), block.timestamp + 1, abi.encode(address(this)));

        StickyLiquidityIncentives.UserState memory afterState = incentives.getUserState(poolId, address(this));
        assertLt(afterState.activeWeight, beforeState.activeWeight);
    }

    function testClaimableMaturePendingAndPenaltyBranch() public {
        uint256 tokenId = _mintLiquidity(address(this), 20e18);

        vm.warp(block.timestamp + 61);
        (uint256 beforePenaltyAmount, uint256 beforePenaltyValue) = incentives.claimable(poolId, address(this));
        assertGe(beforePenaltyAmount, 0);
        assertEq(beforePenaltyValue, 0);

        incentives.claim(poolId, address(this));

        positionManager.decreaseLiquidity(tokenId, 20e18, 0, 0, address(this), block.timestamp + 1, abi.encode(address(this)));

        StickyLiquidityIncentives.UserState memory user = incentives.getUserState(poolId, address(this));
        assertGt(user.penaltyEndsAt, block.timestamp);

        vm.warp(block.timestamp + 120);
        (uint256 afterPenaltyAmount, uint256 afterPenaltyValue) = incentives.claimable(poolId, address(this));

        assertGt(afterPenaltyAmount, 0);
        assertGt(afterPenaltyValue, 0);
    }
}
