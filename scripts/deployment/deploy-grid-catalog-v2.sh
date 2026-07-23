#!/usr/bin/env bash
# Prepare or deploy the standalone GridCatalogV2 with hardware-wallet signing.
# Default mode is read-only. No raw private-key path is supported.
set -euo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/../.." && pwd)
MODE=${1:---prepare}
RPC=${BASE_RPC_URL:-}
HWFLAG=${HWFLAG:---ledger}
EXPECTED_CHAIN_ID=${EXPECTED_CHAIN_ID:-8453}

case "$MODE" in
  --prepare|--send) ;;
  *) echo "Usage: $0 [--prepare|--send]" >&2; exit 2 ;;
esac

case "$HWFLAG" in
  --ledger|--trezor) ;;
  *) echo "HWFLAG must be --ledger or --trezor" >&2; exit 2 ;;
esac

for command in forge cast jq shasum; do
  command -v "$command" >/dev/null || { echo "$command is required" >&2; exit 1; }
done

require_address() {
  local name=$1
  local value=${!name:-}
  if ! [[ "$value" =~ ^0x[0-9a-fA-F]{40}$ ]] || [ "$value" = "0x0000000000000000000000000000000000000000" ]; then
    echo "$name must be an explicit nonzero address" >&2
    exit 1
  fi
}

require_address CATALOG_ADMIN
require_address CATALOG_REGISTRAR
require_address CATALOG_PAUSER
require_address CATALOG_NFT_APPROVER
require_address CATALOG_DEPLOYER

ADMIN_NORMALIZED=$(cast to-check-sum-address "$CATALOG_ADMIN")
REGISTRAR_NORMALIZED=$(cast to-check-sum-address "$CATALOG_REGISTRAR")
PAUSER_NORMALIZED=$(cast to-check-sum-address "$CATALOG_PAUSER")
NFT_APPROVER_NORMALIZED=$(cast to-check-sum-address "$CATALOG_NFT_APPROVER")
if [ "$ADMIN_NORMALIZED" = "$REGISTRAR_NORMALIZED" ] \
  || [ "$ADMIN_NORMALIZED" = "$PAUSER_NORMALIZED" ] \
  || [ "$ADMIN_NORMALIZED" = "$NFT_APPROVER_NORMALIZED" ] \
  || [ "$REGISTRAR_NORMALIZED" = "$PAUSER_NORMALIZED" ] \
  || [ "$REGISTRAR_NORMALIZED" = "$NFT_APPROVER_NORMALIZED" ] \
  || [ "$PAUSER_NORMALIZED" = "$NFT_APPROVER_NORMALIZED" ]; then
  echo "Catalog governance roles must use four distinct addresses" >&2
  exit 1
fi

cd "$REPO_ROOT"
forge build contracts/GridCatalogV2.sol --skip test --skip script >/dev/null
CREATION_BYTECODE=$(forge inspect GridCatalogV2 bytecode)
RUNTIME_BYTECODE=$(forge inspect GridCatalogV2 deployedBytecode)
GIT_COMMIT=$(git rev-parse HEAD)
SOLC_VERSION=$(forge config --json | jq -er '.solc')
OZ_COMMIT=$(git -C lib/openzeppelin-contracts rev-parse HEAD)
FORGE_STD_COMMIT=$(git -C lib/forge-std rev-parse HEAD)

echo "GridCatalogV2 deployment plan"
echo "  expected chain: $EXPECTED_CHAIN_ID"
echo "  deployer:       $CATALOG_DEPLOYER"
echo "  admin:          $CATALOG_ADMIN"
echo "  registrar:      $CATALOG_REGISTRAR"
echo "  pauser:         $CATALOG_PAUSER"
echo "  NFT approver:   $CATALOG_NFT_APPROVER"
echo "  signer:         $HWFLAG"
echo "  git commit:     $GIT_COMMIT"
echo "  solc:           $SOLC_VERSION"
echo "  OpenZeppelin:   $OZ_COMMIT"
echo "  forge-std:      $FORGE_STD_COMMIT"
echo "  source digest:  $(shasum -a 256 contracts/GridCatalogV2.sol | awk '{print $1}')"
echo "  creation hash:  $(cast keccak "$CREATION_BYTECODE")"
echo "  runtime hash:   $(cast keccak "$RUNTIME_BYTECODE")"

if [ "$MODE" = "--prepare" ]; then
  echo "Prepared only. Set BASE_RPC_URL and rerun with --send after review."
  exit 0
fi

[ -n "$RPC" ] || { echo "BASE_RPC_URL is required for --send" >&2; exit 1; }
if [ -n "$(git status --porcelain --untracked-files=normal)" ]; then
  echo "Refusing deployment from a dirty worktree" >&2
  exit 1
