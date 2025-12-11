# AIPG Grid Integration Guide

## Overview

**Grid** is a modular smart contract that combines all AIPG compute infrastructure into a single address. Instead of interacting with multiple contracts, developers call one address for everything.

## Contract Address (Base Mainnet)

```
Grid: 0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609
```

**BaseScan:** https://basescan.org/address/0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609

## How It Works

Grid uses a proxy pattern (EIP-2535) where one contract routes calls to specialized modules:

```
┌─────────────────────────────────────────────────────────┐
│                         GRID                            │
│              0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609 │
├─────────────────────────────────────────────────────────┤
│  registerModel()  →  ModelVault Module                  │
│  storeRecipe()    →  RecipeVault Module                 │
│  anchorDay()      →  JobAnchor Module                   │
│  registerWorker() →  WorkerRegistry Module              │
│  grantRole()      →  RoleManager Module                 │
└─────────────────────────────────────────────────────────┘
```

**You call Grid directly. It handles routing.**

### Module Addresses (Mainnet)

| Module | Address |
|--------|---------|
| ModuleManager | `0xa55eD5bb1a177d43f1A3FfC57dfd2c0cfe65d297` |
| ModuleInspector | `0x517e3eFEE7205318eea5d3c51d0d0ABfaB648672` |
| Ownership | `0x27f06726F9F29DCcf22e98030A3d34A090103605` |
| RoleManager | `0x59144e0730638f652B9717379c5CA634da7CE926` |
| ModelVault | `0xf2A3bA5C4b56E85e022c5079B645120CE7B6d199` |
| RecipeVault | `0xddEC9d082FB2B45815Ee104947bfd556d4BD0aa1` |
| JobAnchor | `0x1aee3a3e4F2C05814d86cF2426Cf20Ed5c1bfa32` |
| WorkerRegistry | `0x0a3075b1787070210483d3e4845fE58d41c28438` |

---

## Quick Start

### JavaScript/ethers.js

```javascript
const { ethers } = require('ethers');

const GRID_ADDRESS = '0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609';
const provider = new ethers.JsonRpcProvider('https://mainnet.base.org');
const signer = new ethers.Wallet(PRIVATE_KEY, provider);

// Use the ABI for whatever module you need
const grid = new ethers.Contract(GRID_ADDRESS, MODEL_VAULT_ABI, signer);

// Register a model
await grid.registerModel(
    modelHash,      // bytes32
    1,              // modelType (0=TEXT, 1=IMAGE, 2=VIDEO)
    "model.safetensors",
    "My Model",
    "1.0.0",
    "QmIPFSCID...",
    "https://download.url/model.safetensors",
    12000000000,    // size in bytes
    "fp8",          // quantization
    "safetensors",  // format
    24000,          // VRAM in MB
    "FLUX.1-dev",   // base model
    false,          // inpainting
    true,           // img2img
    false,          // controlnet
    false,          // lora
    false           // isNSFW
);

// Read a model
const model = await grid.getModel(1);
console.log(model.name, model.ipfsCid, model.downloadUrl);
```

---

## Modules & Functions

### ModelVault - AI Model Registry

| Function | Description |
|----------|-------------|
| `registerModel(...)` | Register a new model |
| `getModel(uint256 modelId)` | Get model by ID |
| `getModelByHash(bytes32 hash)` | Get model by hash |
| `getModelCount()` | Total registered models |
| `isModelActive(uint256 modelId)` | Check if model is active |
| `updateStorageLocations(id, ipfsCid, downloadUrl)` | Update IPFS/URL |
| `deprecateModel(uint256 modelId)` | Mark model inactive |
| `setConstraints(...)` | Set generation constraints |
| `validateParams(...)` | Validate generation params |

#### Model Struct

```solidity
struct Model {
    // Identity
    bytes32 modelHash;
    ModelType modelType;     // TEXT_MODEL, IMAGE_MODEL, VIDEO_MODEL
    string fileName;
    string name;
    string version;
    
    // Storage
    string ipfsCid;          // IPFS content ID
    string downloadUrl;      // HTTP mirror
    uint256 sizeBytes;
    
    // Technical
    string quantization;     // "fp16", "fp8", "Q4_K_M"
    string format;           // "safetensors", "gguf", "onnx"
    uint32 vramMB;
    string baseModel;
    
    // Capabilities
    bool inpainting;
    bool img2img;
    bool controlnet;
    bool lora;
    
    // Status
    bool isActive;
    bool isNSFW;
    uint256 timestamp;
    address creator;
}
```

### RecipeVault - Workflow Storage

| Function | Description |
|----------|-------------|
| `storeRecipe(...)` | Store a workflow |
| `getRecipe(uint256 recipeId)` | Get recipe by ID |
| `getRecipeByRoot(bytes32 root)` | Get recipe by hash |
| `getCreatorRecipes(address)` | Get all recipes by creator |
| `updateRecipePermissions(...)` | Update public/NFT flags |

### JobAnchor - Job Tracking

