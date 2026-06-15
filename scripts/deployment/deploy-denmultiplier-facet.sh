#!/usr/bin/env bash
# Deploy the ModelVault denMultiplier facet and cut it into the live Grid diamond.
#
# Adds 3 admin functions to ModelVault so per-model den (reward) multipliers live
# on-chain (see docs/DEN_MULTIPLIER.md). Signs with the admin HARDWARE WALLET —
# no private keys ever touch this script or disk.
#
# Prereqs: foundry (forge/cast), the admin Trezor/Ledger connected, the admin
# being 0xA218db26ed545f3476e6c3E827b595cf2E182533 (Grid owner).
#
# Usage:
#   RPC=https://mainnet.base.org ./scripts/deployment/deploy-denmultiplier-facet.sh
# Add HWFLAG=--ledger if you use a Ledger instead of a Trezor.
set -euo pipefail

GRID=0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609
RPC=${RPC:-https://mainnet.base.org}
HWFLAG=${HWFLAG:---trezor}

# New selectors (verified: forge inspect ModelVault methodIdentifiers)
SET_ONE=0x495a7e60      # setDenMultiplier(uint256,uint256)
SET_BATCH=0x35172d70    # setDenMultipliers(uint256[],uint256[])
GET=0xb1a673ed          # getDenMultiplier(uint256)

echo "1) Deploy the new ModelVault implementation (contains base + update + den fns)..."
echo "   Only the 3 NEW selectors below are cut in; existing ModelVault selectors"
echo "   keep pointing at their current facets."
FACET=$(forge create contracts/grid/modules/ModelVault.sol:ModelVault \
  --rpc-url "$RPC" $HWFLAG --broadcast --json | python3 -c 'import sys,json;print(json.load(sys.stdin)["deployedTo"])')
echo "   New ModelVault impl: $FACET"

echo "2) updateModules ADD (action=0) the 3 den selectors -> new impl..."
# IModuleManager.updateModules((address,uint8,bytes4[])[] cut, address init, bytes calldata)
cast send "$GRID" \
  "updateModules((address,uint8,bytes4[])[],address,bytes)" \
  "[($FACET,0,[$SET_ONE,$SET_BATCH,$GET])]" \
  0x0000000000000000000000000000000000000000 \
  0x \
  --rpc-url "$RPC" $HWFLAG

echo "3) Verify the selectors now resolve to the new facet:"
for s in "$SET_ONE" "$SET_BATCH" "$GET"; do
  echo "   $s -> $(cast call "$GRID" 'moduleAddress(bytes4)(address)' "$s" --rpc-url "$RPC")"
done
echo "Done. Next: register current models (if needed) + set their multipliers"
echo "(scripts/deployment/set-den-multipliers.sh)."
