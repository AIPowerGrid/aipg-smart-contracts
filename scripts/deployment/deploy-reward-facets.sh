#!/usr/bin/env bash
# Prepare, execute, or verify the bond-reserve RewardPool/PaymentRouter cut.
# Default mode is read-only. DenReporter is intentionally left untouched.
set -euo pipefail

GRID=${GRID:-0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609}
AIPG=${AIPG:-0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608}
RPC=${RPC:-${BASE_RPC_URL:-https://mainnet.base.org}}
HWFLAG=${HWFLAG:---ledger}
CONFIRM=${CONFIRM:-}
CONFIRM_GRID=${CONFIRM_GRID:-}
REVIEWED_COMMIT=${REVIEWED_COMMIT:-}
REVIEWED_RP_RUNTIME_HASH=${REVIEWED_RP_RUNTIME_HASH:-}
REVIEWED_PR_RUNTIME_HASH=${REVIEWED_PR_RUNTIME_HASH:-}
EXPECTED_OWNER=${EXPECTED_OWNER:-}
EXPECTED_OLD_RP_FACET=${EXPECTED_OLD_RP_FACET:-}
EXPECTED_OLD_PR_FACET=${EXPECTED_OLD_PR_FACET:-}
EXPECTED_TOTAL_DEPOSITED=${EXPECTED_TOTAL_DEPOSITED:-}
EXPECTED_TOTAL_PAID_OUT=${EXPECTED_TOTAL_PAID_OUT:-}
EXPECTED_TOTAL_BONDED=${EXPECTED_TOTAL_BONDED:-}
EXPECTED_TOKEN_BALANCE=${EXPECTED_TOKEN_BALANCE:-}
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
  CONFIRM_GRID            exact Grid address reviewed for --send
  REVIEWED_COMMIT         exact 40-character source commit reviewed for --send/--verify
  REVIEWED_RP_RUNTIME_HASH  exact RewardPool runtime hash reviewed for --send/--verify
  REVIEWED_PR_RUNTIME_HASH  exact PaymentRouter runtime hash reviewed for --send/--verify
  EXPECTED_OWNER          exact pre-cut Diamond owner reviewed for --send
  EXPECTED_OLD_RP_FACET   exact pre-cut RewardPool facet reviewed for --send
  EXPECTED_OLD_PR_FACET   exact pre-cut PaymentRouter facet reviewed for --send
  EXPECTED_TOTAL_DEPOSITED  exact pre-cut accounting snapshot for --send/--verify
  EXPECTED_TOTAL_PAID_OUT   exact pre-cut accounting snapshot for --send/--verify
  EXPECTED_TOTAL_BONDED     exact pre-cut accounting snapshot for --send/--verify
  EXPECTED_TOKEN_BALANCE    exact pre-cut Grid AIPG balance for --send/--verify
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
  # Never echo the full command or provider response: --rpc-url may contain
  # credentials, and upstream errors sometimes reflect the URL.
  echo "RPC read failed after $attempt attempts (${1##*/} ${2:-request})" >&2
  return 1
}

uint_call() {
  local target=$1 signature=$2
  shift 2
  rpc_read cast call "$target" "$signature" "$@" --rpc-url "$RPC" | awk '{print $1}'
}

check_accounting() {
  local stage=$1
  SNAPSHOT_BLOCK=$(rpc_read cast block-number --rpc-url "$RPC")
  SNAPSHOT_DEPOSITED=$(uint_call "$GRID" 'totalDeposited()(uint256)' --block "$SNAPSHOT_BLOCK")
  SNAPSHOT_PAID=$(uint_call "$GRID" 'totalPaidOut()(uint256)' --block "$SNAPSHOT_BLOCK")
  SNAPSHOT_BONDED=$(uint_call "$GRID" 'getTotalBonded()(uint256)' --block "$SNAPSHOT_BLOCK")
  SNAPSHOT_TOKEN_BALANCE=$(uint_call "$AIPG" 'balanceOf(address)(uint256)' "$GRID" \
    --block "$SNAPSHOT_BLOCK")
  SNAPSHOT_POOL_VIEW=$(uint_call "$GRID" 'poolBalance()(uint256)' --block "$SNAPSHOT_BLOCK")
  SNAPSHOT_AVAILABLE=$(STAGE="$stage" DEPOSITED="$SNAPSHOT_DEPOSITED" \
    PAID="$SNAPSHOT_PAID" BONDED="$SNAPSHOT_BONDED" \
    TOKEN_BALANCE="$SNAPSHOT_TOKEN_BALANCE" REPORTED_POOL="$SNAPSHOT_POOL_VIEW" \
    MODE="$MODE" python3 - <<'PY'
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
  echo "$stage accounting at block $SNAPSHOT_BLOCK: deposited=$SNAPSHOT_DEPOSITED paid=$SNAPSHOT_PAID bonded=$SNAPSHOT_BONDED available=$SNAPSHOT_AVAILABLE token=$SNAPSHOT_TOKEN_BALANCE poolView=$SNAPSHOT_POOL_VIEW"
}

require_accounting_snapshot() {
  local label expected_var expected actual
  for label in TOTAL_DEPOSITED TOTAL_PAID_OUT TOTAL_BONDED TOKEN_BALANCE; do
    case "$label" in
      TOTAL_DEPOSITED) actual=$SNAPSHOT_DEPOSITED ;;
      TOTAL_PAID_OUT) actual=$SNAPSHOT_PAID ;;
      TOTAL_BONDED) actual=$SNAPSHOT_BONDED ;;
      TOKEN_BALANCE) actual=$SNAPSHOT_TOKEN_BALANCE ;;
    esac
    expected_var="EXPECTED_$label"
    expected=${!expected_var}
    if [[ ! "$expected" =~ ^[0-9]+$ || "$expected" != "$actual" ]]; then
      echo "$expected_var no longer matches the live accounting snapshot" >&2
      exit 1
    fi
  done
}

