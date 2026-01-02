# JavaScript SDKs

Helper SDKs for interacting with AI Power Grid contracts.

## Available SDKs

### aipg-nft-sdk.js
GridNFT contract interactions for reading and creating AI-generated NFTs.

### modelregistry-sdk.js
Model registry interactions for querying AI models and constraints.

### recipevault-sdk.js
Recipe vault interactions for storing and retrieving ComfyUI workflows via the Grid Diamond.

See `RECIPEVAULT_README.md` for full documentation and examples.

## Installation

```bash
npm install ethers@6
```

## Usage

```javascript
const { ethers } = require('ethers');

// Example: Query token balance
const provider = new ethers.JsonRpcProvider('https://mainnet.base.org');
const token = new ethers.Contract(
  '0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608',
  ['function balanceOf(address) view returns (uint256)'],
  provider
);

const balance = await token.balanceOf('0xYourAddress');
console.log(ethers.formatEther(balance), 'AIPG');
```

## Mainnet Addresses

| Contract | Address |
|----------|---------|
| AIPGTokenV2 | `0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608` |
| StakingVault | `0x3ED14A6D5A48614D77f313389611410d38fd8277` |
| Grid Diamond | `0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609` |
| RecipeVault (module) | `0xddEC9d082FB2B45815Ee104947bfd556d4BD0aa1` |

See `docs/ADDRESSES.md` for complete list.

## Network Configuration

```javascript
const networks = {
  mainnet: {
    chainId: 8453,
    rpc: 'https://mainnet.base.org'
  },
  testnet: {
    chainId: 84532,
    rpc: 'https://sepolia.base.org'
  }
};
```

## Examples

See `sdk-example.js` for complete examples and patterns.

## Notes

- All SDKs use ethers v6
- Read-only by default
- Add private key for signing transactions
- No secrets in repository
