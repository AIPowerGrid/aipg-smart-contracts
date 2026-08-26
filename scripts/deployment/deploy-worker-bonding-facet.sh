#!/usr/bin/env bash
# Prepare, execute, or verify the WorkerRegistry bonding facet cut on Base.
# Default mode is read-only. The send path never grants SLASHER_ROLE.
set -euo pipefail

GRID=${GRID:-0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609}
RPC=${RPC:-${BASE_RPC_URL:-https://mainnet.base.org}}
HWFLAG=${HWFLAG:---ledger}
CONFIRM=${CONFIRM:-}
MODE=prepare
ZERO=0x0000000000000000000000000000000000000000
CONTRACT=contracts/grid/modules/WorkerRegistry.sol:WorkerRegistry

SIGNATURES=(
  'cancelUnbond()'
  'getMinBond()'
  'getTotalBonded()'
  'getUnbondInfo(address)'
  'getWorker(address)'
  'getWorkerAt(uint256)'
  'getWorkerCount()'
  'isWorkerActive(address)'
  'isSlashEvidenceUsed(bytes32)'
  'registerWorker(uint256)'
  'setMinBond(uint256)'
  'setUnbondingPeriod(uint256)'
  'slash(address,uint256,bytes32,string)'
  'unbond()'
  'unbondingPeriod()'
  'withdrawBond()'
)

EXPECTED_SELECTORS=(
  0xfe40c4bf
  0x5990dc2b
  0x5c50c356
  0x0c64afb2
  0xc011b1c3
  0x62e6e84d
  0x4d7599f1
  0xc5689dbf
  0xab0e7d53
  0x86796f13
  0x6eaae824
  0x114eaf55
  0x773850c2
  0x5df6a6bc
  0x6cf6d675
  0x66eb9cec
)

usage() {
  cat <<'EOF'
Usage: deploy-worker-bonding-facet.sh [--prepare|--send|--verify]

  --prepare  Compile, test, validate selectors, and inspect the live cut. No write. (default)
  --send     Deploy with Ledger/Trezor, then cut only when the Diamond owner is an EOA.
             If the owner is a Safe/contract, print the reviewed transaction instead.
  --verify   Verify EXPECTED_FACET owns every WorkerRegistry selector after an approved cut.

Environment:
  RPC / BASE_RPC_URL   Base mainnet RPC URL
  GRID                 Grid Diamond address
  HWFLAG               --ledger (default) or --trezor
  CONFIRM=YES          required for --send
  EXPECTED_FACET       required for --verify
  EXPECTED_TOTAL_BONDED  pre-cut decimal getTotalBonded value; required for --verify

This script does not grant SLASHER_ROLE or change bond parameters.
EOF
}

case "${1:-}" in
  ''|--prepare) MODE=prepare ;;
  --send) MODE=send ;;
  --verify) MODE=verify ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

lower() { tr '[:upper:]' '[:lower:]'; }
join_by_comma() { local IFS=,; printf '%s' "$*"; }

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required tool: $1" >&2
    exit 1
  }
}

rpc_read() {
  local attempt output
  for attempt in 1 2 3 4 5; do
    if output=$("$@" 2>&1); then
      printf '%s\n' "$output"
      return 0
    fi
    if (( attempt < 5 )); then
      sleep $((attempt * 2))
    fi
  done
  echo "RPC read failed after $attempt attempts: $*" >&2
  echo "$output" >&2
  return 1
}

for tool in forge cast git python3; do
  require_tool "$tool"
done

if [[ "$HWFLAG" != "--ledger" && "$HWFLAG" != "--trezor" ]]; then
  echo "HWFLAG must be --ledger or --trezor" >&2
  exit 1
fi

CHAIN_ID=$(rpc_read cast chain-id --rpc-url "$RPC")
if [[ "$CHAIN_ID" != "8453" ]]; then
  echo "Refusing non-Base-mainnet chain id: $CHAIN_ID" >&2
  exit 1
fi

GRID_CODE=$(rpc_read cast code "$GRID" --rpc-url "$RPC")
if [[ "$GRID_CODE" == "0x" ]]; then
  echo "No contract code at GRID=$GRID" >&2
  exit 1
fi

echo "Grid:       $GRID"
echo "Chain ID:   $CHAIN_ID"
echo "Mode:       $MODE"

