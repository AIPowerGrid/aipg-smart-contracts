#!/usr/bin/env bash
# Configure the reward system after deploy-reward-facets.sh. Admin hardware wallet.
#
#   1. Approve the diamond to pull AIPG, then depositRewards() into the pool.
#   2. setPeriodAllocation() — AIPG released per period (daily by default).
#   3. Grant REPORTER_ROLE to the settlement bot's hot wallet (so it can post
#      daily den roots autonomously; it never holds funds — claims pull from the
#      pool). Until validators/co-signing land, a fake report is bounded to one
#      period's allocation.
#
# Edit the values below, then run.  HWFLAG=--ledger by default.
set -euo pipefail

GRID=0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609
AIPG=0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608
RPC=${RPC:-https://mainnet.base.org}
HWFLAG=${HWFLAG:---ledger}

# ── EDIT THESE ──
DEPOSIT_WEI=${DEPOSIT_WEI:-0}            # AIPG to seed the pool (18 dec). e.g. 1000000 ether
ALLOCATION_WEI=${ALLOCATION_WEI:-0}      # AIPG released per period. e.g. 4080 ether
REPORTER_BOT=${REPORTER_BOT:-}           # settlement bot hot-wallet address

[ "$DEPOSIT_WEI" = "0" ] && { echo "Set DEPOSIT_WEI / ALLOCATION_WEI / REPORTER_BOT first."; exit 1; }

# REPORTER_ROLE = keccak256("REPORTER_ROLE")
REPORTER_ROLE=$(cast keccak "REPORTER_ROLE")

echo "1) approve($GRID, $DEPOSIT_WEI) on AIPG..."
cast send "$AIPG" "approve(address,uint256)" "$GRID" "$DEPOSIT_WEI" --rpc-url "$RPC" $HWFLAG

echo "2) depositRewards($DEPOSIT_WEI)..."
cast send "$GRID" "depositRewards(uint256)" "$DEPOSIT_WEI" --rpc-url "$RPC" $HWFLAG

echo "3) setPeriodAllocation($ALLOCATION_WEI)..."
cast send "$GRID" "setPeriodAllocation(uint256,string)" "$ALLOCATION_WEI" "launch" --rpc-url "$RPC" $HWFLAG

if [ -n "$REPORTER_BOT" ]; then
  echo "4) grantRole(REPORTER_ROLE, $REPORTER_BOT)..."
  cast send "$GRID" "grantRole(bytes32,address)" "$REPORTER_ROLE" "$REPORTER_BOT" --rpc-url "$RPC" $HWFLAG
fi

echo "Pool balance: $(cast call "$GRID" 'poolBalance()(uint256)' --rpc-url "$RPC")"
echo "Allocation:   $(cast call "$GRID" 'periodAllocation()(uint256)' --rpc-url "$RPC")"
echo "Done. Start the settlement bot (SETTLEMENT_DRY_RUN=0 once you trust it)."
