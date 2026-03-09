// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

import {StableTypes} from "../libraries/StableTypes.sol";
import {IRewardsVault} from "../interfaces/IRewardsVault.sol";
import {IStickyLiquidityIncentives} from "../interfaces/IStickyLiquidityIncentives.sol";

contract StickyLiquidityIncentives is Ownable2Step, ReentrancyGuard, IStickyLiquidityIncentives {
    error NotHook();
    error NotOwnerOrHook();
    error InsufficientWeight();

    uint256 private constant ACC_PRECISION = 1e18;

    struct ProgramState {
        bool enabled;
        uint32 warmupSeconds;
        uint32 cooldownSeconds;
        uint16 cooldownPenaltyBps;
        uint128 emissionRate;
        uint128 totalActiveWeight;
        uint128 totalPendingWeight;
        uint40 lastAccrualTimestamp;
        uint256 accRewardPerWeightX18;
        uint256 rewardBudget;
        uint256 totalFunded;
        uint256 totalClaimed;
        uint256 penaltyRetained;
    }

    struct UserState {
        uint128 activeWeight;
        uint128 pendingWeight;
        uint256 accrued;
        uint256 rewardDebt;
        uint40 pendingActivationTime;
        uint40 lastAddTimestamp;
        uint40 lastRemoveTimestamp;
        uint40 penaltyEndsAt;
    }

    IRewardsVault public immutable rewardsVault;
    address public hook;

    mapping(PoolId => ProgramState) private _programs;
    mapping(PoolId => mapping(address => UserState)) private _users;

    event HookSet(address indexed hook);
    event ProgramSynced(PoolId indexed poolId, StableTypes.IncentiveConfig config);
    event ProgramEnabled(PoolId indexed poolId, bool enabled);
    event ProgramFunded(PoolId indexed poolId, address indexed sponsor, uint256 amount);
    event WeightAdded(PoolId indexed poolId, address indexed account, uint128 liquidityDelta);
    event WeightRemoved(PoolId indexed poolId, address indexed account, uint128 liquidityDelta);
    event RewardsClaimed(
        PoolId indexed poolId, address indexed account, address indexed to, uint256 amount, uint256 penalty
    );

    constructor(IRewardsVault rewardsVault_, address initialOwner) Ownable(initialOwner) {
        rewardsVault = rewardsVault_;
    }

    modifier onlyHook() {
        if (msg.sender != hook) revert NotHook();
        _;
    }

    modifier onlyOwnerOrHook() {
        if (msg.sender != owner() && msg.sender != hook) revert NotOwnerOrHook();
        _;
    }

    function setHook(address hook_) external onlyOwner {
        hook = hook_;
        emit HookSet(hook_);
    }

    function setProgramEnabled(PoolId poolId, bool enabled) external onlyOwner {
        ProgramState storage program = _programs[poolId];
        if (program.lastAccrualTimestamp == 0) {
            program.lastAccrualTimestamp = uint40(block.timestamp);
        }

        program.enabled = enabled;
        emit ProgramEnabled(poolId, enabled);
    }

    function syncPolicy(PoolId poolId, StableTypes.IncentiveConfig calldata config) external onlyOwnerOrHook {
        ProgramState storage program = _programs[poolId];
        _accrue(poolId, program);

        program.warmupSeconds = config.warmupSeconds;
        program.cooldownSeconds = config.cooldownSeconds;
        program.cooldownPenaltyBps = config.cooldownPenaltyBps;
        program.emissionRate = config.emissionRate;

        emit ProgramSynced(poolId, config);
    }

    function fundProgram(PoolId poolId, uint256 amount) external nonReentrant {
        ProgramState storage program = _programs[poolId];
        _accrue(poolId, program);

        rewardsVault.fundFrom(msg.sender, amount);

        program.totalFunded += amount;
        program.rewardBudget += amount;
        emit ProgramFunded(poolId, msg.sender, amount);
    }

    function onLiquidityAdded(PoolId poolId, address account, uint128 liquidityDelta) external onlyHook {
        if (liquidityDelta == 0) {
            return;
        }

        ProgramState storage program = _programs[poolId];
        _accrue(poolId, program);

        UserState storage user = _users[poolId][account];
        _activatePendingIfMature(program, user);
        _checkpointUser(program, user);

        user.pendingWeight += liquidityDelta;
        program.totalPendingWeight += liquidityDelta;

        uint40 activationTime = uint40(block.timestamp + program.warmupSeconds);
        if (activationTime > user.pendingActivationTime) {
            user.pendingActivationTime = activationTime;
        }

        user.lastAddTimestamp = uint40(block.timestamp);
        emit WeightAdded(poolId, account, liquidityDelta);
    }

    function onLiquidityRemoved(PoolId poolId, address account, uint128 liquidityDelta) external onlyHook {
        if (liquidityDelta == 0) {
            return;
        }

        ProgramState storage program = _programs[poolId];
        _accrue(poolId, program);

        UserState storage user = _users[poolId][account];
        _activatePendingIfMature(program, user);
        _checkpointUser(program, user);

        uint128 remaining = liquidityDelta;

        if (user.pendingWeight != 0) {
            uint128 consumedPending = remaining > user.pendingWeight ? user.pendingWeight : remaining;
            user.pendingWeight -= consumedPending;
            program.totalPendingWeight -= consumedPending;
            remaining -= consumedPending;

            if (user.pendingWeight == 0) {
                user.pendingActivationTime = 0;
            }
        }

        if (remaining != 0) {
            if (remaining > user.activeWeight) revert InsufficientWeight();
            user.activeWeight -= remaining;
            program.totalActiveWeight -= remaining;
        }

        if (
            program.cooldownSeconds != 0 && user.lastAddTimestamp != 0
                && block.timestamp < user.lastAddTimestamp + program.cooldownSeconds
        ) {
            uint40 penaltyEndsAt = uint40(block.timestamp + program.cooldownSeconds);
            if (penaltyEndsAt > user.penaltyEndsAt) {
                user.penaltyEndsAt = penaltyEndsAt;
            }
        }

        user.lastRemoveTimestamp = uint40(block.timestamp);
        user.rewardDebt = (uint256(user.activeWeight) * program.accRewardPerWeightX18) / ACC_PRECISION;

        emit WeightRemoved(poolId, account, liquidityDelta);
    }

    function claim(PoolId poolId, address to)
        external
        nonReentrant
        returns (uint256 claimedAmount, uint256 penaltyAmount)
    {
        ProgramState storage program = _programs[poolId];
        _accrue(poolId, program);

        UserState storage user = _users[poolId][msg.sender];
        _activatePendingIfMature(program, user);
        _checkpointUser(program, user);

        uint256 gross = user.accrued;
        if (gross == 0) {
            return (0, 0);
        }

        user.accrued = 0;

        if (block.timestamp < user.penaltyEndsAt && program.cooldownPenaltyBps != 0) {
            penaltyAmount = (gross * program.cooldownPenaltyBps) / 10_000;
            program.penaltyRetained += penaltyAmount;
            program.rewardBudget += penaltyAmount;
            gross -= penaltyAmount;
        }

        claimedAmount = gross;
        if (claimedAmount != 0) {
            program.totalClaimed += claimedAmount;
            rewardsVault.disburse(to, claimedAmount);
        }

        emit RewardsClaimed(poolId, msg.sender, to, claimedAmount, penaltyAmount);
    }

    function claimable(PoolId poolId, address account) external view returns (uint256 amount, uint256 penalty) {
        ProgramState memory program = _programs[poolId];
        UserState memory user = _users[poolId][account];

        if (program.lastAccrualTimestamp == 0) {
            return (0, 0);
        }

        program = _previewAccrual(program);

        if (user.pendingWeight != 0 && block.timestamp >= user.pendingActivationTime) {
            user.activeWeight += user.pendingWeight;
            user.pendingWeight = 0;
            user.pendingActivationTime = 0;
        }

        uint256 accumulated = (uint256(user.activeWeight) * program.accRewardPerWeightX18) / ACC_PRECISION;
        uint256 pending = accumulated > user.rewardDebt ? accumulated - user.rewardDebt : 0;

        uint256 gross = user.accrued + pending;
        if (gross == 0) {
            return (0, 0);
        }

        if (block.timestamp < user.penaltyEndsAt && program.cooldownPenaltyBps != 0) {
            penalty = (gross * program.cooldownPenaltyBps) / 10_000;
            amount = gross - penalty;
        } else {
            amount = gross;
        }
    }

    function getProgram(PoolId poolId) external view returns (ProgramState memory) {
        return _programs[poolId];
    }

    function getUserState(PoolId poolId, address account) external view returns (UserState memory) {
        return _users[poolId][account];
    }

    function _accrue(PoolId, ProgramState storage program) internal {
        uint40 timestamp = uint40(block.timestamp);

        if (program.lastAccrualTimestamp == 0) {
            program.lastAccrualTimestamp = timestamp;
            return;
        }

        uint40 elapsed = timestamp - program.lastAccrualTimestamp;
        if (elapsed == 0) {
            return;
        }

        if (
            !program.enabled || program.totalActiveWeight == 0 || program.emissionRate == 0 || program.rewardBudget == 0
        ) {
            program.lastAccrualTimestamp = timestamp;
            return;
        }

        uint256 grossAccrual = uint256(elapsed) * uint256(program.emissionRate);
        uint256 distributed = grossAccrual > program.rewardBudget ? program.rewardBudget : grossAccrual;

        if (distributed != 0) {
            program.accRewardPerWeightX18 += (distributed * ACC_PRECISION) / program.totalActiveWeight;
            program.rewardBudget -= distributed;
        }

        program.lastAccrualTimestamp = timestamp;
    }

    function _previewAccrual(ProgramState memory program) internal view returns (ProgramState memory) {
        uint40 timestamp = uint40(block.timestamp);

        if (
            !program.enabled || program.totalActiveWeight == 0 || program.emissionRate == 0 || program.rewardBudget == 0
                || timestamp <= program.lastAccrualTimestamp
        ) {
            return program;
        }

        uint40 elapsed = timestamp - program.lastAccrualTimestamp;
        uint256 grossAccrual = uint256(elapsed) * uint256(program.emissionRate);
        uint256 distributed = grossAccrual > program.rewardBudget ? program.rewardBudget : grossAccrual;

        if (distributed != 0) {
            program.accRewardPerWeightX18 += (distributed * ACC_PRECISION) / program.totalActiveWeight;
        }

        return program;
    }

    function _activatePendingIfMature(ProgramState storage program, UserState storage user) internal {
        if (user.pendingWeight == 0 || block.timestamp < user.pendingActivationTime) {
            return;
        }

        uint128 activated = user.pendingWeight;
        user.pendingWeight = 0;
        user.pendingActivationTime = 0;

        user.activeWeight += activated;
        program.totalPendingWeight -= activated;
        program.totalActiveWeight += activated;
    }

    function _checkpointUser(ProgramState storage program, UserState storage user) internal {
        uint256 accumulated = (uint256(user.activeWeight) * program.accRewardPerWeightX18) / ACC_PRECISION;
        if (accumulated > user.rewardDebt) {
            user.accrued += accumulated - user.rewardDebt;
        }
        user.rewardDebt = accumulated;
    }
}
