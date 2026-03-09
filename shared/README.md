# Shared Artifacts

`/shared` contains contract interfaces consumed by scripts/frontend:

- `abis/*.abi.json`: canonical ABI exports from Foundry artifacts
- `types/contracts.ts`: lightweight shared TypeScript types

Regenerate after contract changes:

```bash
./scripts/export-abis.sh
```
