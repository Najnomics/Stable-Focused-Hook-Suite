// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";

import {StableSuiteBase} from "./utils/StableSuiteBase.sol";
import {EasyPosm} from "./utils/libraries/EasyPosm.sol";

contract StickyLiquidityIncentivesTest is StableSuiteBase {
    using EasyPosm for IPositionManager;

    function setUp() public {
        setUpSuite();

        rewardToken.approve(address(vault), type(uint256).max);
        incentives.fundProgram(poolId, 100_000e18);
    }

    function testWarmupBoundary() public {
        (uint256 claimableBefore,) = incentives.claimable(poolId, address(this));
        assertEq(claimableBefore, 0);

        vm.warp(block.timestamp + 61);
        incentives.claim(poolId, address(this)); // activates pending weight

        vm.warp(block.timestamp + 30);
        (uint256 claimableAfter,) = incentives.claimable(poolId, address(this));
        assertGt(claimableAfter, 0);

        (uint256 claimed,) = incentives.claim(poolId, address(this));
        assertGt(claimed, 0);
    }

    function testWithdrawDuringCooldownPenalty() public {
        vm.warp(block.timestamp + 61);

        uint256 tokenId = _mintLiquidity(address(this), 50e18);

        // Rapid remove to trigger cooldown penalty.
        positionManager.decreaseLiquidity(
            tokenId, 50e18, 0, 0, address(this), block.timestamp + 1, abi.encode(address(this))
        );

        vm.warp(block.timestamp + 10);

        (uint256 claimed, uint256 penalty) = incentives.claim(poolId, address(this));
        assertGt(penalty, 0);
        assertGt(claimed, 0);
    }

    function testClaimTwiceSecondClaimZero() public {
        vm.warp(block.timestamp + 61);
        incentives.claim(poolId, address(this)); // activates pending weight
        vm.warp(block.timestamp + 60);

        (uint256 firstClaim,) = incentives.claim(poolId, address(this));
        assertGt(firstClaim, 0);

        (uint256 secondClaim, uint256 secondPenalty) = incentives.claim(poolId, address(this));
        assertEq(secondClaim, 0);
        assertEq(secondPenalty, 0);
    }

    function testRewardsClaimedNeverExceedFunded() public {
        vm.warp(block.timestamp + 365 days);
        incentives.claim(poolId, address(this));

        assertLe(vault.totalDisbursed(), vault.totalFunded());
    }
}
