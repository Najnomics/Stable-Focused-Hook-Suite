#!/usr/bin/env bash
set -euo pipefail
DEMO_ONLY_PHASE=depeg "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/demo-testnet.sh"
