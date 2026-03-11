// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {RewardsVault} from "../src/incentives/RewardsVault.sol";
import {MockRewardToken} from "../src/mocks/MockRewardToken.sol";

contract RewardsVaultCoverageTest is Test {
    RewardsVault internal vault;
    MockRewardToken internal rewardToken;

    address internal incentives = address(0xBEEF);
    address internal sponsor = address(0xCAFE);
    address internal recipient = address(0xABCD);

    function setUp() public {
        rewardToken = new MockRewardToken();
        vault = new RewardsVault(rewardToken, address(this));

        rewardToken.mint(sponsor, 1_000e18);
    }

    function testOnlyIncentivesGatesFundAndDisburse() public {
        vm.expectRevert(RewardsVault.NotIncentives.selector);
        vault.fundFrom(sponsor, 1e18);

        vm.expectRevert(RewardsVault.NotIncentives.selector);
        vault.disburse(recipient, 1e18);
    }

    function testFundDisburseAndAvailableRewards() public {
        vault.setIncentives(incentives);

        vm.startPrank(sponsor);
        rewardToken.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        vm.prank(incentives);
        vault.fundFrom(sponsor, 100e18);

        assertEq(vault.totalFunded(), 100e18);
        assertEq(vault.availableRewards(), 100e18);

        vm.prank(incentives);
        vault.disburse(recipient, 0);
        assertEq(vault.totalDisbursed(), 0);

        vm.prank(incentives);
        vault.disburse(recipient, 40e18);

        assertEq(vault.totalDisbursed(), 40e18);
        assertEq(vault.availableRewards(), 60e18);
        assertEq(rewardToken.balanceOf(recipient), 40e18);
    }
}
