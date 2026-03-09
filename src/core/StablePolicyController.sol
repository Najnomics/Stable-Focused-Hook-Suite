// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";

import {IStablePolicyController} from "../interfaces/IStablePolicyController.sol";
import {StableTypes} from "../libraries/StableTypes.sol";

contract StablePolicyController is Ownable2Step, IStablePolicyController {
    using PoolIdLibrary for PoolKey;

    error InvalidBandOrdering();
    error InvalidHysteresis();
    error InvalidVolatilityConfig();
    error InvalidSkewConfig();
    error InvalidRegimeConfig();
    error InvalidIncentiveConfig();
    error TimelockEnabled();
    error TimelockDisabled();
    error PolicyNotQueued();
    error PolicyHashMismatch();
    error TimelockNotElapsed();

    uint24 public constant MAX_FEE_PIPS = 1_000_000;
    uint32 public constant MAX_POLICY_TIMELOCK = 30 days;
    uint32 public constant MAX_REGIME_TIME = 7 days;
    uint32 public constant MAX_VOLATILITY_WINDOW = 3 hours;
    uint32 public constant MAX_COOLDOWN_SECONDS = 3 days;

    struct QueuedPolicy {
        bytes32 policyHash;
        uint40 executeAfter;
    }

    mapping(PoolId => StableTypes.Policy) private _policies;
    mapping(PoolId => QueuedPolicy) private _queuedPolicies;

    uint32 public policyTimelockSeconds;

    event PolicyTimelockUpdated(uint32 timelockSeconds);
    event PolicyQueued(PoolId indexed poolId, bytes32 indexed policyHash, uint40 executeAfter);
    event PolicyConfigured(PoolId indexed poolId, uint64 indexed policyNonce, StableTypes.PolicyInput policyInput);

    constructor(address initialOwner, uint32 initialTimelockSeconds) Ownable(initialOwner) {
        if (initialTimelockSeconds > MAX_POLICY_TIMELOCK) revert InvalidRegimeConfig();
        policyTimelockSeconds = initialTimelockSeconds;
    }

    function getPolicy(PoolId poolId) external view returns (StableTypes.Policy memory) {
        return _policies[poolId];
    }

    function getPolicyNonce(PoolId poolId) external view returns (uint64) {
        return _policies[poolId].policyNonce;
    }

    function setPolicyTimelock(uint32 timelockSeconds) external onlyOwner {
        if (timelockSeconds > MAX_POLICY_TIMELOCK) revert InvalidRegimeConfig();
        policyTimelockSeconds = timelockSeconds;
        emit PolicyTimelockUpdated(timelockSeconds);
    }

    function configurePoolPolicy(PoolKey calldata key, StableTypes.PolicyInput calldata policyInput)
        external
        onlyOwner
    {
        if (policyTimelockSeconds != 0) revert TimelockEnabled();
        _applyPolicy(key.toId(), policyInput);
    }

    function queuePolicyUpdate(PoolKey calldata key, StableTypes.PolicyInput calldata policyInput) external onlyOwner {
        if (policyTimelockSeconds == 0) revert TimelockDisabled();

        PoolId poolId = key.toId();
        bytes32 policyHash = keccak256(abi.encode(policyInput));
        uint40 executeAfter = uint40(block.timestamp + policyTimelockSeconds);

        _queuedPolicies[poolId] = QueuedPolicy({policyHash: policyHash, executeAfter: executeAfter});

        emit PolicyQueued(poolId, policyHash, executeAfter);
    }

    function executePolicyUpdate(PoolKey calldata key, StableTypes.PolicyInput calldata policyInput)
        external
        onlyOwner
    {
        if (policyTimelockSeconds == 0) revert TimelockDisabled();

        PoolId poolId = key.toId();
        QueuedPolicy memory queued = _queuedPolicies[poolId];
        if (queued.executeAfter == 0) revert PolicyNotQueued();
        if (queued.policyHash != keccak256(abi.encode(policyInput))) revert PolicyHashMismatch();
        if (block.timestamp < queued.executeAfter) revert TimelockNotElapsed();

        delete _queuedPolicies[poolId];
        _applyPolicy(poolId, policyInput);
    }

    function getQueuedPolicy(PoolId poolId) external view returns (QueuedPolicy memory) {
        return _queuedPolicies[poolId];
    }

    function _applyPolicy(PoolId poolId, StableTypes.PolicyInput calldata policyInput) internal {
        _validatePolicy(policyInput);

        StableTypes.Policy storage policy = _policies[poolId];
        uint64 nextNonce = policy.policyNonce + 1;

        policy.exists = true;
        policy.dynamicFeeEnabled = policyInput.dynamicFeeEnabled;
        policy.pegTick = policyInput.pegTick;
        policy.band1Ticks = policyInput.band1Ticks;
        policy.band2Ticks = policyInput.band2Ticks;
        policy.hysteresisTicks = policyInput.hysteresisTicks;
        policy.minTimeInRegime = policyInput.minTimeInRegime;
        policy.volatilityWindow = policyInput.volatilityWindow;
        policy.softVolatilityThreshold = policyInput.softVolatilityThreshold;
        policy.hardVolatilityThreshold = policyInput.hardVolatilityThreshold;
        policy.softFlowSkewThreshold = policyInput.softFlowSkewThreshold;
        policy.hardFlowSkewThreshold = policyInput.hardFlowSkewThreshold;

        _copyRegime(policy.normal, policyInput.normal);
        _copyRegime(policy.soft, policyInput.soft);
        _copyRegime(policy.hard, policyInput.hard);

        policy.incentives.warmupSeconds = policyInput.incentives.warmupSeconds;
        policy.incentives.cooldownSeconds = policyInput.incentives.cooldownSeconds;
        policy.incentives.cooldownPenaltyBps = policyInput.incentives.cooldownPenaltyBps;
        policy.incentives.emissionRate = policyInput.incentives.emissionRate;

        policy.policyNonce = nextNonce;
        emit PolicyConfigured(poolId, nextNonce, policyInput);
    }

    function _copyRegime(StableTypes.RegimeConfig storage target, StableTypes.RegimeConfig calldata source) internal {
        target.feePips = source.feePips;
        target.maxSwapAmount = source.maxSwapAmount;
        target.maxImpactTicks = source.maxImpactTicks;
        target.cooldownSeconds = source.cooldownSeconds;
    }

    function _validatePolicy(StableTypes.PolicyInput calldata policyInput) internal pure {
        if (policyInput.band1Ticks == 0 || policyInput.band2Ticks <= policyInput.band1Ticks) {
            revert InvalidBandOrdering();
        }
        if (policyInput.hysteresisTicks >= policyInput.band1Ticks) revert InvalidHysteresis();
        if (policyInput.minTimeInRegime > MAX_REGIME_TIME) revert InvalidRegimeConfig();

        if (policyInput.volatilityWindow == 0 || policyInput.volatilityWindow > MAX_VOLATILITY_WINDOW) {
            revert InvalidVolatilityConfig();
        }
        if (
            policyInput.softVolatilityThreshold == 0
                || policyInput.hardVolatilityThreshold < policyInput.softVolatilityThreshold
        ) {
            revert InvalidVolatilityConfig();
        }

        if (
            policyInput.softFlowSkewThreshold <= 0
                || policyInput.hardFlowSkewThreshold < policyInput.softFlowSkewThreshold
        ) {
            revert InvalidSkewConfig();
        }

        _validateRegime(policyInput.normal, false);
        _validateRegime(policyInput.soft, false);
        _validateRegime(policyInput.hard, true);

        if (policyInput.incentives.cooldownPenaltyBps > 10_000) revert InvalidIncentiveConfig();
        if (policyInput.incentives.cooldownSeconds > MAX_COOLDOWN_SECONDS) revert InvalidIncentiveConfig();
    }

    function _validateRegime(StableTypes.RegimeConfig calldata config, bool allowCooldown) internal pure {
        if (config.feePips > MAX_FEE_PIPS || !LPFeeLibrary.isValid(config.feePips)) revert InvalidRegimeConfig();
        if (config.maxSwapAmount == 0 || config.maxImpactTicks == 0) revert InvalidRegimeConfig();
        if (config.cooldownSeconds > MAX_COOLDOWN_SECONDS) revert InvalidRegimeConfig();
        if (!allowCooldown && config.cooldownSeconds != 0) revert InvalidRegimeConfig();
    }
}
