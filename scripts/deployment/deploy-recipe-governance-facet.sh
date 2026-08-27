#!/usr/bin/env bash
# Prepare, execute, or verify the governed RecipeVault facet cut on Base.
# Default mode is read-only. The cut does not grant roles or change recipe data.
set -euo pipefail

GRID=${GRID:-0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609}
RPC=${RPC:-${BASE_RPC_URL:-https://mainnet.base.org}}
HWFLAG=${HWFLAG:---ledger}
CONFIRM=${CONFIRM:-}
CONFIRM_GRID=${CONFIRM_GRID:-}
REVIEWED_COMMIT=${REVIEWED_COMMIT:-}
REVIEWED_RUNTIME_HASH=${REVIEWED_RUNTIME_HASH:-}
EXPECTED_OWNER=${EXPECTED_OWNER:-}
EXPECTED_OLD_FACET=${EXPECTED_OLD_FACET:-}
EXPECTED_TOTAL_RECIPES=${EXPECTED_TOTAL_RECIPES:-}
EXPECTED_MAX_WORKFLOW_BYTES=${EXPECTED_MAX_WORKFLOW_BYTES:-}
EXPECTED_RECIPE_STATE_HASH=${EXPECTED_RECIPE_STATE_HASH:-}
MODE=prepare
ZERO=0x0000000000000000000000000000000000000000
CONTRACT=contracts/grid/modules/RecipeVault.sol:RecipeVault
MAX_SNAPSHOT_RECIPES=256

SIGNATURES=(
  'canRecipeCreateNFTs(uint256)'
  'getCreatorRecipes(address)'
  'getMaxWorkflowBytes()'
  'getRecipe(uint256)'
  'getRecipeByRoot(bytes32)'
  'getTotalRecipes()'
  'isRecipePublic(uint256)'
  'setMaxWorkflowBytes(uint256)'
  'storeRecipe(bytes32,bytes,bool,bool,uint8,string,string)'
  'updateRecipePermissions(uint256,bool,bool)'
)
SELECTORS=(
  0xa6658f46
  0x98f9ecf8
  0x4d0af193
  0xf8d12a41
  0xc03ce167
  0x1650ac6d
  0xb7471fc2
  0xfa8e6b0b
  0xb2c93a4b
  0x63927510
)

usage() {
  cat <<'EOF'
Usage: deploy-recipe-governance-facet.sh [--prepare|--send|--verify]

  --prepare  Compile, test, inspect all live recipes/selectors, and print anchors. No write. (default)
  --send     Deploy with Ledger/Trezor, then print Safe calldata or execute an EOA-owner cut.
  --verify   Verify EXPECTED_FACET and the complete pre-cut recipe-state commitment.

Environment:
  RPC / BASE_RPC_URL       Base mainnet RPC URL
  GRID                     Grid Diamond address
  HWFLAG                   --ledger (default) or --trezor
  CONFIRM=YES              required for --send
  CONFIRM_GRID             exact reviewed Grid address
  REVIEWED_COMMIT          exact 40-character reviewed source commit
  REVIEWED_RUNTIME_HASH    exact keccak256 compiled deployed-runtime hash
  EXPECTED_OWNER           exact pre-cut Diamond owner
  EXPECTED_OLD_FACET       exact pre-cut RecipeVault facet
  EXPECTED_TOTAL_RECIPES   exact pre-cut recipe count
  EXPECTED_MAX_WORKFLOW_BYTES  exact pre-cut workflow cap
  EXPECTED_RECIPE_STATE_HASH  SHA-256 commitment to every pre-cut recipe ABI record
  EXPECTED_FACET           deployed governed facet address for --verify

The cut replaces all ten RecipeVault selectors atomically. It preserves every
legacy record and does not grant REGISTRAR_ROLE, alter visibility/NFT flags,
change maxWorkflowBytes, or enable Core RecipeVault synchronization.
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
  # Provider errors can reflect credential-bearing URLs, so never print the
  # command or raw response here.
  echo "RPC read failed after $attempt attempts (${1##*/} ${2:-request})" >&2
  return 1
}

uint_call() {
  local signature=$1 block=$2
  rpc_read cast call "$GRID" "$signature" --block "$block" --rpc-url "$RPC" | awk '{print $1}'
}

validate_selectors() {
  local methods count signature expected source_selector i
  methods=$(forge inspect "$CONTRACT" methodIdentifiers --json)
  count=$(METHODS_JSON="$methods" python3 - <<'PY'
import json
import os

print(len(json.loads(os.environ["METHODS_JSON"])))
PY
  )
  if [[ "$count" != "${#SIGNATURES[@]}" ]]; then
    echo "RecipeVault exports $count methods; reviewed surface expects ${#SIGNATURES[@]}" >&2
    exit 1
  fi
  for i in "${!SIGNATURES[@]}"; do
    signature=${SIGNATURES[$i]}
    expected=${SELECTORS[$i]}
    source_selector=$(METHODS_JSON="$methods" SIGNATURE="$signature" python3 - <<'PY'
import json
import os

selector = json.loads(os.environ["METHODS_JSON"]).get(os.environ["SIGNATURE"])
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

snapshot_recipes() {
  local block=$1 id data raw
  SNAPSHOT_TOTAL=$(uint_call 'getTotalRecipes()(uint256)' "$block")
  SNAPSHOT_MAX_BYTES=$(uint_call 'getMaxWorkflowBytes()(uint256)' "$block")
  if [[ ! "$SNAPSHOT_TOTAL" =~ ^[0-9]+$ || "$SNAPSHOT_TOTAL" -gt "$MAX_SNAPSHOT_RECIPES" ]]; then
    echo "Recipe count $SNAPSHOT_TOTAL exceeds reviewed snapshot bound $MAX_SNAPSHOT_RECIPES" >&2
    exit 1
  fi
  SNAPSHOT_HASH=$(
    {
      printf 'total=%s\nmax=%s\n' "$SNAPSHOT_TOTAL" "$SNAPSHOT_MAX_BYTES"
      for ((id = 1; id <= SNAPSHOT_TOTAL; id++)); do
        data=$(cast calldata 'getRecipe(uint256)' "$id")
        raw=$(rpc_read cast call "$GRID" --data "$data" --block "$block" --rpc-url "$RPC")
        printf 'recipe[%s]=%s\n' "$id" "$(printf '%s' "$raw" | lower)"
      done
    } | python3 -c 'import hashlib,sys; print("0x" + hashlib.sha256(sys.stdin.buffer.read()).hexdigest())'
  )
  SNAPSHOT_BLOCK=$block
}

require_snapshot() {
  if [[ ! "$EXPECTED_TOTAL_RECIPES" =~ ^[0-9]+$ \
    || "$EXPECTED_TOTAL_RECIPES" != "$SNAPSHOT_TOTAL" ]]; then
    echo "EXPECTED_TOTAL_RECIPES no longer matches live state" >&2
    exit 1
  fi
  if [[ ! "$EXPECTED_MAX_WORKFLOW_BYTES" =~ ^[0-9]+$ \
    || "$EXPECTED_MAX_WORKFLOW_BYTES" != "$SNAPSHOT_MAX_BYTES" ]]; then
    echo "EXPECTED_MAX_WORKFLOW_BYTES no longer matches live state" >&2
    exit 1
  fi
  if [[ ! "$EXPECTED_RECIPE_STATE_HASH" =~ ^0x[0-9a-fA-F]{64}$ \
    || "$(printf '%s' "$EXPECTED_RECIPE_STATE_HASH" | lower)" != "$(printf '%s' "$SNAPSHOT_HASH" | lower)" ]]; then
    echo "EXPECTED_RECIPE_STATE_HASH no longer matches every live recipe record" >&2
    exit 1
  fi
}

verify_routes() {
  local expected=$1 got i failed=0
  for i in "${!SIGNATURES[@]}"; do
    got=$(rpc_read cast call "$GRID" 'moduleAddress(bytes4)(address)' \
      "${SELECTORS[$i]}" --rpc-url "$RPC")
    if [[ "$(printf '%s' "$got" | lower)" != "$(printf '%s' "$expected" | lower)" ]]; then
      printf 'FAIL %-72s %s\n' "${SIGNATURES[$i]}" "$got"
      failed=1
    else
      printf 'OK   %-72s %s\n' "${SIGNATURES[$i]}" "$got"
    fi
  done
  return "$failed"
}

verify_legacy_coverage() {
  local facet=$1 raw selector expected found legacy_count=0
  raw=$(rpc_read cast call "$GRID" 'moduleFunctionSelectors(address)(bytes4[])' \
    "$facet" --rpc-url "$RPC")
  while IFS= read -r selector; do
    [[ -n "$selector" ]] || continue
    legacy_count=$((legacy_count + 1))
    found=0
    for expected in "${SELECTORS[@]}"; do
      if [[ "$selector" == "$(printf '%s' "$expected" | lower)" ]]; then
        found=1
        break
      fi
    done
    if [[ "$found" == 0 ]]; then
      echo "Live RecipeVault owns unreviewed selector $selector; refusing partial replacement" >&2
      exit 1
    fi
  done < <(OLD_SELECTOR_RAW="$raw" python3 - <<'PY'
import os
import re

for selector in re.findall(r"0x[0-9a-fA-F]{8}", os.environ["OLD_SELECTOR_RAW"]):
    print(selector.lower())
PY
  )
  if [[ "$legacy_count" != "${#SELECTORS[@]}" ]]; then
    echo "Live RecipeVault selector count $legacy_count does not equal ${#SELECTORS[@]}" >&2
    exit 1
  fi
  verify_routes "$facet"
  echo "Legacy RecipeVault selectors: $legacy_count (all covered by REPLACE)"
}

require_reviewed_source() {
  local head_commit
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "$MODE requires the clean reviewed source worktree" >&2
    exit 1
  fi
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
  if [[ ! "$REVIEWED_RUNTIME_HASH" =~ ^0x[0-9a-fA-F]{64}$ \
    || "$(printf '%s' "$REVIEWED_RUNTIME_HASH" | lower)" != "$(printf '%s' "$RUNTIME_HASH" | lower)" ]]; then
    echo "REVIEWED_RUNTIME_HASH must match the exact compiled RecipeVault runtime" >&2
    exit 1
  fi
}

verify_runtime() {
  local facet=$1 actual expected
  if [[ ! "$facet" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
    echo "EXPECTED_FACET must be a contract address" >&2
    exit 1
  fi
  actual=$(rpc_read cast code "$facet" --rpc-url "$RPC")
  expected=$(forge inspect "$CONTRACT" deployedBytecode)
  if [[ "$(printf '%s' "$actual" | lower)" != "$(printf '%s' "$expected" | lower)" ]]; then
    echo "Deployed RecipeVault runtime does not match reviewed source" >&2
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

forge build
validate_selectors
RUNTIME_HASH=$(forge inspect "$CONTRACT" deployedBytecode | cast keccak)

if [[ "$MODE" == "verify" ]]; then
  require_reviewed_source
  FACET=${EXPECTED_FACET:-}
  verify_runtime "$FACET"
  verify_routes "$FACET"
  snapshot_recipes "$(rpc_read cast block-number --rpc-url "$RPC")"
  require_snapshot
  echo "Governed RecipeVault facet verified with all legacy recipe state preserved."
  exit 0
fi

echo "Running contract tests..."
forge test
OWNER=$(rpc_read cast call "$GRID" 'owner()(address)' --rpc-url "$RPC")
OLD_FACET=$(rpc_read cast call "$GRID" 'moduleAddress(bytes4)(address)' \
  "${SELECTORS[0]}" --rpc-url "$RPC")
if [[ "$(printf '%s' "$OLD_FACET" | lower)" == "$ZERO" ]]; then
  echo "RecipeVault is not deployed; refusing an upgrade-only script" >&2
  exit 1
fi
verify_legacy_coverage "$OLD_FACET"
snapshot_recipes "$(rpc_read cast block-number --rpc-url "$RPC")"

echo "Grid:                    $GRID"
echo "Diamond owner:           $OWNER"
echo "Current RecipeVault:     $OLD_FACET"
echo "Source commit:           $(git rev-parse HEAD)"
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Source state:            DIRTY (development rehearsal only)"
else
  echo "Source state:            clean"
fi
echo "RecipeVault runtime:     $RUNTIME_HASH"
echo "Snapshot block:          $SNAPSHOT_BLOCK"
echo "Total recipes:           $SNAPSHOT_TOTAL"
echo "Max workflow bytes:      $SNAPSHOT_MAX_BYTES"
echo "All-recipe state hash:   $SNAPSHOT_HASH"

if [[ "$MODE" == "prepare" ]]; then
  echo
  echo "Preparation complete. No transaction was signed or broadcast."
  echo "Commit the candidate, repeat --prepare from a clean tree, and independently review"
  echo "the exact commit, selector coverage, runtime, and full recipe-state commitment."
  echo
  echo "Reviewed send/verify anchors (public values; independently verify before use):"
  echo "  CONFIRM_GRID=$GRID"
  echo "  REVIEWED_COMMIT=$(git rev-parse HEAD)"
  echo "  REVIEWED_RUNTIME_HASH=$RUNTIME_HASH"
  echo "  EXPECTED_OWNER=$OWNER"
  echo "  EXPECTED_OLD_FACET=$OLD_FACET"
  echo "  EXPECTED_TOTAL_RECIPES=$SNAPSHOT_TOTAL"
  echo "  EXPECTED_MAX_WORKFLOW_BYTES=$SNAPSHOT_MAX_BYTES"
  echo "  EXPECTED_RECIPE_STATE_HASH=$SNAPSHOT_HASH"
  exit 0
fi

if [[ "$CONFIRM" != "YES" ]]; then
  echo "--send requires CONFIRM=YES" >&2
  exit 1
fi
require_reviewed_source
if [[ "$(printf '%s' "$CONFIRM_GRID" | lower)" != "$(printf '%s' "$GRID" | lower)" ]]; then
  echo "CONFIRM_GRID must match the reviewed Grid address" >&2
  exit 1
fi
OWNER=$(rpc_read cast call "$GRID" 'owner()(address)' --rpc-url "$RPC")
OLD_FACET=$(rpc_read cast call "$GRID" 'moduleAddress(bytes4)(address)' \
  "${SELECTORS[0]}" --rpc-url "$RPC")
verify_legacy_coverage "$OLD_FACET"
snapshot_recipes "$(rpc_read cast block-number --rpc-url "$RPC")"
if [[ "$(printf '%s' "$EXPECTED_OWNER" | lower)" != "$(printf '%s' "$OWNER" | lower)" ]]; then
  echo "EXPECTED_OWNER no longer matches the Diamond owner" >&2
  exit 1
fi
if [[ "$(printf '%s' "$EXPECTED_OLD_FACET" | lower)" != "$(printf '%s' "$OLD_FACET" | lower)" ]]; then
  echo "EXPECTED_OLD_FACET no longer matches the live RecipeVault" >&2
  exit 1
fi
require_snapshot

echo "Deploying reviewed RecipeVault facet with $HWFLAG..."
OUTPUT=$(forge create "$CONTRACT" --rpc-url "$RPC" "$HWFLAG" --broadcast --json)
NEW_FACET=$(printf '%s' "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["deployedTo"])')
verify_runtime "$NEW_FACET"
SELECTOR_LIST=$(join_by_comma "${SELECTORS[@]}")
CUT_ARG="[($NEW_FACET,1,[$SELECTOR_LIST])]"
CALLDATA=$(cast calldata \
  'updateModules((address,uint8,bytes4[])[],address,bytes)' \
  "$CUT_ARG" "$ZERO" 0x)

if [[ "$(rpc_read cast code "$OWNER" --rpc-url "$RPC")" != "0x" ]]; then
  echo "Diamond owner is a Safe/contract. No cut was broadcast."
  echo "Safe target: $GRID"
  echo "Safe value:  0"
  echo "Safe data:   $CALLDATA"
  echo "After approved execution run:"
  echo "  REVIEWED_COMMIT=$REVIEWED_COMMIT REVIEWED_RUNTIME_HASH=$REVIEWED_RUNTIME_HASH EXPECTED_TOTAL_RECIPES=$SNAPSHOT_TOTAL EXPECTED_MAX_WORKFLOW_BYTES=$SNAPSHOT_MAX_BYTES EXPECTED_RECIPE_STATE_HASH=$SNAPSHOT_HASH EXPECTED_FACET=$NEW_FACET $0 --verify"
  exit 0
fi

cast send "$GRID" \
  'updateModules((address,uint8,bytes4[])[],address,bytes)' \
  "$CUT_ARG" "$ZERO" 0x --rpc-url "$RPC" "$HWFLAG"
REVIEWED_COMMIT=$REVIEWED_COMMIT \
  REVIEWED_RUNTIME_HASH=$REVIEWED_RUNTIME_HASH \
  EXPECTED_TOTAL_RECIPES=$SNAPSHOT_TOTAL \
  EXPECTED_MAX_WORKFLOW_BYTES=$SNAPSHOT_MAX_BYTES \
  EXPECTED_RECIPE_STATE_HASH=$SNAPSHOT_HASH \
  EXPECTED_FACET=$NEW_FACET "$0" --verify
