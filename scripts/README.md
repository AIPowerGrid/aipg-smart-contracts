# Scripts

Verification scripts for deployed contracts on Base Mainnet.

## Setup

```bash
npm install
```

## interact-aipg-token.js

Read-only interaction with AIPGTokenV2 contract.

## deployment/deploy-grid-security-upgrade.sh

Preferred mainnet path for the Grid reward/bonding security upgrade. It runs the
offline Foundry suite, deploys only the changed `PaymentRouter` and
`WorkerRegistry` facets, classifies selectors as ADD or REPLACE, applies one
atomic `updateModules` cut, and verifies every selector routes to the new facet.

```bash
CONFIRM=YES RPC=https://mainnet.base.org HWFLAG=--ledger \
  ./scripts/deployment/deploy-grid-security-upgrade.sh
```

Use `SKIP_TESTS=1` only after the exact commit has already passed locally or in
CI. If local Foundry RPC calls hit the macOS proxy panic, run the deploy from a
Linux shell/CI runner with the same hardware-wallet or multisig signing process.

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

- Read-only operations only
- No private keys required
- Public RPC endpoints
- No sensitive data logged

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
- `AUDIT_SCOPE.md` - Audit priorities
- `docs/STAKING.md` - Staking documentation
