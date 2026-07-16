#!/usr/bin/env bash
# Prepare or register the exact canonical ACE-Step recipe from Worker Profile V1.
# Default mode is offline/read-only. Passing --send broadcasts one Base mainnet
# transaction with a hardware wallet; this script never accepts a raw private key.
set -euo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
PROFILE=${PROFILE:-"$SCRIPT_DIR/../../../grid-media-worker/bridge/profiles/ace-step-v1.profile.json"}
GRID=${GRID:-0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609}
RPC=${RPC:-https://mainnet.base.org}
HWFLAG=${HWFLAG:---ledger}
MODE=${1:---prepare}

case "$MODE" in
  --prepare|--send) ;;
  *) echo "Usage: $0 [--prepare|--send]" >&2; exit 2 ;;
esac

command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
if [ "$MODE" = "--send" ]; then
  command -v cast >/dev/null || { echo "Foundry cast is required" >&2; exit 1; }
fi

PLAN=$(mktemp)
trap 'rm -f "$PLAN"' EXIT

python3 - "$PROFILE" "$PLAN" <<'PY'
import hashlib
import json
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).expanduser().resolve()
destination = pathlib.Path(sys.argv[2])
envelope = json.loads(source.read_text(encoding="utf-8"))
profile = envelope.get("profile")
if not isinstance(profile, dict):
    raise SystemExit("profile envelope is malformed")
recipe = profile.get("recipe")
if not isinstance(recipe, dict) or not isinstance(recipe.get("spec"), dict):
    raise SystemExit("profile recipe is malformed")
canonical = json.dumps(
    recipe["spec"], sort_keys=True, separators=(",", ":"), ensure_ascii=True
).encode("ascii")
digest = hashlib.sha256(canonical).hexdigest()
if digest != recipe.get("sha256"):
    raise SystemExit("recipe SHA-256 does not match canonical recipe bytes")
onchain = recipe.get("onchain_root")
if onchain not in (None, "0x" + digest):
    raise SystemExit("profile on-chain root conflicts with the canonical recipe SHA-256")
name = f"AIPG {profile['id']} {profile['version']}"
description = "Canonical governed ACE-Step audio recipe for AI Power Grid Worker Profile V1"
plan = {
    "profile": str(source),
    "profile_id": profile["id"],
    "profile_version": profile["version"],
    "recipe_root": "0x" + digest,
    "workflow_data": "0x" + canonical.hex(),
    "workflow_bytes": len(canonical),
    "can_create_nfts": False,
    "is_public": True,
    "compression": 0,
    "name": name,
    "description": description,
}
destination.write_text(json.dumps(plan), encoding="utf-8")
PY

ROOT=$(jq -r .recipe_root "$PLAN")
DATA=$(jq -r .workflow_data "$PLAN")
NAME=$(jq -r .name "$PLAN")
DESCRIPTION=$(jq -r .description "$PLAN")

echo "Profile:       $(jq -r .profile "$PLAN")"
echo "Recipe root:   $ROOT"
echo "Canonical size: $(jq -r .workflow_bytes "$PLAN") bytes"
echo "Diamond:       $GRID"
echo "NFT permission: false"
echo "Public recipe: true"

if [ "$MODE" = "--prepare" ]; then
  echo "Prepared only. Review the frozen profile and rerun with --send when authorized."
  exit 0
fi

CHAIN_ID=$(cast chain-id --rpc-url "$RPC")
[ "$CHAIN_ID" = "8453" ] || { echo "Refusing non-Base-mainnet chain ID $CHAIN_ID" >&2; exit 1; }

MAX_BYTES=$(cast call "$GRID" "getMaxWorkflowBytes()(uint256)" --rpc-url "$RPC" --json | jq -r '.[0]')
WORKFLOW_BYTES=$(jq -r .workflow_bytes "$PLAN")
if [ "$MAX_BYTES" -ne 0 ] && [ "$WORKFLOW_BYTES" -gt "$MAX_BYTES" ]; then
  echo "Refusing recipe larger than the live RecipeVault cap ($WORKFLOW_BYTES > $MAX_BYTES)" >&2
  exit 1
fi

EXISTING=$(cast call "$GRID" \
  "getRecipeByRoot(bytes32)((uint256,bytes32,bytes,address,bool,bool,uint8,uint256,string,string))" \
  "$ROOT" --rpc-url "$RPC" --json)
EXISTING_ID=$(jq -r '.[0][0]' <<<"$EXISTING")
if [ "$EXISTING_ID" -ne 0 ]; then
  jq -e \
    --arg root "$ROOT" \
    --arg data "$DATA" \
    --arg name "$NAME" \
    --arg description "$DESCRIPTION" \
    '.[0] | .[1] == $root and .[2] == $data and .[4] == false and
      .[5] == true and .[6] == 0 and .[8] == $name and .[9] == $description' \
    <<<"$EXISTING" >/dev/null || {
      echo "Recipe root already exists with conflicting data or permissions; refusing to send" >&2
      exit 1
    }
  echo "Recipe $EXISTING_ID is already registered with the exact canonical data; no transaction needed."
  exit 0
fi

echo "Broadcasting RecipeVault.storeRecipe from the hardware wallet..."
# shellcheck disable=SC2086 # HWFLAG intentionally expands to one cast signer option.
cast send "$GRID" \
  "storeRecipe(bytes32,bytes,bool,bool,uint8,string,string)" \
  "$ROOT" "$DATA" false true 0 "$NAME" "$DESCRIPTION" \
  --rpc-url "$RPC" $HWFLAG

echo "Verifying the stored entry by root..."
cast call "$GRID" \
  "getRecipeByRoot(bytes32)((uint256,bytes32,bytes,address,bool,bool,uint8,uint256,string,string))" \
  "$ROOT" --rpc-url "$RPC"
echo "After review, set profile.recipe.onchain_root to $ROOT before signing the final profile."
