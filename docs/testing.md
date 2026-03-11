# Testing

## Categories

- unit tests
- edge/boundary tests
- fuzz tests
- integration lifecycle tests
- economic correctness tests

## Commands

```bash
make test
make fuzz
make coverage
```

`make coverage` runs `scripts/check_coverage.sh`, which enforces `100%` lines/statements/branches/functions across `src/*` contracts.
