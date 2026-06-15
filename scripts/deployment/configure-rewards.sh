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

# ── EDIT THESE (plain AIPG amounts — no wei, no zeros) ──
DEPOSIT_AIPG=${DEPOSIT_AIPG:-0}          # AIPG to seed the pool, e.g. 100000
ALLOCATION_AIPG=${ALLOCATION_AIPG:-0}    # AIPG released per period (day), e.g. 500
REPORTER_BOT=${REPORTER_BOT:-}           # settlement bot hot-wallet address

[ "$DEPOSIT_AIPG" = "0" ] && { echo "Set DEPOSIT_AIPG / ALLOCATION_AIPG / REPORTER_BOT first."; exit 1; }

# AIPG is 18-decimals, so on-chain amounts are AIPG * 1e18. cast does the zeros.
DEPOSIT_WEI=$(cast to-wei "$DEPOSIT_AIPG" ether)
ALLOCATION_WEI=$(cast to-wei "$ALLOCATION_AIPG" ether)
REPORTER_ROLE=$(cast keccak "REPORTER_ROLE")
echo "Depositing $DEPOSIT_AIPG AIPG ($DEPOSIT_WEI base units); allocation $ALLOCATION_AIPG AIPG/period."

echo "1) approve($GRID, $DEPOSIT_AIPG AIPG) on AIPG..."
cast send "$AIPG" "approve(address,uint256)" "$GRID" "$DEPOSIT_WEI" --rpc-url "$RPC" $HWFLAG

echo "2) depositRewards($DEPOSIT_AIPG AIPG)..."
cast send "$GRID" "depositRewards(uint256)" "$DEPOSIT_WEI" --rpc-url "$RPC" $HWFLAG

echo "3) setPeriodAllocation($ALLOCATION_AIPG AIPG)..."
cast send "$GRID" "setPeriodAllocation(uint256,string)" "$ALLOCATION_WEI" "launch" --rpc-url "$RPC" $HWFLAG

if [ -n "$REPORTER_BOT" ]; then
  echo "4) grantRole(REPORTER_ROLE, $REPORTER_BOT)..."
  cast send "$GRID" "grantRole(bytes32,address)" "$REPORTER_ROLE" "$REPORTER_BOT" --rpc-url "$RPC" $HWFLAG
fi

echo "Pool balance: $(cast call "$GRID" 'poolBalance()(uint256)' --rpc-url "$RPC")"
echo "Allocation:   $(cast call "$GRID" 'periodAllocation()(uint256)' --rpc-url "$RPC")"
echo "Done. Start the settlement bot (SETTLEMENT_DRY_RUN=0 once you trust it)."
