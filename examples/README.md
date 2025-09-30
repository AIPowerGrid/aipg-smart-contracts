# Examples and Reference Implementations

This folder contains example scripts and reference implementations for interacting with AI Power Grid contracts.

## 📚 Contents

### NFT Generation Framework

**`nft-generation-framework.js`** - Core framework for deterministic AI art generation

A unified framework that ensures pixel-perfect reproducibility across different AI backends:
- ComfyUI local generation
- Grid API distributed generation
- Parameter validation against blockchain constraints
- Template-based workflow management

**Key Features:**
- Fetch model constraints from blockchain
- Validate generation parameters
- Generate on ComfyUI or Grid API
- Compare outputs for reproducibility testing

**Usage:**
```javascript
const { NFTGenerationFramework } = require('./nft-generation-framework');

const framework = new NFTGenerationFramework({
  comfyUIEndpoint: 'http://localhost:8188',
  gridAPIUrl: 'https://api.aipowergrid.io/api',
  gridAPIKey: 'your-api-key',
  provider: ethersProvider,
  modelShopAddress: '0xYourModelShopAddress',
  templatePath: 'workflow_template.json'
});

// Fetch constraints from blockchain
const constraints = await framework.fetchModelConstraints('flux.1-dev');

// Generate image with parameters
const result = await framework.generateOnComfyUI({
  seed: 42,
  steps: 30,
  cfg_scale: 7.5,
  // ... other params
});
```

### Example Scripts

**Note**: These scripts are reference examples from the testnet deployment. They require:
- Base Sepolia testnet access
- Deployed contract addresses (see `/docs/ADDRESSES.md`)
- Private keys with test ETH
- Additional dependencies (axios, fs, etc.)

#### mint-fun-nft-with-forced-params.js
Example of minting an NFT with complete generation parameters stored on-chain.

Shows:
- Parameter validation
- IPFS metadata upload
- NFT minting with full params
- Event verification

#### read-nft-and-recreate.js
Demonstrates reading NFT parameters from blockchain and recreating the exact image.

Shows:
- Reading on-chain parameters
- Reconstructing workflow from template
- Generating identical output
- Verifying reproducibility

#### test-modelshop-end-to-end.js
End-to-end test of the ModelShop constraint system.

Shows:
- Registering AI models
- Setting parameter constraints
- Validating generation parameters
- Querying model information

## 🔧 Installation

These examples require additional dependencies beyond the base audit package:

```bash
npm install ethers@^6.9.0 axios
```

## ⚠️ Important Notes

1. **These are reference examples only** - They demonstrate patterns and usage but are configured for testnet
2. **Contract addresses are testnet** - Update addresses for mainnet use
3. **Requires external services** - ComfyUI or Grid API access needed for generation
4. **Not audited** - These scripts are for reference and testing purposes only

## 🎯 For Auditors

These examples demonstrate:
- How contracts are intended to be used
- Parameter validation flow
- Integration patterns
- Reproducibility verification

**Focus your audit on the contracts themselves** (`/contracts/` folder), not these example scripts.

## 📖 Related Documentation

- `/docs/GRIDNFT.md` - GridNFT contract documentation
- `/docs/EMISSIONS_CONTROLLER.md` - EmissionsController documentation  
- `/sdk/README.md` - SDK documentation
- `/scripts/README.md` - Interaction scripts for deployed contracts
