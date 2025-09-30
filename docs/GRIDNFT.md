# GridNFT

## Overview

`GridNFT` is an ERC721 NFT contract for verifiable AI-generated art on the AI Power Grid. It stores complete generation parameters on-chain, enabling pixel-perfect reproducibility of AI artwork across different platforms and hardware.

**Status**: Testnet only (Base Sepolia)  
**Deployment**: Not yet deployed to mainnet - awaiting future audit round

## Key Features

### 1. Blockchain-Verifiable AI Art
- All generation parameters stored on-chain
- Pixel-perfect reproducibility across platforms (ComfyUI, Grid API)
- Deterministic generation with cryptographic verification

### 2. Three-Contract Architecture
- **GridNFT**: Stores NFT metadata and generation parameters
- **RecipeVault**: Reusable workflow templates with placeholders
- **ModelRegistry**: AI model constraints and validation rules

### 3. Worker Incentives
- 75% of mint fees go directly to GPU workers
- 25% goes to protocol treasury
- Quality-based incentives for better results

### 4. Comprehensive Parameter Storage
Each NFT stores:
- Seed, steps, CFG scale, sampler, scheduler
- Model ID and workflow recipe ID
- Target worker address (for hardware-specific generation)
- Image dimensions and IPFS metadata

## Architecture

```
GridNFT
├── mintWithParameters()      # Mint NFT with full generation params
├── getGenerationParams()     # Retrieve params for reproducibility
├── tokenURI()                # IPFS metadata URI
├── approveModel()            # Whitelist AI models
├── approveRecipe()           # Whitelist workflow recipes
└── emergencyWithdraw()       # Emergency fund recovery
```

## Core Functions

### mintWithParameters

Mints a new NFT with complete generation parameters for reproducibility.

```solidity
function mintWithParameters(
    address to,
    uint256 seed,
    uint256 steps,
    uint256 cfgScale,
    string calldata sampler,
    string calldata scheduler,
    uint256 width,
    uint256 height,
    uint256 modelId,
    uint256 recipeId,
    address targetWorker,
    string calldata metadataURI
) external payable returns (uint256 tokenId)
```

**Parameters:**
- `to`: NFT recipient address
- `seed`: Random seed for reproducibility
- `steps`: Number of diffusion steps
- `cfgScale`: Classifier-Free Guidance scale (multiplied by 100, e.g., 7.5 = 750)
- `sampler`: Sampling method (e.g., "euler", "dpmpp_2m")
- `scheduler`: Noise schedule (e.g., "normal", "karras")
- `width`, `height`: Image dimensions
- `modelId`: Reference to approved model in ModelRegistry
- `recipeId`: Reference to workflow template in RecipeVault
- `targetWorker`: GPU worker who generated the image
- `metadataURI`: IPFS URI for image and additional metadata

**Payment Flow:**
- Mint fee split: 75% to worker, 25% to treasury
- Worker receives payment automatically on mint
- Excess payment refunded to minter

**Events:**
```solidity
event NFTMinted(
    uint256 indexed tokenId,
    address indexed owner,
    uint256 seed,
    address targetWorker,
    string metadataURI
);
```

### getGenerationParams

Retrieves all generation parameters for an NFT, enabling reproduction.

```solidity
function getGenerationParams(uint256 tokenId) external view returns (
    uint256 seed,
    uint256 steps,
    uint256 cfgScale,
    string memory sampler,
    string memory scheduler,
    uint256 width,
    uint256 height,
    uint256 modelId,
    uint256 recipeId,
    address targetWorker
)
```

## Generation Parameter Details

### Seed
- **Type**: `uint256`
- **Purpose**: Random seed for deterministic generation
- **Range**: 0 to 2^256-1
- **Notes**: Same seed + params = identical image

### Steps
- **Type**: `uint256`
- **Purpose**: Number of diffusion steps
- **Typical Range**: 20-50 steps
- **Impact**: More steps = higher quality, longer generation time

### CFG Scale
- **Type**: `uint256` (stored as integer, divide by 100 for actual value)
- **Purpose**: Classifier-Free Guidance strength
- **Typical Range**: 1.0 (100) to 15.0 (1500)
- **Common Value**: 7.5 (750)
- **Impact**: Higher = closer to prompt, lower = more creative

