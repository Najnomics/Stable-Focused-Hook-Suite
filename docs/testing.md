# Testing

Test suite includes:

- Unit tests: controller, hook, incentives
- Edge tests: band boundaries, cooldown boundaries, unauthorized paths
- Fuzz tests: regime determinism, band ordering, reward-funding invariant
- Integration test: normal lifecycle + depeg stress path

Run:

```bash
make test
make fuzz
make coverage
```
