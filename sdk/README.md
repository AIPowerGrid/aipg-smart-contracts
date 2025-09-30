# AIPG SDKs

This folder contains all the JavaScript SDKs for interacting with the AIPG NFT system.

## Available SDKs

### 1. AIPG NFT SDK (`aipg-nft-sdk.js`)
Complete SDK for minting and managing AI art NFTs.

**Features:**
- Approve models and recipes
- Mint NFTs with full parameters
- Read NFT data from chain
- Verify minting success via events

**Usage:**
```javascript
const { AIPGNFTClient } = require('./aipg-nft-sdk');

const client = new AIPGNFTClient({
  rpcUrl: 'https://sepolia.base.org',
  privateKey: 'your-private-key',
  contractAddress: '0xa87Eb64534086e914A4437ac75a1b554A10C9934'
});
```

### 2. ModelRegistry SDK (`modelregistry-sdk.js`)
SDK for managing AI models and their constraints.

**Features:**
- Register new AI models
- Set model constraints (steps, CFG, samplers, schedulers)
- Query available models
- Validate generation parameters

**Usage:**
```javascript
const ModelRegistrySDK = require('./modelregistry-sdk');

const sdk = new ModelRegistrySDK(contractAddress, provider, signer);
```

### 3. RecipeVault SDK (`recipevault-sdk.js`)
SDK for managing ComfyUI workflow recipes.

**Features:**
- Store public/private recipes
- Retrieve recipe metadata
- Manage recipe visibility

**Usage:**
```javascript
const RecipeVaultClient = require('./recipevault-sdk');

const client = new RecipeVaultClient({
  rpcUrl: 'https://sepolia.base.org',
  privateKey: 'your-private-key',
  address: '0x26FAd52658A726927De3331C5F5D01a5b09aC685'
});
```

### 4. SDK Example (`sdk-example.js`)
Complete example showing how to use all SDKs together.

## Contract Addresses

- **GridNFT**: `0xa87Eb64534086e914A4437ac75a1b554A10C9934`
- **RecipeVault**: `0x26FAd52658A726927De3331C5F5D01a5b09aC685`
- **ModelRegistry**: `0xe660455D4A83bbbbcfDCF4219ad82447a831c8A1`

## Network

- **Base Sepolia** (Chain ID: 84532)
- **RPC**: https://sepolia.base.org

## Emissions SDK (Base Sepolia/Mainnet)

Minimal client for calling EmissionsControllerV2.batchMintWorkers and reading config.

Install: uses ethers v6 (already in production package.json).

Example:

```js
const { EmissionsSDK } = require('./emissions-sdk');
const deployment = require('../emissions-deployment.json');

(async () => {
  const sdk = EmissionsSDK.fromDeployment({ deployment, rpcUrl: deployment.RPC })
    .withSigner(process.env.PRIVATE_KEY);

  const cfg = await sdk.getConfig();
  console.log('Config', cfg);

  const workers = [
    '0x1234567890123456789012345678901234567890',
    '0x0987654321098765432109876543210987654321'
  ];
  const amounts = [
    ethers.parseEther('1'),
    ethers.parseEther('0.5')
  ];

  const rec = await sdk.batchMint({
    workers,
    amounts,
    epochId: 5,
    uri: 'ipfs://<manifest_cid>',
    gasPriceGwei: 0.003
  });
  console.log('Mined at', rec.transactionHash);
})();
```

Notes:
- Controller must have MINTER_ROLE on token and REWARD_DISTRIBUTOR_ROLE on vault.
- Use very low gas price on Base (0.002–0.01 gwei typical off-peak).
