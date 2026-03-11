# Deployment

## Dependency Pinning

```bash
make bootstrap
```

This enforces Uniswap v4 periphery pin `3779387e5d296f39df543d23524b050f89a62917`.

## Environment

Populate `.env` with Unichain Sepolia RPC + signer keys. Reactive variables are intentionally omitted because Reactive is not integrated.

## Local

```bash
make demo-local
```

## Unichain Sepolia

```bash
make demo-testnet
```

`demo-testnet` will:

- deploy contracts if addresses are missing in `.env`
- persist deployed addresses back into `.env`
- run normal/depeg/incentives demo phases
- print tx hashes and explorer URLs
