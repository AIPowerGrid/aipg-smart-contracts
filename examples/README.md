# Examples

Reference implementations for interacting with AIPG contracts.

## Available Examples

### read-nft-and-recreate.js
Read GridNFT metadata from chain and recreate the parameters.

**Usage:**
```bash
node read-nft-and-recreate.js <tokenId>
```

### nft-generation-framework.js
Complete framework for generating AI art NFTs with validation.

**Features:**
- Model selection
- Parameter validation
- Recipe integration
- Error handling

### mint-fun-nft-with-forced-params.js
Example for minting NFTs with specific parameters.

### test-modelregistry-sdk.js
Test ModelRegistry SDK functionality.

## Quick Start

1. Review the example script
2. Install dependencies: `npm install`
3. Set network configuration
4. Run the example

## Common Patterns

### Reading Contract Data

```javascript
const { ethers } = require('ethers');

const provider = new ethers.JsonRpcProvider('https://mainnet.base.org');
const contract = new ethers.Contract(address, abi, provider);

const data = await contract.yourFunction();
console.log(data);
```

### Writing Transactions

Requires private key and signer setup. See examples for patterns.

## Networks

- **Base Mainnet**: Chain ID 8453
- **Base Sepolia**: Chain ID 84532

## Related Documentation

- `/sdk/` - Available SDKs
- `/docs/` - Complete documentation
- `/AUDIT_SCOPE.md` - Audit priorities
