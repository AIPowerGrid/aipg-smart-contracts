#!/usr/bin/env bash
# Deploy the reward/settlement facets (RewardPool, DenReporter, PaymentRouter)
# and cut them into the live Grid diamond in one atomic updateModules call.
# Signs with the admin HARDWARE WALLET — no keys touch disk.
#
# After this: configure-rewards.sh (fund pool + allocation + grant reporter).
#
# Usage:  RPC=https://mainnet.base.org ./scripts/deployment/deploy-reward-facets.sh
# Ledger instead of Trezor:  HWFLAG=--ledger ./scripts/deployment/deploy-reward-facets.sh
set -euo pipefail

GRID=0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609
RPC=${RPC:-https://mainnet.base.org}
HWFLAG=${HWFLAG:---ledger}
ZERO=0x0000000000000000000000000000000000000000

# Selectors (verified from compiled artifacts).
RP_SELECTORS=(0x988e6595 0x8bdf67f2 0xfe9e071f 0x6b936a4c 0x96365d44 0x740995a7 0x1c5633d7 0xff50abdc 0x1357e1dc)
DR_SELECTORS=(0x4e7f9b19 0x89b80361 0xe0abca03)
PR_SELECTORS=(0x172bd6de 0x0d1fd3f4 0xd2ef0795 0xa6fe1660)

dep() { forge create "contracts/grid/modules/$1.sol:$1" --rpc-url "$RPC" $HWFLAG --broadcast --json \
        | python3 -c 'import sys,json;print(json.load(sys.stdin)["deployedTo"])'; }

join() { local IFS=,; echo "$*"; }

CUTS=()
classify_selectors() {
  local label=$1
  local facet=$2
  shift 2

  local replace=()
  local add=()
  local selector
  local current
  for selector in "$@"; do
    current=$(cast call "$GRID" 'moduleAddress(bytes4)(address)' "$selector" --rpc-url "$RPC")
    if [ "$(echo "$current" | tr '[:upper:]' '[:lower:]')" = "$ZERO" ]; then
      add+=("$selector")
      echo "   $label ADD     $selector"
    else
      replace+=("$selector")
      echo "   $label REPLACE $selector (was $current)"
    fi
  done

  if [ ${#replace[@]} -gt 0 ]; then
    CUTS+=("($facet,1,[$(join "${replace[@]}")])")
  fi
  if [ ${#add[@]} -gt 0 ]; then
    CUTS+=("($facet,0,[$(join "${add[@]}")])")
  fi
}

echo "1) Deploy facets..."
RP_ADDR=$(dep RewardPool);    echo "   RewardPool    $RP_ADDR"
DR_ADDR=$(dep DenReporter);   echo "   DenReporter   $DR_ADDR"
PR_ADDR=$(dep PaymentRouter); echo "   PaymentRouter $PR_ADDR"

echo "2) Classify selectors as ADD or REPLACE..."
classify_selectors RewardPool "$RP_ADDR" "${RP_SELECTORS[@]}"
classify_selectors DenReporter "$DR_ADDR" "${DR_SELECTORS[@]}"
classify_selectors PaymentRouter "$PR_ADDR" "${PR_SELECTORS[@]}"

CUT_ARG="[$(join "${CUTS[@]}")]"

echo "3) updateModules with cut: $CUT_ARG"
cast send "$GRID" \
  "updateModules((address,uint8,bytes4[])[],address,bytes)" \
  "$CUT_ARG" \
  "$ZERO" 0x \
  --rpc-url "$RPC" $HWFLAG

echo "4) Verify a representative selector from each facet resolves:"
for s in 0x8bdf67f2 0xe0abca03 0x0d1fd3f4; do
  echo "   $s -> $(cast call "$GRID" 'moduleAddress(bytes4)(address)' "$s" --rpc-url "$RPC")"
done
echo "Done. Reward selectors are now routed to the freshly deployed facets."
echo "Next: ./scripts/deployment/configure-rewards.sh"
