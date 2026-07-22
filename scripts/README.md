# Scripts

Verification and hardware-wallet deployment scripts for contracts on Base Mainnet.

## Setup

```bash
npm install
```

## interact-aipg-token.js

Read-only interaction with AIPGTokenV2 contract.

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

## GridCatalogV2

The V2 catalog is not deployed. Prepare a deterministic deployment plan with
explicit role addresses:

```bash
export CATALOG_ADMIN=0xYourBaseSafe
export CATALOG_REGISTRAR=0xRegistrar
export CATALOG_PAUSER=0xPauser
export CATALOG_NFT_APPROVER=0xNftApprover
scripts/deployment/deploy-grid-catalog-v2.sh --prepare
```

The `--send` path additionally requires `BASE_RPC_URL`, verifies the chain ID,
requires four distinct role addresses, requires the Base mainnet admin to be a
deployed contract, accepts only Ledger or Trezor signing, and verifies roles
plus empty state after deployment.
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
