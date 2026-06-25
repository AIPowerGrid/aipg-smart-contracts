#!/usr/bin/env bash
# Deploy the upgraded WorkerRegistry facet (unbond cooldown + slashing) and cut
# it into the live Grid diamond.
#
# What this changes on-chain
# --------------------------
#   * unbond() STOPS returning the bond instantly. It now marks the worker
#     inactive and starts a cooldown (default 7 days). This closes the
#     slash-escape hole where a worker could pull its bond in the same tx it
#     misbehaved. Same selector, safe new behavior.
#   * NEW: withdrawBond()  — return the bond after the cooldown elapses.
#   * NEW: cancelUnbond()  — abort an in-progress unbond, return to service.
#   * NEW: slash(address,uint256,string) — SLASHER_ROLE/ADMIN_ROLE burns part or
#     all of a bond; slashed AIPG is routed to the reward pool by internal
#     accounting (totalBonded down, totalDeposited up — no token transfer).
#   * NEW: setUnbondingPeriod / unbondingPeriod / getUnbondInfo / setMinBond.
#   * getWorker() now returns the 8-field Worker struct (adds unbondingAt).
#
# Storage: GridStorage appends `Worker.unbondingAt` (end of struct, safe for a
# struct-in-mapping) and `unbondingPeriodSeconds` (end of AppStorage), plus the
# SLASHER_ROLE constant. No existing slot moves.
#
# Signs with the admin HARDWARE WALLET — no private keys touch this script.
# Prereqs: foundry (forge/cast), admin Trezor/Ledger connected, admin =
# 0xA218db26ed545f3476e6c3E827b595cf2E182533 (Grid owner).
#
# Usage:
#   RPC=https://mainnet.base.org ./scripts/deployment/deploy-worker-bonding-facet.sh
# Add HWFLAG=--ledger if you use a Ledger instead of a Trezor.
#
# After cutting the facet, grant SLASHER_ROLE to the grid's enforcement key:
#   cast send $GRID 'grantRole(bytes32,address)' \
#     $(cast keccak "SLASHER_ROLE") <enforcer-address> --rpc-url $RPC $HWFLAG
# and (optionally) set a non-default cooldown / min bond via setUnbondingPeriod
# / setMinBond.
set -euo pipefail

GRID=0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609
RPC=${RPC:-https://mainnet.base.org}
HWFLAG=${HWFLAG:---trezor}
ZERO=0x0000000000000000000000000000000000000000

# All WorkerRegistry selectors served by the new facet
# (forge inspect contracts/grid/modules/WorkerRegistry.sol:WorkerRegistry methodIdentifiers)
SELECTORS=(
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

echo "1) Deploy the new WorkerRegistry implementation..."
FACET=$(forge create contracts/grid/modules/WorkerRegistry.sol:WorkerRegistry \
  --rpc-url "$RPC" $HWFLAG --broadcast --json | python3 -c 'import sys,json;print(json.load(sys.stdin)["deployedTo"])')
echo "   New WorkerRegistry impl: $FACET"

echo "2) Classify each selector: already live -> REPLACE, otherwise -> ADD..."
REPLACE=()
ADD=()
for s in "${SELECTORS[@]}"; do
  cur=$(cast call "$GRID" 'moduleAddress(bytes4)(address)' "$s" --rpc-url "$RPC")
  if [ "$(echo "$cur" | tr '[:upper:]' '[:lower:]')" = "$ZERO" ]; then
    ADD+=("$s")
    echo "   ADD     $s"
  else
    REPLACE+=("$s")
    echo "   REPLACE $s (was $cur)"
  fi
done

# Build the cut tuple array: (address,uint8 action,bytes4[] selectors)[]
# action: 0=Add, 1=Replace, 2=Remove
join() { local IFS=,; echo "$*"; }
CUTS=()
if [ ${#REPLACE[@]} -gt 0 ]; then
  CUTS+=("($FACET,1,[$(join "${REPLACE[@]}")])")
fi
if [ ${#ADD[@]} -gt 0 ]; then
  CUTS+=("($FACET,0,[$(join "${ADD[@]}")])")
fi
CUT_ARG="[$(join "${CUTS[@]}")]"

echo "3) updateModules with cut: $CUT_ARG"
cast send "$GRID" \
  "updateModules((address,uint8,bytes4[])[],address,bytes)" \
  "$CUT_ARG" \
  "$ZERO" \
  0x \
  --rpc-url "$RPC" $HWFLAG

echo "4) Verify every selector now resolves to the new facet:"
ok=1
for s in "${SELECTORS[@]}"; do
  got=$(cast call "$GRID" 'moduleAddress(bytes4)(address)' "$s" --rpc-url "$RPC")
  if [ "$(echo "$got" | tr '[:upper:]' '[:lower:]')" = "$(echo "$FACET" | tr '[:upper:]' '[:lower:]')" ]; then
    echo "   OK   $s -> $got"
  else
    echo "   FAIL $s -> $got (expected $FACET)"
    ok=0
  fi
done
[ "$ok" = 1 ] && echo "Done. WorkerRegistry upgraded." || { echo "Verification failed."; exit 1; }
echo
echo "Next: grant SLASHER_ROLE to the grid enforcement key (see header), and"
echo "optionally setUnbondingPeriod / setMinBond."