if [[ "$MODE" == "verify" ]]; then
  FACET=${EXPECTED_FACET:-}
  EXPECTED_BONDED=${EXPECTED_TOTAL_BONDED:-}
  if [[ ! "$FACET" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
    echo "EXPECTED_FACET must be a contract address for --verify" >&2
    exit 1
  fi
  if [[ ! "$EXPECTED_BONDED" =~ ^[0-9]+$ ]]; then
    echo "EXPECTED_TOTAL_BONDED must be the pre-cut decimal value for --verify" >&2
    exit 1
  fi
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "--verify requires the clean reviewed source worktree" >&2
    exit 1
  fi

  echo "Building reviewed source for exact runtime verification..."
  forge build
  FACET_CODE=$(rpc_read cast code "$FACET" --rpc-url "$RPC")
  if [[ "$FACET_CODE" == "0x" ]]; then
    echo "No contract code at EXPECTED_FACET=$FACET" >&2
    exit 1
  fi
  EXPECTED_RUNTIME=$(forge inspect "$CONTRACT" deployedBytecode)
  if [[ "$(printf '%s' "$FACET_CODE" | lower)" != "$(printf '%s' "$EXPECTED_RUNTIME" | lower)" ]]; then
    echo "Deployed facet runtime does not match the clean reviewed source" >&2
    exit 1
  fi

  failed=0
  for i in "${!SIGNATURES[@]}"; do
    got=$(rpc_read cast call "$GRID" 'moduleAddress(bytes4)(address)' \
      "${EXPECTED_SELECTORS[$i]}" --rpc-url "$RPC")
    if [[ "$(printf '%s' "$got" | lower)" != "$(printf '%s' "$FACET" | lower)" ]]; then
      printf 'FAIL %-38s %s\n' "${SIGNATURES[$i]}" "$got"
      failed=1
    else
      printf 'OK   %-38s %s\n' "${SIGNATURES[$i]}" "$got"
    fi
    sleep 0.25
  done
  [[ "$failed" == 0 ]] || exit 1
  TOTAL_BONDED_NOW=$(rpc_read cast call "$GRID" 'getTotalBonded()(uint256)' --rpc-url "$RPC")
  TOTAL_BONDED_NOW=${TOTAL_BONDED_NOW%% *}
  if [[ "$TOTAL_BONDED_NOW" != "$EXPECTED_BONDED" ]]; then
    echo "totalBonded changed across the reviewed facet cut" >&2
    echo "before=$EXPECTED_BONDED after=$TOTAL_BONDED_NOW" >&2
    exit 1
  fi
  echo "All WorkerRegistry selectors resolve to $FACET"
  echo "Facet runtime matches commit $(git rev-parse HEAD)"
  echo "totalBonded preserved at $TOTAL_BONDED_NOW"
  exit 0
fi

echo "Running compile and contract tests..."
forge build
forge test

echo "Validating source selectors..."
METHODS_JSON=$(forge inspect "$CONTRACT" methodIdentifiers --json)
for i in "${!SIGNATURES[@]}"; do
  signature=${SIGNATURES[$i]}
  expected=${EXPECTED_SELECTORS[$i]}
  cast_selector=$(cast sig "$signature")
  source_selector=$(METHODS_JSON="$METHODS_JSON" SIGNATURE="$signature" python3 - <<'PY'
import json
import os

methods = json.loads(os.environ["METHODS_JSON"])
selector = methods.get(os.environ["SIGNATURE"])
if selector is None:
    raise SystemExit(1)
print("0x" + selector.removeprefix("0x"))
PY
  )
  if [[ "$cast_selector" != "$expected" || "$source_selector" != "$expected" ]]; then
    echo "Selector mismatch for $signature" >&2
    echo "expected=$expected cast=$cast_selector source=$source_selector" >&2
    exit 1
  fi
done

OWNER=$(rpc_read cast call "$GRID" 'owner()(address)' --rpc-url "$RPC")
TOTAL_BONDED_BEFORE=$(rpc_read cast call "$GRID" 'getTotalBonded()(uint256)' --rpc-url "$RPC")
OLD_FACET=$(rpc_read cast call "$GRID" 'moduleAddress(bytes4)(address)' \
  "$(cast sig 'registerWorker(uint256)')" --rpc-url "$RPC")
if [[ "$(printf '%s' "$OLD_FACET" | lower)" == "$ZERO" ]]; then
  echo "registerWorker(uint256) is not routed; refusing an unexpected deployment state" >&2
  exit 1
fi

REPLACE=()
ADD=()
for i in "${!SIGNATURES[@]}"; do
  selector=${EXPECTED_SELECTORS[$i]}
  current=$(rpc_read cast call "$GRID" 'moduleAddress(bytes4)(address)' "$selector" --rpc-url "$RPC")
  current_lower=$(printf '%s' "$current" | lower)
  if [[ "$current_lower" == "$ZERO" ]]; then
    ADD+=("$selector")
    printf 'ADD     %-38s %s\n' "${SIGNATURES[$i]}" "$selector"
  elif [[ "$current_lower" == "$(printf '%s' "$OLD_FACET" | lower)" ]]; then
    REPLACE+=("$selector")
    printf 'REPLACE %-38s %s\n' "${SIGNATURES[$i]}" "$selector"
  else
    echo "Selector $selector (${SIGNATURES[$i]}) belongs to unexpected facet $current" >&2
    exit 1
  fi
  sleep 0.25
done

echo "Diamond owner:       $OWNER"
echo "Current facet:       $OLD_FACET"
echo "totalBonded snapshot: $TOTAL_BONDED_BEFORE"
echo "Source commit:       $(git rev-parse HEAD)"
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Source state:        DIRTY (development rehearsal only)"
  echo "Source diff hash:    $(git diff --binary HEAD | python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')"
else
  echo "Source state:        clean"
fi
echo "Compiler:            $(forge --version | head -n 1)"
echo "Runtime hash:        $(forge inspect "$CONTRACT" deployedBytecode | cast keccak)"

if [[ "$MODE" == "prepare" ]]; then
  echo
  echo "Preparation complete. No transaction was signed or broadcast."
  echo "Commit the candidate, repeat --prepare from a clean tree, and independently review"
  echo "that exact commit and selector classification before --send."
  exit 0
fi

if [[ "$CONFIRM" != "YES" ]]; then
  echo "--send requires CONFIRM=YES" >&2
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "--send requires a clean worktree, including submodules and untracked files" >&2
  exit 1
fi
# The command is intentionally expanded inside each submodule, not by this shell.
# shellcheck disable=SC2016
git submodule foreach --quiet 'test -z "$(git status --porcelain)"' || {
  echo "--send requires clean submodules" >&2
  exit 1
}

echo "Deploying reviewed WorkerRegistry implementation with $HWFLAG..."
DEPLOY_JSON=$(forge create "$CONTRACT" --rpc-url "$RPC" "$HWFLAG" --broadcast --json)
FACET=$(printf '%s' "$DEPLOY_JSON" | python3 -c \
  'import json,sys; print(json.load(sys.stdin)["deployedTo"])')
FACET_CODE=$(rpc_read cast code "$FACET" --rpc-url "$RPC")
EXPECTED_RUNTIME=$(forge inspect "$CONTRACT" deployedBytecode)
if [[ "$(printf '%s' "$FACET_CODE" | lower)" != "$(printf '%s' "$EXPECTED_RUNTIME" | lower)" ]]; then
  echo "Deployed runtime does not match the reviewed build at $FACET" >&2
  exit 1
fi
echo "Facet deployed and bytecode-verified: $FACET"

CUTS=()
if (( ${#REPLACE[@]} > 0 )); then
  CUTS+=("($FACET,1,[$(join_by_comma "${REPLACE[@]}")])")
fi
if (( ${#ADD[@]} > 0 )); then
  CUTS+=("($FACET,0,[$(join_by_comma "${ADD[@]}")])")
fi
CUT_ARG="[$(join_by_comma "${CUTS[@]}")]"
CALLDATA=$(cast calldata \
  'updateModules((address,uint8,bytes4[])[],address,bytes)' \
  "$CUT_ARG" "$ZERO" 0x)

OWNER_CODE=$(rpc_read cast code "$OWNER" --rpc-url "$RPC")
if [[ "$OWNER_CODE" != "0x" ]]; then
  echo
  echo "Diamond owner is a contract (for example, a Safe). No cut was broadcast."
  echo "Submit and independently review this owner transaction:"
  echo "  target: $GRID"
  echo "  value:  0"
  echo "  data:   $CALLDATA"
  echo "After execution, run:"
  VERIFY_BONDED=${TOTAL_BONDED_BEFORE%% *}
  echo "  EXPECTED_FACET=$FACET EXPECTED_TOTAL_BONDED=$VERIFY_BONDED $0 --verify"
  exit 0
fi

echo "Broadcasting owner cut with $HWFLAG..."
cast send "$GRID" \
  'updateModules((address,uint8,bytes4[])[],address,bytes)' \
  "$CUT_ARG" "$ZERO" 0x --rpc-url "$RPC" "$HWFLAG"

failed=0
for selector in "${EXPECTED_SELECTORS[@]}"; do
  got=$(rpc_read cast call "$GRID" 'moduleAddress(bytes4)(address)' "$selector" --rpc-url "$RPC")
  if [[ "$(printf '%s' "$got" | lower)" != "$(printf '%s' "$FACET" | lower)" ]]; then
    echo "Post-cut selector verification failed: $selector -> $got" >&2
    failed=1
  fi
  sleep 0.25
done
TOTAL_BONDED_AFTER=$(rpc_read cast call "$GRID" 'getTotalBonded()(uint256)' --rpc-url "$RPC")
if [[ "$TOTAL_BONDED_AFTER" != "$TOTAL_BONDED_BEFORE" ]]; then
  echo "totalBonded changed across the facet cut" >&2
  echo "before=$TOTAL_BONDED_BEFORE after=$TOTAL_BONDED_AFTER" >&2
  failed=1
fi
[[ "$failed" == 0 ]] || exit 1

echo "WorkerRegistry cut verified at $FACET"
echo "SLASHER_ROLE remains ungranted; do not enable automated slashing."