fi
if git submodule status lib/openzeppelin-contracts lib/forge-std | grep -Eq '^[+-U]'; then
  echo "Refusing deployment with missing or modified submodules" >&2
  exit 1
fi
CHAIN_ID=$(cast chain-id --rpc-url "$RPC")
[ "$CHAIN_ID" = "$EXPECTED_CHAIN_ID" ] || {
  echo "Refusing chain ID $CHAIN_ID; expected $EXPECTED_CHAIN_ID" >&2
  exit 1
}

# Mainnet administration must be a deployed Safe or another reviewed contract,
# never an unattended EOA. Non-mainnet rehearsals may opt out explicitly.
if [ "$CHAIN_ID" = "8453" ] || [ "${REQUIRE_ADMIN_CONTRACT:-1}" = "1" ]; then
  ADMIN_CODE=$(cast code "$CATALOG_ADMIN" --rpc-url "$RPC")
  [ "$ADMIN_CODE" != "0x" ] || {
    echo "CATALOG_ADMIN has no bytecode; use a deployed Safe or explicitly set REQUIRE_ADMIN_CONTRACT=0 for a testnet rehearsal" >&2
    exit 1
  }
fi

echo "Deploying with the hardware wallet..."
CREATE_ARGS=(
  contracts/GridCatalogV2.sol:GridCatalogV2
  --from "$CATALOG_DEPLOYER"
  --rpc-url "$RPC"
  "$HWFLAG"
  --broadcast
  --json
  --constructor-args
  "$CATALOG_ADMIN"
  "$CATALOG_REGISTRAR"
  "$CATALOG_PAUSER"
  "$CATALOG_NFT_APPROVER"
)
DEPLOYMENT=$(forge create "${CREATE_ARGS[@]}")
ADDRESS=$(jq -er '.deployedTo' <<<"$DEPLOYMENT")
TX_HASH=$(jq -er '.transactionHash' <<<"$DEPLOYMENT")
RECEIPT=$(cast receipt "$TX_HASH" --rpc-url "$RPC" --json)
jq -e '.status == "0x1" or .status == "1"' <<<"$RECEIPT" >/dev/null

echo "Deployed: $ADDRESS"
echo "Tx:       $TX_HASH"
echo "Verifying bytecode, roles, and empty state..."
ACTUAL_RUNTIME=$(cast code "$ADDRESS" --rpc-url "$RPC")
[ "$ACTUAL_RUNTIME" = "$RUNTIME_BYTECODE" ] || {
  echo "Deployed runtime bytecode does not match the locally audited artifact" >&2
  exit 1
}
DEFAULT_ADMIN_ROLE=0x0000000000000000000000000000000000000000000000000000000000000000
REGISTRAR_ROLE=$(cast keccak 'REGISTRAR_ROLE')
PAUSER_ROLE=$(cast keccak 'PAUSER_ROLE')
NFT_APPROVER_ROLE=$(cast keccak 'NFT_APPROVER_ROLE')

[ "$(cast call "$ADDRESS" 'hasRole(bytes32,address)(bool)' "$DEFAULT_ADMIN_ROLE" "$CATALOG_ADMIN" --rpc-url "$RPC")" = "true" ]
[ "$(cast to-check-sum-address "$(cast call "$ADDRESS" 'defaultAdmin()(address)' --rpc-url "$RPC")")" = "$ADMIN_NORMALIZED" ]
[ "$(cast call "$ADDRESS" 'defaultAdminDelay()(uint48)' --rpc-url "$RPC")" = "172800" ]
[ "$(cast call "$ADDRESS" 'hasRole(bytes32,address)(bool)' "$REGISTRAR_ROLE" "$CATALOG_REGISTRAR" --rpc-url "$RPC")" = "true" ]
[ "$(cast call "$ADDRESS" 'hasRole(bytes32,address)(bool)' "$PAUSER_ROLE" "$CATALOG_PAUSER" --rpc-url "$RPC")" = "true" ]
[ "$(cast call "$ADDRESS" 'hasRole(bytes32,address)(bool)' "$NFT_APPROVER_ROLE" "$CATALOG_NFT_APPROVER" --rpc-url "$RPC")" = "true" ]
[ "$(cast call "$ADDRESS" 'modelCount()(uint256)' --rpc-url "$RPC")" = "0" ]
[ "$(cast call "$ADDRESS" 'recipeCount()(uint256)' --rpc-url "$RPC")" = "0" ]

echo "Verification passed. Do not register records until the address, bytecode, and catalog plan are independently reviewed."
