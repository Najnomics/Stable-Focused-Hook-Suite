# Demo Guide

## Goal

Demonstrate the full stablecoin lifecycle from owner + user perspective with deterministic on-chain evidence:

- deploy/reuse suite contracts
- run normal-peg swap flow
- trigger depeg regime policy and show cooldown state
- claim sticky-liquidity rewards
- print every transaction hash with explorer URL

## One-Command Testnet Demo

Run:

```bash
make demo-testnet
```

## Workflow and Phases

| Phase | Actor | What happens | On-chain proof printed by script |
|---|---|---|---|
| 1. Deploy/Reuse | Owner | Deploy contracts or reuse addresses from `.env`; compute `POOL_ID` | deploy tx URLs (if deployed), deployed addresses, poolId |
| 2. Normal Peg | User | Approve tokens and execute normal swap | `approve token0`, `approve token1`, `swap normal` tx URLs |
| 3. Depeg Stress | Owner + User | Owner applies stress policy; script checks hard cooldown state and reports enforcement | policy update tx URL + cooldown projection (`lastHardSwapTimestamp`, `cooldownEndsAt`, `cooldownActive`) |
| 4. Warmup | System | Wait for warm-up to pass before claim | warm-up wait log |
| 5. Incentives | User | Query `claimable` then claim rewards through incentives + vault | claim tx URL + funded/claimed accounting |

## User Perspective Flow

1. Open frontend and connect wallet.
2. Owner runs `make demo-testnet` (or individual phase commands).
3. User performs normal swap and sees NORMAL regime behavior.
4. Owner enables stress policy; user observes hard-regime cooldown projection.
5. User claims rewards after warm-up; script prints claim tx URL and updated totals.

## Phase-Only Runs (Reuse Existing Deployment)

```bash
make demo-normal
make demo-depeg
make demo-incentives
```

## Explorer URL Pattern

Unichain Sepolia:

`https://sepolia.uniscan.xyz/tx/<TX_HASH>`

## Latest End-to-End Evidence (March 10, 2026)

- normal approve token0: `0x0b7b722c669a3d5e8cd4419f5365c0f4d11b184a62117559b4916fbc6f4b5742`
- normal approve token1: `0x2c9aa087d43c6b743d993ad82ea105c15ca1d266729a569367b3d733406d7b60`
- normal swap: `0x452eaaf98d65f4e831c8f1a1524b6223adfc51e2e32abf8489c5345d145535a9`
- depeg policy update: `0xb35555f819b3404fc0b9bfb86e8d50d8814035d289dfd51b5de31c1e0c66376d`
- incentives claim: `0xb6ab85cfdfe1c324ee466e83de729ca39984cc406ed5d116bcb50c0e587dbc7b`

## Useful Targets

- `make demo-local`
- `make demo-normal`
- `make demo-depeg`
- `make demo-incentives`
- `make demo-all`

`make demo-normal`, `make demo-depeg`, and `make demo-incentives` are wrappers over `scripts/demo-testnet.sh` using `DEMO_ONLY_PHASE`.
