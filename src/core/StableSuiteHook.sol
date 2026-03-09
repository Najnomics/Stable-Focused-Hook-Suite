// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager, SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

import {IStablePolicyController} from "../interfaces/IStablePolicyController.sol";
import {IStickyLiquidityIncentives} from "../interfaces/IStickyLiquidityIncentives.sol";
import {StableTypes} from "../libraries/StableTypes.sol";
import {DynamicFeeModule} from "../modules/DynamicFeeModule.sol";
import {PegGuardrailsModule} from "../modules/PegGuardrailsModule.sol";

contract StableSuiteHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using LPFeeLibrary for uint24;

    error PoolPolicyMissing(PoolId poolId);

    struct RuntimeState {
        bool initialized;
        StableTypes.Regime currentRegime;
        int24 lastObservedTick;
        uint32 smoothedVolatility;
        int64 flowSkew;
        uint40 lastObservationTimestamp;
        uint40 regimeSince;
        uint40 lastHardSwapTimestamp;
        uint64 lastSyncedPolicyNonce;
    }

    struct SwapContext {
        int24 currentTick;
        uint40 timestamp;
        uint32 smoothedVolatility;
        uint24 absTickDistance;
        uint64 absFlowSkew;
        StableTypes.Regime rawRegime;
        StableTypes.Regime effectiveRegime;
        StableTypes.RegimeConfig regimeConfig;
    }

    IStablePolicyController public immutable policyController;
    IStickyLiquidityIncentives public immutable incentives;

    mapping(PoolId => RuntimeState) public runtime;

    event RegimeEvaluated(
        PoolId indexed poolId,
        StableTypes.Regime rawRegime,
        StableTypes.Regime effectiveRegime,
        int24 currentTick,
        uint32 smoothedVolatility,
        int64 flowSkew,
        uint24 feePips,
        uint128 maxSwapAmount,
        uint24 maxImpactTicks,
        bool feeOverridden
    );

    event IncentivesWeightUpdated(PoolId indexed poolId, address indexed account, int256 liquidityDelta);

    constructor(
        IPoolManager poolManager_,
        IStablePolicyController policyController_,
        IStickyLiquidityIncentives incentives_
    ) BaseHook(poolManager_) {
        policyController = policyController_;
        incentives = incentives_;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _beforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4) {
        if (params.liquidityDelta <= 0) {
            return BaseHook.beforeAddLiquidity.selector;
        }

        PoolId poolId = key.toId();
        StableTypes.Policy memory policy = _requirePolicy(poolId);
        _syncIncentivePolicyIfNeeded(poolId, policy);

        if (address(incentives) != address(0)) {
            address account = _resolveLiquidityAccount(sender, hookData);
            uint128 added = uint128(uint256(params.liquidityDelta));
            incentives.onLiquidityAdded(poolId, account, added);
            emit IncentivesWeightUpdated(poolId, account, params.liquidityDelta);
        }

        return BaseHook.beforeAddLiquidity.selector;
    }

    function _beforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4) {
        if (params.liquidityDelta >= 0) {
            return BaseHook.beforeRemoveLiquidity.selector;
        }

        PoolId poolId = key.toId();
        StableTypes.Policy memory policy = _requirePolicy(poolId);
        _syncIncentivePolicyIfNeeded(poolId, policy);

        if (address(incentives) != address(0)) {
            address account = _resolveLiquidityAccount(sender, hookData);
            uint128 removed = _absToUint128(params.liquidityDelta);
            incentives.onLiquidityRemoved(poolId, account, removed);
            emit IncentivesWeightUpdated(poolId, account, params.liquidityDelta);
        }

        return BaseHook.beforeRemoveLiquidity.selector;
    }

    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        PoolId poolId = key.toId();
        StableTypes.Policy memory policy = _requirePolicy(poolId);
        RuntimeState storage state = runtime[poolId];
        SwapContext memory context;
        context.timestamp = uint40(block.timestamp);
        (, context.currentTick,,) = poolManager.getSlot0(poolId);

        context.smoothedVolatility =
            _updateVolatility(state, context.currentTick, policy.volatilityWindow, context.timestamp);
        context.absTickDistance = _absTickDistance(context.currentTick, policy.pegTick);
        context.absFlowSkew = _absFlowSkew(state.flowSkew);
        context.rawRegime = DynamicFeeModule.selectRawRegime(
            context.absTickDistance, context.smoothedVolatility, context.absFlowSkew, policy
        );
        context.effectiveRegime = DynamicFeeModule.applyHysteresis(
            context.rawRegime,
            state.initialized ? state.currentRegime : StableTypes.Regime.NORMAL,
            context.absTickDistance,
            policy,
            state.regimeSince,
            context.timestamp
        );

        if (!state.initialized) {
            state.initialized = true;
            state.regimeSince = context.timestamp;
        }

        if (context.effectiveRegime != state.currentRegime) {
            state.currentRegime = context.effectiveRegime;
            state.regimeSince = context.timestamp;
        }

        context.regimeConfig = DynamicFeeModule.configForRegime(policy, context.effectiveRegime);

        PegGuardrailsModule.enforceSwap(
            params, context.currentTick, context.regimeConfig, state.lastHardSwapTimestamp, context.timestamp
        );

        state.lastObservedTick = context.currentTick;
        state.lastObservationTimestamp = context.timestamp;

        bool feeOverridden = key.fee.isDynamicFee() && policy.dynamicFeeEnabled;
        uint24 feeOverride = feeOverridden ? context.regimeConfig.feePips | LPFeeLibrary.OVERRIDE_FEE_FLAG : 0;

        emit RegimeEvaluated(
            poolId,
            context.rawRegime,
            context.effectiveRegime,
            context.currentTick,
            context.smoothedVolatility,
            state.flowSkew,
            context.regimeConfig.feePips,
            context.regimeConfig.maxSwapAmount,
            context.regimeConfig.maxImpactTicks,
            feeOverridden
        );

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, feeOverride);
    }

    function _afterSwap(address, PoolKey calldata key, SwapParams calldata params, BalanceDelta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        PoolId poolId = key.toId();
        StableTypes.Policy memory policy = _requirePolicy(poolId);

        RuntimeState storage state = runtime[poolId];

        int64 signedFlow = _boundToInt64(_absAmountSpecified(params.amountSpecified));
        if (params.zeroForOne) {
            signedFlow = -signedFlow;
        }

        int64 updatedSkew = state.flowSkew + signedFlow;
        int64 skewBound = _boundToInt64(uint256(uint64(uint256(int256(policy.hardFlowSkewThreshold)))) * 8);
        if (updatedSkew > skewBound) {
            updatedSkew = skewBound;
        }
        if (updatedSkew < -skewBound) {
            updatedSkew = -skewBound;
        }

        // Bounded rolling skew to provide an on-chain imbalance proxy without storing windows.
        state.flowSkew = (updatedSkew * 9) / 10;

        if (state.currentRegime == StableTypes.Regime.HARD_DEPEG) {
            state.lastHardSwapTimestamp = uint40(block.timestamp);
        }

        return (BaseHook.afterSwap.selector, 0);
    }

    function _requirePolicy(PoolId poolId) internal view returns (StableTypes.Policy memory policy) {
        policy = policyController.getPolicy(poolId);
        if (!policy.exists) {
            revert PoolPolicyMissing(poolId);
        }
    }

    function _syncIncentivePolicyIfNeeded(PoolId poolId, StableTypes.Policy memory policy) internal {
        if (address(incentives) == address(0)) {
            return;
        }

        RuntimeState storage state = runtime[poolId];
        if (state.lastSyncedPolicyNonce == policy.policyNonce) {
            return;
        }

        incentives.syncPolicy(poolId, policy.incentives);
        state.lastSyncedPolicyNonce = policy.policyNonce;
    }

    function _updateVolatility(RuntimeState storage state, int24 currentTick, uint32 window, uint40 timestamp)
        internal
        returns (uint32)
    {
        if (!state.initialized || state.lastObservationTimestamp == 0 || window <= 1) {
            state.smoothedVolatility = 0;
            return 0;
        }

        uint24 move = _absTickDistance(currentTick, state.lastObservedTick);
        uint256 weighted = uint256(state.smoothedVolatility) * (window - 1) + move;
        uint32 smoothed = uint32(weighted / window);
        state.smoothedVolatility = smoothed;

        if (timestamp > state.lastObservationTimestamp + window) {
            state.smoothedVolatility = uint32(move);
            smoothed = uint32(move);
        }

        return smoothed;
    }

    function _resolveLiquidityAccount(address sender, bytes calldata hookData) internal pure returns (address account) {
        if (hookData.length == 20) {
            assembly ("memory-safe") {
                account := shr(96, calldataload(hookData.offset))
            }
            return account;
        }

        if (hookData.length >= 32) {
            return abi.decode(hookData, (address));
        }

        return sender;
    }

    function _absTickDistance(int24 a, int24 b) internal pure returns (uint24) {
        int256 delta = int256(a) - int256(b);
        if (delta < 0) {
            delta = -delta;
        }
        return uint24(uint256(delta));
    }

    function _absFlowSkew(int64 skew) internal pure returns (uint64) {
        return uint64(uint256(skew < 0 ? int256(-skew) : int256(skew)));
    }

    function _absAmountSpecified(int256 amountSpecified) internal pure returns (uint256) {
        if (amountSpecified == type(int256).min) {
            return uint256(type(int256).max) + 1;
        }
        return uint256(amountSpecified < 0 ? -amountSpecified : amountSpecified);
    }

    function _boundToInt64(uint256 value) internal pure returns (int64) {
        if (value > uint256(uint64(type(int64).max))) {
            return type(int64).max;
        }
        return int64(uint64(value));
    }

    function _absToUint128(int256 value) internal pure returns (uint128) {
        uint256 abs = value < 0 ? uint256(-value) : uint256(value);
        if (abs > type(uint128).max) {
            return type(uint128).max;
        }
        return uint128(abs);
    }
}