| Function | Description |
|----------|-------------|
| `anchorDay(day, merkleRoot, jobs, rewards)` | Anchor daily summary |
| `anchorJobIds(bytes32[] jobIds)` | Anchor individual job IDs |
| `getDayAnchor(uint256 day)` | Get anchor for a day |
| `isJobAnchored(bytes32 jobId)` | Check if job is anchored |
| `verifyJobInDay(day, jobId, proof)` | Verify job with merkle proof |
| `getCurrentDay()` | Get current day number |

### WorkerRegistry - Worker Management (Bonded)

| Function | Description |
|----------|-------------|
| `registerWorker(uint256 bondAmount)` | Register with bond |
| `unbond()` | Withdraw bond and deactivate |
| `getWorker(address)` | Get worker info |
| `isWorkerActive(address)` | Check if worker active |
| `getTotalBonded()` | Total bonded amount |

### RoleManager - Access Control

| Function | Description |
|----------|-------------|
| `grantRole(bytes32 role, address)` | Grant a role |
| `revokeRole(bytes32 role, address)` | Revoke a role |
| `hasRole(bytes32 role, address)` | Check if has role |
| `pause()` | Pause all modules |
| `unpause()` | Unpause |

**Roles:**
- `ADMIN_ROLE` - Full admin access
- `REGISTRAR_ROLE` - Can register models
- `ANCHOR_ROLE` - Can anchor jobs
- `PAUSER_ROLE` - Can pause

---

## Example: Register a Model

```javascript
const { ethers } = require('ethers');

const GRID = '0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609';
const RPC = 'https://mainnet.base.org';

const ABI = [
    'function registerModel(bytes32,uint8,string,string,string,string,string,uint256,string,string,uint32,string,bool,bool,bool,bool,bool) returns (uint256)',
    'function getModel(uint256) view returns (tuple(bytes32,uint8,string,string,string,string,string,uint256,string,string,uint32,string,bool,bool,bool,bool,bool,bool,uint256,address))',
    'function getModelCount() view returns (uint256)'
];

async function main() {
    const provider = new ethers.JsonRpcProvider(RPC);
    const signer = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
    const grid = new ethers.Contract(GRID, ABI, signer);

    // Create model hash from filename
    const modelHash = ethers.keccak256(ethers.toUtf8Bytes('flux1-dev-fp8.safetensors'));

    // Register
    const tx = await grid.registerModel(
        modelHash,
        1,  // IMAGE_MODEL
        'flux1-dev-fp8.safetensors',
        'FLUX.1-dev FP8',
        '1.0.0',
        'QmXoypizjW3WknFiJnKLwHCnL72vedxjQkDDP1mXWo6uco',
        'https://models.aipowergrid.io/flux1-dev-fp8.safetensors',
        12000000000,
        'fp8',
        'safetensors',
        24000,
        'FLUX.1-dev',
        false, true, false, false, false
    );
    
    console.log('TX:', tx.hash);
    await tx.wait();
    
    // Read back
    const count = await grid.getModelCount();
    const model = await grid.getModel(count);
    console.log('Registered:', model.name);
}

main();
```

---

## Example: Read Models

```javascript
const { ethers } = require('ethers');

const GRID = '0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609';
const RPC = 'https://mainnet.base.org';

const ABI = [
    'function getModel(uint256) view returns (tuple(bytes32 modelHash,uint8 modelType,string fileName,string name,string version,string ipfsCid,string downloadUrl,uint256 sizeBytes,string quantization,string format,uint32 vramMB,string baseModel,bool inpainting,bool img2img,bool controlnet,bool lora,bool isActive,bool isNSFW,uint256 timestamp,address creator))',
    'function getModelCount() view returns (uint256)'
];

async function main() {
    const provider = new ethers.JsonRpcProvider(RPC);
    const grid = new ethers.Contract(GRID, ABI, provider);

    const count = await grid.getModelCount();
    console.log('Total models:', count.toString());

    for (let i = 1; i <= count; i++) {
        const m = await grid.getModel(i);
        console.log(`\nModel ${i}:`);
        console.log('  Name:', m.name);
        console.log('  File:', m.fileName);
        console.log('  IPFS:', m.ipfsCid);
        console.log('  URL:', m.downloadUrl);
        console.log('  Size:', Number(m.sizeBytes) / 1e9, 'GB');
        console.log('  VRAM:', m.vramMB, 'MB');
        console.log('  Format:', m.format);
        console.log('  Quantization:', m.quantization);
        console.log('  Capabilities:', {
            img2img: m.img2img,
            inpainting: m.inpainting,
            controlnet: m.controlnet,
            lora: m.lora
        });
    }
}

main();
```

---

## Network Info

| Network | Chain ID | RPC |
|---------|----------|-----|
| Base (mainnet) | 8453 | https://mainnet.base.org |
| Base Sepolia (testnet) | 84532 | https://sepolia.base.org |

---

## Admin

Current admin: `0xA218db26ed545f3476e6c3E827b595cf2E182533`

To grant REGISTRAR_ROLE to a new address:
```javascript
const REGISTRAR_ROLE = ethers.keccak256(ethers.toUtf8Bytes('REGISTRAR_ROLE'));
await grid.grantRole(REGISTRAR_ROLE, '0xNewAddress...');
```

---

## Questions?

Contact the AIPG team.