### Sampler
- **Type**: `string`
- **Purpose**: Noise sampling algorithm
- **Common Values**:
  - `"euler"`: Fast, stable
  - `"euler_ancestral"`: More random
  - `"dpmpp_2m"`: High quality
  - `"dpmpp_2m_karras"`: Alternative noise schedule

### Scheduler
- **Type**: `string`
- **Purpose**: Noise schedule progression
- **Common Values**:
  - `"normal"`: Standard linear schedule
  - `"karras"`: Non-linear, better quality
  - `"exponential"`: Alternative progression

### Model ID
- **Type**: `uint256`
- **Purpose**: Reference to AI model in ModelRegistry
- **Validation**: Must be approved model
- **Examples**: FLUX.1, Stable Diffusion XL, custom fine-tunes

### Recipe ID
- **Type**: `uint256`
- **Purpose**: Reference to workflow template in RecipeVault
- **Templates**: Reusable ComfyUI workflows
- **Placeholders**: Replaced with actual parameters at generation time

### Target Worker
- **Type**: `address`
- **Purpose**: Specific GPU worker for hardware targeting
- **Benefit**: Consistent generation on same hardware
- **Payment**: Receives 75% of mint fee

## Proven Reproducibility

The GridNFT system has been tested and proven to achieve **pixel-perfect reproducibility**:

### Cross-Platform Testing ✅
- **ComfyUI ↔ Grid API**: 100% perceptual hash match
- **Hamming Distance**: 0/64 bits difference (perfect match)
- **Different Hardware**: Same output across various GPUs
- **Quantized Models**: Even FP8 models maintain determinism

### Verification Methods
```javascript
// Generate on ComfyUI
const comfyImage = await framework.generateOnComfyUI(params);

// Generate on Grid API with same params
const gridImage = await framework.generateOnGridAPI(params, targetWorker);

// Verify pixel-perfect match
const phash1 = await perceptualHash(comfyImage);
const phash2 = await perceptualHash(gridImage);
const distance = hammingDistance(phash1, phash2);

console.log('Match:', distance === 0); // true - perfect match
```

## Integration with Related Contracts

### ModelRegistry
Validates AI model constraints:
```solidity
// Model must be approved
require(modelRegistry.isModelApproved(modelId), "Model not approved");

// Check parameter constraints
ModelRegistry.ModelConstraints memory constraints = 
    modelRegistry.getModelConstraints(modelId);
require(steps >= constraints.minSteps && steps <= constraints.maxSteps);
require(cfgScale >= constraints.minCFG && cfgScale <= constraints.maxCFG);
```

### RecipeVault
Provides reusable workflow templates:
```solidity
// Recipe must be approved
require(recipeVault.isRecipeApproved(recipeId), "Recipe not approved");

// Fetch template workflow
string memory workflow = recipeVault.getRecipeData(recipeId);

// Replace placeholders with actual parameters
workflow = replacePlaceholders(workflow, params);
```

## Usage Example

### Via SDK (JavaScript)

```javascript
const { AIPGNFTClient } = require('./sdk/aipg-nft-sdk');

// Initialize client
const client = new AIPGNFTClient({
  rpcUrl: 'https://sepolia.base.org',
  privateKey: process.env.PRIVATE_KEY,
  contractAddress: '0x7d49b017E824aA47Ca36d74a9377A3c1EFb53ef9'
});

// Mint NFT with parameters
const params = {
  to: '0xYourAddress',
  seed: 42,
  steps: 30,
  cfgScale: 750, // 7.5
  sampler: 'dpmpp_2m_karras',
  scheduler: 'karras',
  width: 1024,
  height: 1024,
  modelId: 1, // FLUX.1
  recipeId: 1,
  targetWorker: '0xWorkerAddress',
  metadataURI: 'ipfs://QmXxx...',
  mintFee: ethers.parseEther('0.01')
};

const tokenId = await client.mintNFT(params);
console.log('Minted NFT #', tokenId);

// Later: retrieve parameters for reproduction
const retrievedParams = await client.getGenerationParams(tokenId);
const regeneratedImage = await generateImage(retrievedParams);
```

### Direct Contract Interaction

