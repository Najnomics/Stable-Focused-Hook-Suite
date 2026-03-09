# Security Policy

## Scope

This repository contains smart contracts and scripts for stablecoin-focused Uniswap v4 hooks.

Primary contracts in scope:

- `src/core/StableSuiteHook.sol`
- `src/core/StablePolicyController.sol`
- `src/incentives/StickyLiquidityIncentives.sol`
- `src/incentives/RewardsVault.sol`

## Reporting

Please report vulnerabilities privately before disclosure:

- Email: `jesuorobonosakhare873@gmail.com`
- Subject: `Stable Suite Security Report`

Include:

- impact summary
- reproduction steps
- affected files/functions
- suggested fix (if available)

## Threat Model Highlights

- PoolManager trust assumption
- governance/admin misconfiguration risk
- stress-regime transition manipulation attempts
- reward accounting precision and edge behavior

## Safe Deployment Checklist

1. Run `make bootstrap`
2. Run `make test` and `make coverage`
3. Validate policy ranges before mainnet
4. Validate hook permission bits/address match
5. Dry-run demo scripts on an isolated testnet deployment

## Disclaimer

No system is attack-proof. Residual risk remains and should be managed with staged rollouts, audits, and operational controls.
