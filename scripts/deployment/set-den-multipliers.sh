#!/usr/bin/env bash
# Set per-model den multipliers in ModelVault (batch), signed with the admin
# hardware wallet. Run AFTER deploy-denmultiplier-facet.sh.
#
# Edit IDS and MULTS_E3 below (parallel arrays). MULTS_E3 is the multiplier x1000
# (a 27B model => 27000, a 7B => 7000, 1.5B => 1500). Get model IDs from:
#   cast call <GRID> "getModelCount()(uint256)" --rpc-url $RPC
#   cast call <GRID> "getModel(uint256)(...)" <id> --rpc-url $RPC   # read names
#
# The model must already be registered (registerModel) or the call reverts.
set -euo pipefail

GRID=0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609
RPC=${RPC:-https://mainnet.base.org}
HWFLAG=${HWFLAG:---trezor}

# ── EDIT THESE (parallel arrays) ──
IDS="[]"          # e.g. [12,13,14]
MULTS_E3="[]"     # e.g. [120000,27000,7000]  (120B, 27B, 7B)

if [ "$IDS" = "[]" ]; then
  echo "Edit IDS and MULTS_E3 in this script first."; exit 1
fi

cast send "$GRID" \
  "setDenMultipliers(uint256[],uint256[])" \
  "$IDS" "$MULTS_E3" \
  --rpc-url "$RPC" $HWFLAG

echo "Set ${IDS} -> ${MULTS_E3} (x1000). The grid picks these up on its next"
echo "ModelVault sync (<= MODELVAULT_SYNC_SECONDS)."
