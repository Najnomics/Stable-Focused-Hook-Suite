# Contributing

## Development Setup

```bash
make bootstrap
make test
```

## Workflow

1. Open an issue describing scope and threat model impact.
2. Create a branch with focused changes.
3. Add or update tests for behavioral/security changes.
4. Run `make ci-check` before submitting PR.

## Standards

- Keep logic deterministic and on-chain.
- Avoid offchain dependencies for regime correctness.
- Preserve O(1) reward accounting paths.
- Add clear docs for any policy or trust-model changes.

## Commit Style

Use conventional commit prefixes:

- `feat:`
- `fix:`
- `test:`
- `docs:`
- `chore:`

## Pull Request Requirements

- Describe behavior and threat-model impact.
- Include tests and expected outputs.
- Note migration/deployment implications.
