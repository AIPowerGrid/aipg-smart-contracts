#!/usr/bin/env bash
# Prepare, execute, or verify the bond-reserve RewardPool/PaymentRouter cut.
# Default mode is read-only. DenReporter is intentionally left untouched.
set -euo pipefail

GRID=${GRID:-0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609}
AIPG=${AIPG:-0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608}
RPC=${RPC:-${BASE_RPC_URL:-https://mainnet.base.org}}
HWFLAG=${HWFLAG:---ledger}
CONFIRM=${CONFIRM:-}
MODE=prepare
ZERO=0x0000000000000000000000000000000000000000
RP_CONTRACT=contracts/grid/modules/RewardPool.sol:RewardPool
PR_CONTRACT=contracts/grid/modules/PaymentRouter.sol:PaymentRouter

RP_SIGNATURES=(
  'depositRewards(uint256)'
  'setPeriodAllocation(uint256,string)'
  'setPeriodLength(uint256)'
  'poolBalance()'
  'totalDeposited()'
  'totalPaidOut()'
  'periodAllocation()'
  'currentPeriodId()'
  'periodLengthSeconds()'
)
RP_SELECTORS=(
  0x8bdf67f2
  0x740995a7
  0x1c5633d7
  0x96365d44
  0xff50abdc
  0x1357e1dc
  0xfe9e071f
  0x988e6595
  0x6b936a4c
)
PR_SIGNATURES=(
  'claim(address,uint256,uint256,bytes32[])'
  'claimBatch(uint256,address[],uint256[],bytes32[][])'
  'previewClaim(uint256,address,uint256,bytes32[])'
  'isClaimed(uint256,address)'
)
PR_SELECTORS=(
  0x172bd6de
  0x0d1fd3f4
  0xa6fe1660
  0xd2ef0795
)

usage() {
  cat <<'EOF'
Usage: deploy-reward-facets.sh [--prepare|--send|--verify]

  --prepare  Compile, test, inspect live accounting/selectors, and print hashes. No write. (default)
  --send     Deploy both facets, then print a Safe transaction or execute an EOA-owner cut.
  --verify   Verify EXPECTED_RP_FACET and EXPECTED_PR_FACET after an approved cut.

Environment:
  RPC / BASE_RPC_URL      Base mainnet RPC URL
  GRID                    Grid Diamond address
  AIPG                    AIPG token address
  HWFLAG                  --ledger (default) or --trezor
  CONFIRM=YES             required for --send
  EXPECTED_RP_FACET       required for --verify
  EXPECTED_PR_FACET       required for --verify

The cut atomically replaces RewardPool and PaymentRouter. It does not touch
DenReporter, roles, period configuration, balances, or WorkerRegistry.
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

uint_call() {
  local target=$1 signature=$2
  shift 2
  rpc_read cast call "$target" "$signature" "$@" --rpc-url "$RPC" | awk '{print $1}'
}

check_accounting() {
  local stage deposited paid bonded available token_balance reported_pool
  deposited=$(uint_call "$GRID" 'totalDeposited()(uint256)')
  paid=$(uint_call "$GRID" 'totalPaidOut()(uint256)')
  bonded=$(uint_call "$GRID" 'getTotalBonded()(uint256)')
  token_balance=$(uint_call "$AIPG" 'balanceOf(address)(uint256)' "$GRID")
  reported_pool=$(uint_call "$GRID" 'poolBalance()(uint256)')
  stage=$1
  available=$(STAGE="$stage" DEPOSITED="$deposited" PAID="$paid" BONDED="$bonded" \
    TOKEN_BALANCE="$token_balance" REPORTED_POOL="$reported_pool" MODE="$MODE" python3 - <<'PY'
import os

stage = os.environ["STAGE"]
deposited = int(os.environ["DEPOSITED"])
paid = int(os.environ["PAID"])
bonded = int(os.environ["BONDED"])
token_balance = int(os.environ["TOKEN_BALANCE"])
reported_pool = int(os.environ["REPORTED_POOL"])
if paid > deposited:
    raise SystemExit(f"{stage}: totalPaidOut exceeds totalDeposited")
available = deposited - paid
if token_balance < bonded + available:
    raise SystemExit(f"{stage}: token balance does not cover bonds plus rewards")
if os.environ["MODE"] == "verify" and reported_pool != available:
    raise SystemExit(f"{stage}: poolBalance does not equal deposited minus paid")
print(available)
PY
  )
  echo "$stage accounting: deposited=$deposited paid=$paid bonded=$bonded available=$available token=$token_balance poolView=$reported_pool"
}

validate_selectors() {
  local contract=$1 label=$2 methods signature expected source_selector i
  local signatures=() selectors=()
  if [[ "$label" == "RP" ]]; then
    signatures=("${RP_SIGNATURES[@]}")
    selectors=("${RP_SELECTORS[@]}")
  else
    signatures=("${PR_SIGNATURES[@]}")
    selectors=("${PR_SELECTORS[@]}")
  fi
  methods=$(forge inspect "$contract" methodIdentifiers --json)
  for i in "${!signatures[@]}"; do
    signature=${signatures[$i]}
    expected=${selectors[$i]}
    source_selector=$(METHODS_JSON="$methods" SIGNATURE="$signature" python3 - <<'PY'
import json
import os

methods = json.loads(os.environ["METHODS_JSON"])
selector = methods.get(os.environ["SIGNATURE"])
if selector is None:
    raise SystemExit(1)
print("0x" + selector.removeprefix("0x"))
PY
    )
    if [[ "$(cast sig "$signature")" != "$expected" || "$source_selector" != "$expected" ]]; then
      echo "Selector mismatch for $signature" >&2
      exit 1
    fi
  done
}

verify_routes() {
  local expected=$1 label=$2 signature got i failed=0
  local signatures=() selectors=()
  if [[ "$label" == "RP" ]]; then
    signatures=("${RP_SIGNATURES[@]}")
    selectors=("${RP_SELECTORS[@]}")
  else
    signatures=("${PR_SIGNATURES[@]}")
    selectors=("${PR_SELECTORS[@]}")
  fi
  for i in "${!signatures[@]}"; do
    signature=${signatures[$i]}
    got=$(rpc_read cast call "$GRID" 'moduleAddress(bytes4)(address)' \
      "${selectors[$i]}" --rpc-url "$RPC")
    if [[ "$(printf '%s' "$got" | lower)" != "$(printf '%s' "$expected" | lower)" ]]; then
      printf 'FAIL %-55s %s\n' "$signature" "$got"
      failed=1
    else
      printf 'OK   %-55s %s\n' "$signature" "$got"
    fi
  done
  return "$failed"
}

verify_runtime() {
  local facet=$1 contract=$2 label=$3 actual expected
  if [[ ! "$facet" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
    echo "$label facet must be a contract address" >&2
    exit 1
  fi
  actual=$(rpc_read cast code "$facet" --rpc-url "$RPC")
  expected=$(forge inspect "$contract" deployedBytecode)
  if [[ "$(printf '%s' "$actual" | lower)" != "$(printf '%s' "$expected" | lower)" ]]; then
    echo "$label deployed runtime does not match this reviewed build" >&2
    exit 1
  fi
}

for tool in forge cast git python3 awk; do
  require_tool "$tool"
done
if [[ "$HWFLAG" != "--ledger" && "$HWFLAG" != "--trezor" ]]; then
  echo "HWFLAG must be --ledger or --trezor" >&2
  exit 1
fi
if [[ "$(rpc_read cast chain-id --rpc-url "$RPC")" != "8453" ]]; then
  echo "Refusing a non-Base-mainnet RPC" >&2
  exit 1
fi
if [[ "$(rpc_read cast code "$GRID" --rpc-url "$RPC")" == "0x" ]]; then
  echo "No contract code at GRID=$GRID" >&2
  exit 1
fi
if [[ "$(rpc_read cast code "$AIPG" --rpc-url "$RPC")" == "0x" ]]; then
  echo "No contract code at AIPG=$AIPG" >&2
  exit 1
fi

forge build
validate_selectors "$RP_CONTRACT" RP
validate_selectors "$PR_CONTRACT" PR

if [[ "$MODE" == "verify" ]]; then
  RP_FACET=${EXPECTED_RP_FACET:-}
  PR_FACET=${EXPECTED_PR_FACET:-}
  verify_runtime "$RP_FACET" "$RP_CONTRACT" RewardPool
  verify_runtime "$PR_FACET" "$PR_CONTRACT" PaymentRouter
  verify_routes "$RP_FACET" RP
  verify_routes "$PR_FACET" PR
  check_accounting post-cut
  echo "Bond-reserve reward facets verified."
  exit 0
fi

echo "Running contract tests..."
forge test
check_accounting pre-cut

OWNER=$(rpc_read cast call "$GRID" 'owner()(address)' --rpc-url "$RPC")
OLD_RP=$(rpc_read cast call "$GRID" 'moduleAddress(bytes4)(address)' \
  "${RP_SELECTORS[0]}" --rpc-url "$RPC")
OLD_PR=$(rpc_read cast call "$GRID" 'moduleAddress(bytes4)(address)' \
  "${PR_SELECTORS[0]}" --rpc-url "$RPC")
if [[ "$(printf '%s' "$OLD_RP" | lower)" == "$ZERO" || "$(printf '%s' "$OLD_PR" | lower)" == "$ZERO" ]]; then
  echo "Reward facets are not fully deployed; refusing an upgrade-only script" >&2
  exit 1
fi
verify_routes "$OLD_RP" RP
verify_routes "$OLD_PR" PR

echo "Diamond owner:        $OWNER"
echo "Current RewardPool:   $OLD_RP"
echo "Current PaymentRouter:$OLD_PR"
echo "Source commit:        $(git rev-parse HEAD)"
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Source state:         DIRTY (development rehearsal only)"
else
  echo "Source state:         clean"
fi
echo "RewardPool runtime:   $(forge inspect "$RP_CONTRACT" deployedBytecode | cast keccak)"
echo "PaymentRouter runtime:$(forge inspect "$PR_CONTRACT" deployedBytecode | cast keccak)"

if [[ "$MODE" == "prepare" ]]; then
  echo "Preparation complete. No transaction was signed or broadcast."
  exit 0
fi
if [[ "$CONFIRM" != "YES" ]]; then
  echo "--send requires CONFIRM=YES" >&2
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "--send requires a clean worktree" >&2
  exit 1
fi
# shellcheck disable=SC2016
git submodule foreach --quiet 'test -z "$(git status --porcelain)"' || {
  echo "--send requires clean submodules" >&2
  exit 1
}

deploy_facet() {
  local contract=$1 label=$2 output facet
  output=$(forge create "$contract" --rpc-url "$RPC" "$HWFLAG" --broadcast --json)
  facet=$(printf '%s' "$output" | python3 -c 'import json,sys; print(json.load(sys.stdin)["deployedTo"])')
  verify_runtime "$facet" "$contract" "$label"
  printf '%s' "$facet"
}

echo "Deploying reviewed facets with $HWFLAG..."
NEW_RP=$(deploy_facet "$RP_CONTRACT" RewardPool)
NEW_PR=$(deploy_facet "$PR_CONTRACT" PaymentRouter)
RP_LIST=$(join_by_comma "${RP_SELECTORS[@]}")
PR_LIST=$(join_by_comma "${PR_SELECTORS[@]}")
CUT_ARG="[($NEW_RP,1,[$RP_LIST]),($NEW_PR,1,[$PR_LIST])]"
CALLDATA=$(cast calldata \
  'updateModules((address,uint8,bytes4[])[],address,bytes)' \
  "$CUT_ARG" "$ZERO" 0x)

if [[ "$(rpc_read cast code "$OWNER" --rpc-url "$RPC")" != "0x" ]]; then
  echo "Diamond owner is a Safe/contract. No cut was broadcast."
  echo "Safe target: $GRID"
  echo "Safe value:  0"
  echo "Safe data:   $CALLDATA"
  echo "After execution run:"
  echo "  EXPECTED_RP_FACET=$NEW_RP EXPECTED_PR_FACET=$NEW_PR $0 --verify"
  exit 0
fi

cast send "$GRID" \
  'updateModules((address,uint8,bytes4[])[],address,bytes)' \
  "$CUT_ARG" "$ZERO" 0x --rpc-url "$RPC" "$HWFLAG"
EXPECTED_RP_FACET=$NEW_RP EXPECTED_PR_FACET=$NEW_PR "$0" --verify
