# Audit Package Scripts

This folder contains interaction scripts for auditors to test and verify deployed contracts.

## Requirements

```bash
npm install  # Install ethers v6 (already configured in package.json)
```

## Available Scripts

### 1. interact-aipg-token.js

**Purpose**: Read-only interaction with the deployed AIPGTokenV2 contract on Base Mainnet.

**Features:**
- Check token name, symbol, decimals
- View total supply and max supply (cap)
- Check if contract is paused
- View role configuration (DEFAULT_ADMIN_ROLE, MINTER_ROLE, PAUSER_ROLE)
- Check balance and roles for specific addresses

**Usage:**

```bash
# Check mainnet contract (default)
node scripts/interact-aipg-token.js

# Check testnet contract
node scripts/interact-aipg-token.js testnet

# Check specific address balance on mainnet
node scripts/interact-aipg-token.js mainnet 0xYourAddressHere

# Check specific address balance on testnet
node scripts/interact-aipg-token.js testnet 0xYourAddressHere
```

**Example Output:**

```
=== AIPGTokenV2 Contract Interaction ===

Network: Base Mainnet
RPC: https://mainnet.base.org
Contract: 0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608

📊 Token Information:
  Name: AI Power Grid
  Symbol: AIPG
  Decimals: 18
  Total Supply: 15016680.367528 AIPG
  Cap (Max Supply): 150000000.0 AIPG
  Paused: ✅ NO

🔑 Role Configuration:
  DEFAULT_ADMIN_ROLE: 0x0000000000000000000000000000000000000000000000000000000000000000
  MINTER_ROLE: 0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6
  PAUSER_ROLE: 0x65d7a28e3265b37a6474929f336521b332c1681b933f6cb9f3376673440d862a

💰 Address Information:
  Address: 0x27741E64d0Bcd5D458638109779d69493D8D9a7e
  Balance: 0.0 AIPG

  Roles:
    DEFAULT_ADMIN_ROLE: ❌ NO
    MINTER_ROLE: ✅ YES
    PAUSER_ROLE: ❌ NO

✅ Success! Contract is accessible and responding.
```

**Notes:**
- This script performs read-only operations and does not require a private key
- No transactions are sent, so no gas fees are incurred
- Safe to run against mainnet contracts

## Networks

### Base Mainnet
- **Chain ID**: 8453
- **RPC URL**: https://mainnet.base.org
- **AIPGTokenV2**: `0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608`

### Base Sepolia (Testnet)
- **Chain ID**: 84532
- **RPC URL**: https://sepolia.base.org
- **AIPGTokenV2**: `0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608` (same vanity address)

## Security Notes

- All scripts use read-only operations by default
- No private keys are required for basic interaction
- Scripts connect to public RPC endpoints
- No sensitive data is logged or stored

## Troubleshooting

### Connection Issues
If you encounter RPC connection issues:
```bash
# Try alternative RPC URLs
export BASE_RPC_URL=https://base.meowrpc.com
node scripts/interact-aipg-token.js
```

### Rate Limiting
Public RPCs may rate limit. If you encounter issues:
- Add delays between calls
- Use your own RPC endpoint (Alchemy, Infura, etc.)
- Retry after a few seconds

## Adding New Scripts

To add a new interaction script:

1. Create a new `.js` file in this folder
2. Use the same ethers v6 pattern as `interact-aipg-token.js`
3. Add usage instructions to this README
4. Update `package.json` scripts if needed

Example template:

```javascript
const { ethers } = require('ethers');

async function main() {
  const provider = new ethers.JsonRpcProvider('https://mainnet.base.org');
  const abi = ['function yourFunction() view returns (uint256)'];
  const contract = new ethers.Contract('0xYourContract', abi, provider);
  
  try {
    const result = await contract.yourFunction();
    console.log('Result:', result);
  } catch (error) {
    console.error('Error:', error.message);
  }
}

if (require.main === module) {
  main().catch(console.error);
}
```

## Related Documentation

- `/docs/ADDRESSES.md` - All deployed contract addresses
- `/docs/EMISSIONS_CONTROLLER.md` - EmissionsControllerV2 documentation
- `/docs/GRIDNFT.md` - GridNFT documentation
- `/AUDIT_SCOPE.md` - Primary audit scope and priorities
