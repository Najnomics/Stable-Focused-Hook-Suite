SHELL := /bin/bash

.PHONY: bootstrap build test fuzz coverage lint verify-deps verify-commits demo-local demo-testnet demo-normal demo-depeg demo-incentives demo-all ci-check

bootstrap:
	./scripts/bootstrap.sh

build:
	forge build

test:
	forge test -vv

fuzz:
	forge test --match-path test/fuzz/* -vv

coverage:
	forge coverage

lint:
	forge fmt --check

verify-deps:
	./scripts/bootstrap.sh

verify-commits:
	./scripts/verify_commits.sh

demo-local:
	./scripts/demo-local.sh

demo-testnet:
	./scripts/demo-testnet.sh

demo-normal:
	./scripts/demo-normal.sh

demo-depeg:
	./scripts/demo-depeg.sh

demo-incentives:
	./scripts/demo-incentives.sh

demo-all:
	./scripts/demo-all.sh

ci-check: verify-deps build test coverage
