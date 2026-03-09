// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IRewardsVault {
    function fundFrom(address sponsor, uint256 amount) external;

    function disburse(address recipient, uint256 amount) external;
}