validate_selectors() {
  local contract=$1 label=$2 methods method_count signature expected source_selector i
  local signatures=() selectors=()
  if [[ "$label" == "RP" ]]; then
    signatures=("${RP_SIGNATURES[@]}")
    selectors=("${RP_SELECTORS[@]}")
  else
    signatures=("${PR_SIGNATURES[@]}")
    selectors=("${PR_SELECTORS[@]}")
  fi
  methods=$(forge inspect "$contract" methodIdentifiers --json)
  method_count=$(METHODS_JSON="$methods" python3 - <<'PY'
import json
import os

print(len(json.loads(os.environ["METHODS_JSON"])))
PY
  )
  if [[ "$method_count" != "${#signatures[@]}" ]]; then
    echo "$label exports $method_count methods; reviewed surface expects ${#signatures[@]}" >&2
    exit 1
  fi
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

verify_legacy_selector_coverage() {
  local facet=$1 label=$2 selector found replacement
  shift 2
  local replacements=("$@") legacy_selectors=()
  local raw
  raw=$(rpc_read cast call "$GRID" 'moduleFunctionSelectors(address)(bytes4[])' \
    "$facet" --rpc-url "$RPC")
  while IFS= read -r selector; do
    [[ -n "$selector" ]] && legacy_selectors+=("$selector")
  done < <(OLD_SELECTOR_RAW="$raw" python3 - <<'PY'
import os
import re

for selector in re.findall(r"0x[0-9a-fA-F]{8}", os.environ["OLD_SELECTOR_RAW"]):
    print(selector.lower())
PY
  )
  if (( ${#legacy_selectors[@]} == 0 )); then
    echo "$label live facet reported no selectors" >&2
    exit 1
  fi
  for selector in "${legacy_selectors[@]}"; do
    found=0
    for replacement in "${replacements[@]}"; do
      if [[ "$selector" == "$(printf '%s' "$replacement" | lower)" ]]; then
        found=1
        break
      fi
    done
    if [[ "$found" == 0 ]]; then
      echo "$label live facet owns unreviewed selector $selector; refusing partial replacement" >&2
      exit 1
    fi
  done
  if (( ${#legacy_selectors[@]} != ${#replacements[@]} )); then
    echo "$label legacy selector count does not match replacement count" >&2
    exit 1
  fi
  echo "$label legacy selectors: ${#legacy_selectors[@]} (all covered by REPLACE)"
}

require_reviewed_source() {
  local head_commit
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "$MODE requires the clean reviewed source worktree" >&2
    exit 1
  fi
  # The command is intentionally expanded inside each submodule, not by this shell.
  # shellcheck disable=SC2016
  git submodule foreach --quiet 'test -z "$(git status --porcelain)"' || {
    echo "$MODE requires clean submodules" >&2
    exit 1
  }
  head_commit=$(git rev-parse HEAD)
  if [[ ! "$REVIEWED_COMMIT" =~ ^[0-9a-f]{40}$ || "$REVIEWED_COMMIT" != "$head_commit" ]]; then
    echo "REVIEWED_COMMIT must match the exact clean source commit" >&2
    exit 1
  fi
  if [[ ! "$REVIEWED_RP_RUNTIME_HASH" =~ ^0x[0-9a-fA-F]{64}$ ]] \
    || [[ "$(printf '%s' "$REVIEWED_RP_RUNTIME_HASH" | lower)" != "$(printf '%s' "$RP_RUNTIME_HASH" | lower)" ]]; then
    echo "REVIEWED_RP_RUNTIME_HASH must match the exact compiled RewardPool runtime" >&2
    exit 1
  fi
  if [[ ! "$REVIEWED_PR_RUNTIME_HASH" =~ ^0x[0-9a-fA-F]{64}$ ]] \
    || [[ "$(printf '%s' "$REVIEWED_PR_RUNTIME_HASH" | lower)" != "$(printf '%s' "$PR_RUNTIME_HASH" | lower)" ]]; then
    echo "REVIEWED_PR_RUNTIME_HASH must match the exact compiled PaymentRouter runtime" >&2
    exit 1
  fi
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
RP_RUNTIME_HASH=$(forge inspect "$RP_CONTRACT" deployedBytecode | cast keccak)
PR_RUNTIME_HASH=$(forge inspect "$PR_CONTRACT" deployedBytecode | cast keccak)

if [[ "$MODE" == "verify" ]]; then
  require_reviewed_source
  RP_FACET=${EXPECTED_RP_FACET:-}
  PR_FACET=${EXPECTED_PR_FACET:-}
  verify_runtime "$RP_FACET" "$RP_CONTRACT" RewardPool
  verify_runtime "$PR_FACET" "$PR_CONTRACT" PaymentRouter
  verify_routes "$RP_FACET" RP
  verify_routes "$PR_FACET" PR
  check_accounting post-cut
  require_accounting_snapshot
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
verify_legacy_selector_coverage "$OLD_RP" RewardPool "${RP_SELECTORS[@]}"
verify_legacy_selector_coverage "$OLD_PR" PaymentRouter "${PR_SELECTORS[@]}"

echo "Diamond owner:        $OWNER"
echo "Current RewardPool:   $OLD_RP"
echo "Current PaymentRouter:$OLD_PR"
echo "Source commit:        $(git rev-parse HEAD)"
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Source state:         DIRTY (development rehearsal only)"
else
  echo "Source state:         clean"
fi
echo "RewardPool runtime:   $RP_RUNTIME_HASH"
echo "PaymentRouter runtime:$PR_RUNTIME_HASH"

if [[ "$MODE" == "prepare" ]]; then
  echo
  echo "Preparation complete. No transaction was signed or broadcast."
  echo "Commit the candidate, repeat --prepare from a clean tree, and independently review"
  echo "that exact commit, selector coverage, and accounting snapshot before --send."
  echo
  echo "Reviewed send/verify anchors (public values; independently verify before use):"
  echo "  CONFIRM_GRID=$GRID"
  echo "  REVIEWED_COMMIT=$(git rev-parse HEAD)"
  echo "  REVIEWED_RP_RUNTIME_HASH=$RP_RUNTIME_HASH"
  echo "  REVIEWED_PR_RUNTIME_HASH=$PR_RUNTIME_HASH"
  echo "  EXPECTED_OWNER=$OWNER"
  echo "  EXPECTED_OLD_RP_FACET=$OLD_RP"
  echo "  EXPECTED_OLD_PR_FACET=$OLD_PR"
  echo "  EXPECTED_TOTAL_DEPOSITED=$SNAPSHOT_DEPOSITED"
  echo "  EXPECTED_TOTAL_PAID_OUT=$SNAPSHOT_PAID"
  echo "  EXPECTED_TOTAL_BONDED=$SNAPSHOT_BONDED"
  echo "  EXPECTED_TOKEN_BALANCE=$SNAPSHOT_TOKEN_BALANCE"
  exit 0
fi
if [[ "$CONFIRM" != "YES" ]]; then
  echo "--send requires CONFIRM=YES" >&2
  exit 1
fi
require_reviewed_source
OWNER=$(rpc_read cast call "$GRID" 'owner()(address)' --rpc-url "$RPC")
OLD_RP=$(rpc_read cast call "$GRID" 'moduleAddress(bytes4)(address)' \
  "${RP_SELECTORS[0]}" --rpc-url "$RPC")
OLD_PR=$(rpc_read cast call "$GRID" 'moduleAddress(bytes4)(address)' \
  "${PR_SELECTORS[0]}" --rpc-url "$RPC")
verify_routes "$OLD_RP" RP
verify_routes "$OLD_PR" PR
verify_legacy_selector_coverage "$OLD_RP" RewardPool "${RP_SELECTORS[@]}"
verify_legacy_selector_coverage "$OLD_PR" PaymentRouter "${PR_SELECTORS[@]}"
check_accounting send-pre-cut
if [[ "$(printf '%s' "$CONFIRM_GRID" | lower)" != "$(printf '%s' "$GRID" | lower)" ]]; then
  echo "CONFIRM_GRID must match the reviewed Grid address" >&2
  exit 1
fi
if [[ "$(printf '%s' "$EXPECTED_OWNER" | lower)" != "$(printf '%s' "$OWNER" | lower)" ]]; then
  echo "EXPECTED_OWNER no longer matches the Diamond owner" >&2
  exit 1
fi
if [[ "$(printf '%s' "$EXPECTED_OLD_RP_FACET" | lower)" != "$(printf '%s' "$OLD_RP" | lower)" ]]; then
  echo "EXPECTED_OLD_RP_FACET no longer matches the live RewardPool" >&2
  exit 1
fi
if [[ "$(printf '%s' "$EXPECTED_OLD_PR_FACET" | lower)" != "$(printf '%s' "$OLD_PR" | lower)" ]]; then
  echo "EXPECTED_OLD_PR_FACET no longer matches the live PaymentRouter" >&2
  exit 1
fi
require_accounting_snapshot

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
  echo "  REVIEWED_COMMIT=$REVIEWED_COMMIT REVIEWED_RP_RUNTIME_HASH=$REVIEWED_RP_RUNTIME_HASH REVIEWED_PR_RUNTIME_HASH=$REVIEWED_PR_RUNTIME_HASH EXPECTED_TOTAL_DEPOSITED=$SNAPSHOT_DEPOSITED EXPECTED_TOTAL_PAID_OUT=$SNAPSHOT_PAID EXPECTED_TOTAL_BONDED=$SNAPSHOT_BONDED EXPECTED_TOKEN_BALANCE=$SNAPSHOT_TOKEN_BALANCE EXPECTED_RP_FACET=$NEW_RP EXPECTED_PR_FACET=$NEW_PR $0 --verify"
  exit 0
fi

cast send "$GRID" \
  'updateModules((address,uint8,bytes4[])[],address,bytes)' \
  "$CUT_ARG" "$ZERO" 0x --rpc-url "$RPC" "$HWFLAG"
REVIEWED_COMMIT=$REVIEWED_COMMIT \
  REVIEWED_RP_RUNTIME_HASH=$REVIEWED_RP_RUNTIME_HASH \
  REVIEWED_PR_RUNTIME_HASH=$REVIEWED_PR_RUNTIME_HASH \
  EXPECTED_TOTAL_DEPOSITED=$SNAPSHOT_DEPOSITED \
  EXPECTED_TOTAL_PAID_OUT=$SNAPSHOT_PAID \
  EXPECTED_TOTAL_BONDED=$SNAPSHOT_BONDED \
  EXPECTED_TOKEN_BALANCE=$SNAPSHOT_TOKEN_BALANCE \
  EXPECTED_RP_FACET=$NEW_RP EXPECTED_PR_FACET=$NEW_PR "$0" --verify
