// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IRewardsVault} from "../interfaces/IRewardsVault.sol";

contract RewardsVault is Ownable2Step, ReentrancyGuard, IRewardsVault {
    using SafeERC20 for IERC20;

    error NotIncentives();

    IERC20 public immutable rewardToken;
    address public incentives;

    uint256 public totalFunded;
    uint256 public totalDisbursed;

    event IncentivesSet(address indexed incentives);
    event RewardsFunded(address indexed sponsor, uint256 amount);
    event RewardsDisbursed(address indexed recipient, uint256 amount);

    constructor(IERC20 rewardToken_, address initialOwner) Ownable(initialOwner) {
        rewardToken = rewardToken_;
    }

    modifier onlyIncentives() {
        if (msg.sender != incentives) revert NotIncentives();
        _;
    }

    function setIncentives(address incentives_) external onlyOwner {
        incentives = incentives_;
        emit IncentivesSet(incentives_);
    }

    function fundFrom(address sponsor, uint256 amount) external onlyIncentives nonReentrant {
        rewardToken.safeTransferFrom(sponsor, address(this), amount);
        totalFunded += amount;
        emit RewardsFunded(sponsor, amount);
    }

    function disburse(address recipient, uint256 amount) external onlyIncentives nonReentrant {
        if (amount == 0) {
            return;
        }

        totalDisbursed += amount;
        rewardToken.safeTransfer(recipient, amount);
        emit RewardsDisbursed(recipient, amount);
    }

    function availableRewards() external view returns (uint256) {
        return rewardToken.balanceOf(address(this));
    }
}
