# Deployment

## Bootstrap and Pinning

```bash
make bootstrap
```

This script initializes submodules and pins Uniswap v4 periphery to commit `3779387e5d296f39df543d23524b050f89a62917`.

## Local Deployment

```bash
make demo-local
```

## Testnet Deployment

```bash
RPC_URL=<rpc> PRIVATE_KEY=<pk> TOKEN0=<addr> TOKEN1=<addr> REWARD_TOKEN=<addr> make demo-testnet
```

Base Sepolia references are included in docs and script outputs.
