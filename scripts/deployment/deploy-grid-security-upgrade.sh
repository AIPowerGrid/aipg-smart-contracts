#!/usr/bin/env bash
# Deploy the Grid security upgrade as one operator path:
#   1. PaymentRouter: total reward cap + per-period cap.
#   2. WorkerRegistry: unbond cooldown + slashing + dust-safe below-min slash.
#
# The script deploys only the changed facets, classifies each selector as ADD or
# REPLACE against the live diamond, applies one atomic updateModules cut, then
# verifies every selector routes to the newly deployed implementation.
#
# Usage:
#   CONFIRM=YES RPC=https://mainnet.base.org HWFLAG=--ledger \
#     ./scripts/deployment/deploy-grid-security-upgrade.sh
#
# Optional:
#   SKIP_TESTS=1    skip the local offline Foundry suite
#   OWNER_EXPECTED override the expected Grid owner/admin address
set -euo pipefail

GRID=${GRID:-0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609}
RPC=${RPC:-https://mainnet.base.org}
HWFLAG=${HWFLAG:---ledger}
OWNER_EXPECTED=${OWNER_EXPECTED:-0xA218db26ed545f3476e6c3E827b595cf2E182533}
ZERO=0x0000000000000000000000000000000000000000

# Selectors verified with:
#   forge inspect contracts/grid/modules/PaymentRouter.sol:PaymentRouter methodIdentifiers --offline
PAYMENT_SELECTORS=(
  0x172bd6de  # claim(address,uint256,uint256,bytes32[])
  0x0d1fd3f4  # claimBatch(uint256,address[],uint256[],bytes32[][])
  0xd2ef0795  # isClaimed(uint256,address)
  0xa6fe1660  # previewClaim(uint256,address,uint256,bytes32[])
)

# Selectors verified with:
#   forge inspect contracts/grid/modules/WorkerRegistry.sol:WorkerRegistry methodIdentifiers --offline
WORKER_SELECTORS=(
  0x86796f13  # registerWorker(uint256)
  0x5df6a6bc  # unbond()
  0xc011b1c3  # getWorker(address)
  0xc5689dbf  # isWorkerActive(address)
  0x5c50c356  # getTotalBonded()
  0x5990dc2b  # getMinBond()
  0x678b3ee2  # slash(address,uint256,string)
  0x66eb9cec  # withdrawBond()
  0xfe40c4bf  # cancelUnbond()
  0x114eaf55  # setUnbondingPeriod(uint256)
  0x6cf6d675  # unbondingPeriod()
  0x0c64afb2  # getUnbondInfo(address)
  0x6eaae824  # setMinBond(uint256)
)

lower() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

join() {
  local IFS=,
  echo "$*"
}

rpc_call() {
  local to=$1
  local data=$2

  curl -fsS \
    -H 'Content-Type: application/json' \
    --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_call\",\"params\":[{\"to\":\"$to\",\"data\":\"$data\"},\"latest\"]}" \
    "$RPC" \
    | python3 -c 'import json,sys
r=json.load(sys.stdin)
if "error" in r:
    raise SystemExit(r["error"])
print(r["result"])'
}

word_to_address() {
  local word=${1#0x}
  echo "0x${word: -40}"
}

owner() {
  word_to_address "$(rpc_call "$GRID" 0x8da5cb5b)"
}

module_address() {
  local selector=${1#0x}
  local zeros=00000000000000000000000000000000000000000000000000000000
  word_to_address "$(rpc_call "$GRID" "0xb763dde2${selector}${zeros}")"
}

classify_selectors() {
  local label=$1
  local add_name=$2
  local replace_name=$3
  shift 3

  local selector
  local current
  for selector in "$@"; do
    current=$(module_address "$selector")
    if [ "$(lower "$current")" = "$ZERO" ]; then
      eval "$add_name+=(\"\$selector\")"
      echo "   $label ADD     $selector"
    else
      eval "$replace_name+=(\"\$selector\")"
      echo "   $label REPLACE $selector (was $current)"
    fi
  done
}

deploy_facet() {
  local name=$1
  forge create "contracts/grid/modules/$name.sol:$name" \
    --rpc-url "$RPC" $HWFLAG --broadcast --json \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["deployedTo"])'
}

append_cut() {
  local facet=$1
  local action=$2
  shift 2
  if [ "$#" -gt 0 ]; then
    CUTS+=("($facet,$action,[$(join "$@")])")
  fi
}

verify_routes() {
  local label=$1
  local facet=$2
  shift 2

  local ok=1
  local selector
  local got
  for selector in "$@"; do
    got=$(module_address "$selector")
    if [ "$(lower "$got")" = "$(lower "$facet")" ]; then
      echo "   OK   $label $selector -> $got"
    else
      echo "   FAIL $label $selector -> $got (expected $facet)"
      ok=0
    fi
  done
  [ "$ok" = 1 ]
}

echo "Grid: $GRID"
echo "RPC:  $RPC"
echo

if [ "${SKIP_TESTS:-0}" != "1" ]; then
  echo "1) Run offline test suite..."
  forge test --offline -vv
else
  echo "1) SKIP_TESTS=1, not running local tests."
fi

echo "2) Preflight owner and selector classification..."
LIVE_OWNER=$(owner)
if [ "$(lower "$LIVE_OWNER")" != "$(lower "$OWNER_EXPECTED")" ]; then
  echo "Owner mismatch: live=$LIVE_OWNER expected=$OWNER_EXPECTED"
  exit 1
fi
echo "   owner OK: $LIVE_OWNER"

PR_ADD=()
PR_REPLACE=()
WR_ADD=()
WR_REPLACE=()
classify_selectors PaymentRouter PR_ADD PR_REPLACE "${PAYMENT_SELECTORS[@]}"
classify_selectors WorkerRegistry WR_ADD WR_REPLACE "${WORKER_SELECTORS[@]}"

if [ "${CONFIRM:-}" != "YES" ]; then
  echo
  echo "Preflight complete. No transactions sent."
  echo "Set CONFIRM=YES to deploy facets and apply the diamond cut."
  exit 1
fi

echo "3) Deploy changed facets..."
PAYMENT_FACET=$(deploy_facet PaymentRouter)
echo "   PaymentRouter:  $PAYMENT_FACET"
WORKER_FACET=$(deploy_facet WorkerRegistry)
echo "   WorkerRegistry: $WORKER_FACET"

CUTS=()
append_cut "$PAYMENT_FACET" 1 "${PR_REPLACE[@]}"
append_cut "$PAYMENT_FACET" 0 "${PR_ADD[@]}"
append_cut "$WORKER_FACET" 1 "${WR_REPLACE[@]}"
append_cut "$WORKER_FACET" 0 "${WR_ADD[@]}"
CUT_ARG="[$(join "${CUTS[@]}")]"

echo "4) updateModules with atomic cut:"
echo "   $CUT_ARG"
cast send "$GRID" \
  "updateModules((address,uint8,bytes4[])[],address,bytes)" \
  "$CUT_ARG" \
  "$ZERO" \
  0x \
  --rpc-url "$RPC" $HWFLAG

echo "5) Verify selector routing..."
verify_routes PaymentRouter "$PAYMENT_FACET" "${PAYMENT_SELECTORS[@]}"
verify_routes WorkerRegistry "$WORKER_FACET" "${WORKER_SELECTORS[@]}"

echo
echo "Done. Next: grant SLASHER_ROLE to the enforcement key if not already set:"
echo "  cast send $GRID 'grantRole(bytes32,address)' \\"
echo "    \$(cast keccak 'SLASHER_ROLE') <enforcer-address> --rpc-url $RPC $HWFLAG"
