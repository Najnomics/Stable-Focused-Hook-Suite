// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2 as console} from "forge-std/Script.sol";

import {Deployers} from "test/utils/Deployers.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MockStablecoin} from "../src/mocks/MockStablecoin.sol";
import {MockRewardToken} from "../src/mocks/MockRewardToken.sol";
import {StablePolicyController} from "../src/core/StablePolicyController.sol";
import {StableSuiteHook} from "../src/core/StableSuiteHook.sol";
import {RewardsVault} from "../src/incentives/RewardsVault.sol";
import {StickyLiquidityIncentives} from "../src/incentives/StickyLiquidityIncentives.sol";
import {StableTypes} from "../src/libraries/StableTypes.sol";

contract DeployStableSuiteScript is Script, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    MockStablecoin public usdc;
    MockStablecoin public dai;
    MockRewardToken public rewardToken;

    StablePolicyController public controller;
    RewardsVault public vault;
    StickyLiquidityIncentives public incentives;
    StableSuiteHook public hook;

    PoolKey public poolKey;
    PoolId public poolId;

    function run() external {
        deployArtifacts();

        bool deployMocks = vm.envOr("DEPLOY_MOCKS", block.chainid == 31337);

        vm.startBroadcast();

        if (deployMocks) {
            usdc = new MockStablecoin("Mock USDC", "mUSDC", 6);
            dai = new MockStablecoin("Mock DAI", "mDAI", 18);
            rewardToken = new MockRewardToken();

            uint256 usdcMint = vm.envOr("MOCK_USDC_MINT", uint256(1_000_000_000_000_000e6));
            uint256 daiMint = vm.envOr("MOCK_DAI_MINT", uint256(1_000_000_000_000_000e18));
            uint256 rewardMint = vm.envOr("MOCK_REWARD_MINT", uint256(1_000_000_000_000_000e18));

            usdc.mint(msg.sender, usdcMint);
            dai.mint(msg.sender, daiMint);
            rewardToken.mint(msg.sender, rewardMint);
        } else {
            usdc = MockStablecoin(vm.envAddress("TOKEN0"));
            dai = MockStablecoin(vm.envAddress("TOKEN1"));
            rewardToken = MockRewardToken(vm.envAddress("REWARD_TOKEN"));
        }

        controller = new StablePolicyController(msg.sender, uint32(vm.envOr("POLICY_TIMELOCK", uint256(0))));
        vault = new RewardsVault(rewardToken, msg.sender);
        incentives = new StickyLiquidityIncentives(vault, msg.sender);

        uint160 flags = uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG
                | Hooks.AFTER_SWAP_FLAG
        );

        bytes memory constructorArgs = abi.encode(poolManager, controller, incentives);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_FACTORY, flags, type(StableSuiteHook).creationCode, constructorArgs);

        hook = new StableSuiteHook{salt: salt}(poolManager, controller, incentives);
        require(address(hook) == hookAddress, "Hook address mismatch");

        incentives.setHook(address(hook));
        vault.setIncentives(address(incentives));

        (Currency currency0, Currency currency1) = _sortedCurrencies(address(usdc), address(dai));

        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        poolId = poolKey.toId();

        controller.configurePoolPolicy(poolKey, _defaultPolicy());
        incentives.setProgramEnabled(poolId, true);

        poolManager.initialize(poolKey, 2 ** 96);

        _seedLiquidity(poolKey);
        _fundIncentives(deployMocks);

        vm.stopBroadcast();

        _printSummary();
    }

    function _seedLiquidity(PoolKey memory key) internal {
        uint128 liquidity = uint128(vm.envOr("INITIAL_LIQUIDITY", uint256(100e18)));

        int24 tickLower = TickMath.minUsableTick(key.tickSpacing);
        int24 tickUpper = TickMath.maxUsableTick(key.tickSpacing);

        uint160 sqrtPriceX96 = 2 ** 96;

        (uint256 amount0Max, uint256 amount1Max) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96, TickMath.getSqrtPriceAtTick(tickLower), TickMath.getSqrtPriceAtTick(tickUpper), liquidity
        );

        if (!key.currency0.isAddressZero()) {
            address token0 = Currency.unwrap(key.currency0);
            IERC20(token0).approve(address(permit2), type(uint256).max);
            permit2.approve(token0, address(positionManager), type(uint160).max, type(uint48).max);
        }

        if (!key.currency1.isAddressZero()) {
            address token1 = Currency.unwrap(key.currency1);
            IERC20(token1).approve(address(permit2), type(uint256).max);
            permit2.approve(token1, address(positionManager), type(uint160).max, type(uint48).max);
        }

        bytes[] memory params = new bytes[](4);
        params[0] = abi.encode(key, tickLower, tickUpper, liquidity, amount0Max + 1, amount1Max + 1, msg.sender, abi.encode(msg.sender));
        params[1] = abi.encode(key.currency0, key.currency1);
        params[2] = abi.encode(key.currency0, msg.sender);
        params[3] = abi.encode(key.currency1, msg.sender);

        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR), uint8(Actions.SWEEP), uint8(Actions.SWEEP)
        );
        positionManager.modifyLiquidities(abi.encode(actions, params), block.timestamp + 120);
    }

    function _defaultPolicy() internal pure returns (StableTypes.PolicyInput memory policy) {
        policy.dynamicFeeEnabled = true;
        policy.pegTick = 0;
        policy.band1Ticks = 80;
        policy.band2Ticks = 240;
        policy.hysteresisTicks = 20;
        policy.minTimeInRegime = 5 minutes;
        policy.volatilityWindow = 30;
        policy.softVolatilityThreshold = 100;
        policy.hardVolatilityThreshold = 220;
        policy.softFlowSkewThreshold = 100_000;
        policy.hardFlowSkewThreshold = 300_000;

        policy.normal =
            StableTypes.RegimeConfig({feePips: 500, maxSwapAmount: 50e18, maxImpactTicks: 300, cooldownSeconds: 0});
        policy.soft =
            StableTypes.RegimeConfig({feePips: 3_000, maxSwapAmount: 20e18, maxImpactTicks: 180, cooldownSeconds: 0});
        policy.hard =
            StableTypes.RegimeConfig({feePips: 10_000, maxSwapAmount: 5e18, maxImpactTicks: 90, cooldownSeconds: 120});

        policy.incentives = StableTypes.IncentiveConfig({
            warmupSeconds: 15, cooldownSeconds: 180, cooldownPenaltyBps: 2_000, emissionRate: 1e18
        });
    }

    function _fundIncentives(bool deployMocks) internal {
        uint256 defaultFunding = deployMocks ? 50_000e18 : 0;
        uint256 initialFunding = vm.envOr("INITIAL_REWARD_FUND", defaultFunding);
        if (initialFunding == 0) {
            return;
        }

        rewardToken.approve(address(vault), initialFunding);
        incentives.fundProgram(poolId, initialFunding);
    }

    function _sortedCurrencies(address tokenA, address tokenB)
        internal
        pure
        returns (Currency currency0, Currency currency1)
    {
        if (tokenA < tokenB) {
            return (Currency.wrap(tokenA), Currency.wrap(tokenB));
        }
        return (Currency.wrap(tokenB), Currency.wrap(tokenA));
    }

    function _printSummary() internal view {
        console.log("Stable Suite deployment summary");
        console.log("chainId", block.chainid);
        console.log("poolManager", address(poolManager));
        console.log("positionManager", address(positionManager));
        console.log("swapRouter", address(swapRouter));
        console.log("controller", address(controller));
        console.log("vault", address(vault));
        console.log("incentives", address(incentives));
        console.log("hook", address(hook));
        console.log("poolId");
        console.logBytes32(PoolId.unwrap(poolId));
        console.log("token0", Currency.unwrap(poolKey.currency0));
        console.log("token1", Currency.unwrap(poolKey.currency1));
        console.log("rewardToken", address(rewardToken));
    }

    function _etch(address target, bytes memory bytecode) internal override {
        if (block.chainid == 31337) {
            vm.rpc("anvil_setCode", string.concat('["', vm.toString(target), '",', '"', vm.toString(bytecode), '"]'));
        } else {
            revert("Unsupported etch");
        }
    }
}
