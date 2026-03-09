// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {StableTypes} from "../libraries/StableTypes.sol";

interface IStablePolicyController {
    function getPolicy(PoolId poolId) external view returns (StableTypes.Policy memory);

    function getPolicyNonce(PoolId poolId) external view returns (uint64);

    function configurePoolPolicy(PoolKey calldata key, StableTypes.PolicyInput calldata policyInput) external;

    function queuePolicyUpdate(PoolKey calldata key, StableTypes.PolicyInput calldata policyInput) external;

    function executePolicyUpdate(PoolKey calldata key, StableTypes.PolicyInput calldata policyInput) external;
}
