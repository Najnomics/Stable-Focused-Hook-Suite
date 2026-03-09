// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {StableTypes} from "../libraries/StableTypes.sol";

interface IStickyLiquidityIncentives {
    function syncPolicy(PoolId poolId, StableTypes.IncentiveConfig calldata config) external;

    function onLiquidityAdded(PoolId poolId, address account, uint128 liquidityDelta) external;

    function onLiquidityRemoved(PoolId poolId, address account, uint128 liquidityDelta) external;

    function claim(PoolId poolId, address to) external returns (uint256 claimedAmount, uint256 penaltyAmount);

    function fundProgram(PoolId poolId, uint256 amount) external;

    function claimable(PoolId poolId, address account) external view returns (uint256 amount, uint256 penalty);
}