```javascript
const { ethers } = require('ethers');

const provider = new ethers.JsonRpcProvider('https://sepolia.base.org');
const wallet = new ethers.Wallet(privateKey, provider);

const abi = [
  'function mintWithParameters(address to, uint256 seed, uint256 steps, uint256 cfgScale, string sampler, string scheduler, uint256 width, uint256 height, uint256 modelId, uint256 recipeId, address targetWorker, string metadataURI) payable returns (uint256)',
  'function getGenerationParams(uint256 tokenId) view returns (uint256 seed, uint256 steps, uint256 cfgScale, string sampler, string scheduler, uint256 width, uint256 height, uint256 modelId, uint256 recipeId, address targetWorker)'
];

const gridNFT = new ethers.Contract(contractAddress, abi, wallet);

// Mint NFT
const tx = await gridNFT.mintWithParameters(
  wallet.address,
  42, // seed
  30, // steps
  750, // cfgScale (7.5)
  'dpmpp_2m_karras',
  'karras',
  1024, 1024,
  1, // modelId
  1, // recipeId
  workerAddress,
  'ipfs://QmXxx...',
  { value: ethers.parseEther('0.01') }
);

const receipt = await tx.wait();
const tokenId = receipt.logs[0].args.tokenId;
```

## IPFS Metadata Format

The `metadataURI` should follow ERC721 metadata standard:

```json
{
  "name": "AI Power Grid #42",
  "description": "Verifiable AI-generated art with on-chain parameters",
  "image": "ipfs://QmImageHash",
  "attributes": [
    { "trait_type": "Model", "value": "FLUX.1" },
    { "trait_type": "Seed", "value": "42" },
    { "trait_type": "Steps", "value": "30" },
    { "trait_type": "CFG Scale", "value": "7.5" },
    { "trait_type": "Sampler", "value": "dpmpp_2m_karras" },
    { "trait_type": "Worker", "value": "0xWorkerAddress" }
  ],
  "generation_params": {
    "seed": 42,
    "steps": 30,
    "cfg_scale": 7.5,
    "sampler": "dpmpp_2m_karras",
    "scheduler": "karras",
    "width": 1024,
    "height": 1024,
    "model_id": 1,
    "recipe_id": 1
  },
  "blockchain_verification": {
    "chain": "Base Sepolia",
    "contract": "0x7d49b017E824aA47Ca36d74a9377A3c1EFb53ef9",
    "token_id": 42
  }
}
```

## Security Features

### Access Control
- Model and recipe approval: Admin only
- Emergency withdraw: Admin only
- Minting: Public (with payment)

### Payment Security
- Reentrancy protection on all fund transfers
- Automatic worker payments (no manual claim needed)
- Excess payment refunded to sender
- Emergency withdraw for stuck funds

### Input Validation
- Non-zero addresses required
- Parameter ranges checked against model constraints
- Approved models and recipes only
- Dimensions must be valid

## Testing

The GridNFT contract is currently on Base Sepolia testnet only and has been extensively tested for pixel-perfect reproducibility across platforms. See the main README for available interaction scripts.

## Gas Costs

Approximate gas costs on Base Sepolia:

- Mint NFT: ~150,000 gas
- Get parameters: ~30,000 gas (view function, free)
- Approve model: ~50,000 gas
- Approve recipe: ~50,000 gas

## Deployment Checklist

Before mainnet deployment:

- [ ] Deploy GridNFT contract
- [ ] Deploy ModelRegistry contract
- [ ] Deploy RecipeVault contract
- [ ] Register approved AI models
- [ ] Upload and approve workflow recipes
- [ ] Set treasury address
- [ ] Set mint fee structure
- [ ] Test full generation flow on testnet
- [ ] Verify all contracts on BaseScan
- [ ] Set up IPFS pinning infrastructure

## Future Enhancements

Planned for future audit rounds:

1. **Dynamic Pricing**: Adjust mint fees based on model complexity
2. **Reputation System**: Track worker quality and performance
3. **Batch Minting**: Mint multiple NFTs in one transaction
4. **Royalties**: Secondary sale royalties to workers
5. **Governance**: Community voting on approved models/recipes

## Related Contracts

- **ModelRegistry**: AI model validation and constraints
- **RecipeVault**: Workflow template storage
- **AIPGTokenV2**: Native token (potential future integration)
- **BondedWorkerRegistry**: Worker verification and bonding
