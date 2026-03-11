#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

load_dotenv() {
  local env_file="${1:-$ROOT_DIR/.env}"
  if [[ -f "$env_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a
  fi
}

require_var() {
  local key="$1"
  if [[ -z "${!key:-}" ]]; then
    echo "[env] missing required variable: $key" >&2
    exit 1
  fi
}

explorer_tx_prefix_for_chain() {
  local chain_id="$1"
  case "$chain_id" in
    1301) echo "https://sepolia.uniscan.xyz/tx/" ;;
    84532) echo "https://sepolia.basescan.org/tx/" ;;
    11155111) echo "https://sepolia.etherscan.io/tx/" ;;
    31337) echo "TBD" ;;
    *) echo "TBD" ;;
  esac
}

print_tx_urls_from_run_file() {
  local title="$1"
  local run_file="$2"
  local tx_prefix="$3"

  if [[ ! -f "$run_file" ]]; then
    echo "[$title] run file not found: $run_file" >&2
    return 1
  fi

  echo "[$title] transactions"
  jq -r '.transactions[] | [.hash // "", .transactionType // "tx", .contractName // "call"] | @tsv' "$run_file" | while IFS=$'\t' read -r hash tx_type contract; do
    if [[ -z "$hash" ]]; then
      continue
    fi
    if [[ "$tx_prefix" == "TBD" ]]; then
      echo "  - ${tx_type} ${contract}: ${hash} | explorer: TBD"
    else
      echo "  - ${tx_type} ${contract}: ${hash} | explorer: ${tx_prefix}${hash}"
    fi
  done
}

extract_deploy_value() {
  local run_file="$1"
  local contract_name="$2"
  jq -r --arg n "$contract_name" '.transactions[] | select(.contractName == $n) | .contractAddress // empty' "$run_file" | tail -n 1
}

upsert_env_var() {
  local env_file="$1"
  local key="$2"
  local value="$3"
  local tmp_file

  tmp_file="$(mktemp)"

  if [[ -f "$env_file" ]]; then
    awk -v k="$key" -v v="$value" '
      BEGIN { updated = 0 }
      {
        if ($0 ~ "^" k "=") {
          print k "=" v
          updated = 1
        } else {
          print $0
        }
      }
      END {
        if (!updated) {
          print k "=" v
        }
      }
    ' "$env_file" > "$tmp_file"
  else
    printf '%s=%s\n' "$key" "$value" > "$tmp_file"
  fi

  mv "$tmp_file" "$env_file"
}

print_demo_phase() {
  local phase="$1"
  local detail="$2"
  echo
  echo "========== ${phase} =========="
  echo "$detail"
}

require_contract_deployed() {
  local rpc_url="$1"
  local address="$2"
  local label="$3"

  if [[ -z "$address" ]]; then
    return 1
  fi

  local code
  code="$(cast code "$address" --rpc-url "$rpc_url" 2>/dev/null || true)"
  if [[ -z "$code" || "$code" == "0x" ]]; then
    echo "[deploy-check] ${label} has no code at ${address}" >&2
    return 1
  fi

  return 0
}
