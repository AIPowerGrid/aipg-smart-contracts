# Scripts

Verification and hardware-wallet deployment scripts for contracts on Base Mainnet.

## Setup

```bash
git submodule update --init
npm install
```

The Foundry dependencies are pinned top-level submodules. Their optional nested
test submodules are not required by this repository.

## interact-aipg-token.js

Read-only interaction with AIPGTokenV2 contract.

## WorkerRegistry bonding candidate

`deployment/deploy-worker-bonding-facet.sh` is the prepare-first deployment
runbook for the **review candidate** WorkerRegistry upgrade. The upgrade is not
deployed. Its default mode builds and tests the exact checkout, validates all 16
selectors against both the compiler and `cast`, and classifies the live selector
cut without signing or broadcasting:

```bash
RPC=https://mainnet.base.org \
  ./scripts/deployment/deploy-worker-bonding-facet.sh --prepare
```

The script refuses a selector owned by an unexpected facet. `--send` requires a
clean reviewed commit, `CONFIRM=YES`, Base mainnet, and a Ledger or Trezor. It
verifies deployed runtime bytecode. If the Diamond owner is a Safe or other
contract, it stops after deployment and prints the target/value/calldata for an
explicit Safe review; it does not attempt to bypass contract ownership. After
execution, `--verify` requires the pre-cut `totalBonded` value and proves exact
runtime bytecode, all selector routes, and preserved bond accounting:

```bash
EXPECTED_FACET=0x... EXPECTED_TOTAL_BONDED=0 \
  ./scripts/deployment/deploy-worker-bonding-facet.sh --verify
```

The script deliberately does not grant `SLASHER_ROLE` or change the cooldown or
minimum bond. Do not run `--send` until the contract PR, independent audit, Safe
transaction, rollback/incident plan, and validator bond-sync design are approved.

**Usage:**

```bash
# Check mainnet contract
node scripts/interact-aipg-token.js

# Check testnet contract
node scripts/interact-aipg-token.js testnet

# Check specific address balance on mainnet
node scripts/interact-aipg-token.js mainnet 0xYourAddressHere

# Check specific address balance on testnet
node scripts/interact-aipg-token.js testnet 0xYourAddressHere
```

**Verifies:**
- Token name, symbol, decimals
- Total supply and max supply cap
- Contract pause status
- Role configuration (DEFAULT_ADMIN, MINTER, PAUSER)
- Specific address balances and roles

**Example Output:**

```
=== AIPGTokenV2 Contract Interaction ===

Network: Base Mainnet
Contract: 0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608

📊 Token Information:
  Name: AI Power Grid
  Symbol: AIPG
  Decimals: 18
  Total Supply: 150,000,000 AIPG
  Cap (Max Supply): 150,000,000 AIPG
  Paused: ✅ NO

🔑 Role Configuration:
  DEFAULT_ADMIN_ROLE: 0x0000...
  MINTER_ROLE: 0x9f2d...
  PAUSER_ROLE: 0x65d7...

💰 Address: 0x27741E64d0Bcd5D458638109779d69493D8D9a7e
  Balance: 1,234,567.89 AIPG
  Roles: [MINTER_ROLE]

✅ Success! Contract is accessible.
```

**Notes:**
- Read-only operations only
- No private keys required
- No gas fees
- Safe for mainnet

## ACE-Step Recipe Registration

`deployment/register-ace-step-recipe.sh` canonicalizes the governed ACE-Step
recipe embedded in Worker Profile V1 and verifies its SHA-256 commitment. Its
default mode is offline and does not contact a wallet:

```bash
scripts/deployment/register-ace-step-recipe.sh --prepare
```

After reviewing the printed root, register it through the live Grid Diamond
with a hardware wallet:

```bash
scripts/deployment/register-ace-step-recipe.sh --send
```

The send path requires Base Mainnet, checks the live workflow-size cap, and is
idempotent only when the existing recipe bytes, root, metadata, and permissions
match exactly. Set `HWFLAG=--trezor` to use a Trezor instead of the default
Ledger. Raw private keys are intentionally unsupported.

## Reward Bond-Reserve Upgrade

`deployment/deploy-reward-facets.sh` upgrades RewardPool and PaymentRouter together so reward
claims cannot consume AIPG held as worker bonds. The default mode compiles, runs the contract
suite, validates every selector, and checks live accounting without signing:

```bash
scripts/deployment/deploy-reward-facets.sh --prepare
```

The `--send` path requires `CONFIRM=YES` and a clean reviewed commit. It deploys both facets with
Ledger or Trezor, verifies exact runtime bytecode, and prints one atomic Safe transaction when
the Diamond owner is a contract. It does not replace DenReporter or change roles, balances,
period settings, or WorkerRegistry. After the Safe executes, verify both facet addresses:

```bash
EXPECTED_RP_FACET=0x... EXPECTED_PR_FACET=0x... \
  scripts/deployment/deploy-reward-facets.sh --verify
```

Do not deploy the cooldown-backed WorkerRegistry until this reserve guard is live and verified.

## GridCatalogV2

The V2 catalog is not deployed. Prepare a deterministic deployment plan with
explicit role addresses:

```bash
export CATALOG_ADMIN=0xYourBaseSafe
export CATALOG_REGISTRAR=0xRegistrar
export CATALOG_PAUSER=0xPauser
export CATALOG_NFT_APPROVER=0xNftApprover
export CATALOG_DEPLOYER=0xLedgerDeployer
scripts/deployment/deploy-grid-catalog-v2.sh --prepare
```

The `--send` path additionally requires `BASE_RPC_URL`, verifies the chain ID,
requires four distinct role addresses, requires the Base mainnet admin to be a
deployed contract, accepts only Ledger or Trezor signing, and refuses dirty
source or dependency state. It fingerprints the compiler, dependency commits,
creation bytecode, and runtime bytecode before signing, then verifies the
receipt, exact deployed runtime, roles, and empty state after deployment.
Do not invoke it until the contract audit and Safe plan are approved.

Registration calldata is derived from reviewed files rather than hand-entered:

```bash
python3 scripts/catalog/build-plan.py catalog/examples/registration-plan.json
```

The example output is never a production registration plan. Production files
must carry independently verified artifact hashes and immutable content URIs.

## Networks

### Base Mainnet
- **Chain ID**: 8453
- **RPC**: https://mainnet.base.org
- **AIPGTokenV2**: `0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608`

### Base Sepolia (Testnet)
- **Chain ID**: 84532
- **RPC**: https://sepolia.base.org
- **AIPGTokenV2**: `0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608`

## Security

- Verification scripts are read-only and require no private keys.
- Deployment scripts default to prepare/dry-run modes and use hardware wallets
  for broadcasts.
- Never add raw private keys to environment variables, command lines, or files.
- Public RPC endpoints are suitable for reads; use a reviewed provider for
  reliable mainnet writes.
- No sensitive data is intentionally logged.

## Troubleshooting

**RPC Connection Issues:**
```bash
export BASE_RPC_URL=https://base.meowrpc.com
node scripts/interact-aipg-token.js
```

**Rate Limiting:**
- Try alternative RPC endpoints
- Use your own RPC (Alchemy, Infura, etc.)
- Retry after delays

## Related Docs

- `docs/ADDRESSES.md` - All deployed addresses
- `docs/GRID_CATALOG_V2.md` - V2 catalog trust boundary and deployment gates
- `AUDIT_SCOPE.md` - Audit priorities
- `docs/STAKING.md` - Staking documentation
