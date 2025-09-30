# EmissionsControllerV2

## Overview

`EmissionsControllerV2` is a smart contract that manages the distribution of AIPG tokens to Grid workers who contribute GPU resources to the AI Power Grid network. It handles batch minting of rewards to multiple workers and tracks emissions via IPFS-linked metadata.

**Status**: Testnet only (Base Sepolia)  
**Deployment**: Not yet deployed - awaiting future audit round

## Key Features

### 1. Batch Worker Rewards
- Mint AIPG tokens to multiple workers in a single transaction
- Gas-efficient batch operations for large-scale reward distribution
- Epoch-based tracking for reward periods

### 2. Role-Based Access Control
- `EMISSIONS_MANAGER_ROLE`: Can trigger batch mints and manage emissions
- Integrates with OpenZeppelin AccessControl for security

### 3. IPFS Integration
- Each batch emission links to IPFS metadata
- Metadata contains worker performance data, computation metrics, etc.
- On-chain `BatchEmitted` events for transparency

### 4. Reentrancy Protection
- ReentrancyGuard on all state-changing functions
- Secure fund handling and minting operations

## Architecture

```
EmissionsControllerV2
├── batchMintWorkers()     # Mint rewards to multiple workers
├── setConfig()            # Update emissions parameters
├── getConfig()            # Read current configuration
└── emergencyPause()       # Emergency stop mechanism
```

## Core Functions

### batchMintWorkers

Mints AIPG tokens to multiple workers based on their contribution.

```solidity
function batchMintWorkers(
    address[] calldata workers,
    uint256[] calldata amounts,
    uint256 epochId,
    string calldata uri
) external onlyRole(EMISSIONS_MANAGER_ROLE) nonReentrant
```

**Parameters:**
- `workers`: Array of worker addresses to receive rewards
- `amounts`: Array of token amounts (in wei) for each worker
- `epochId`: The epoch/period identifier for these rewards
- `uri`: IPFS URI containing batch metadata

**Events:**
```solidity
event BatchEmitted(
    uint256 indexed epochId,
    address[] workers,
    uint256[] amounts,
    string uri,
    uint256 timestamp
);
```

## Security Features

### Access Control
- Only `EMISSIONS_MANAGER_ROLE` can trigger batch mints
- Admin can grant/revoke roles via OpenZeppelin AccessControl
- Separate roles for different privilege levels

### Reentrancy Protection
- All external calls protected by ReentrancyGuard
- State updates before external calls (checks-effects-interactions)

### Input Validation
- Arrays must have matching lengths
- Non-zero addresses and amounts required
- Comprehensive require statements

## Integration Requirements

### Required Roles on Other Contracts

1. **AIPGTokenV2**: EmissionsController needs `MINTER_ROLE`
   ```javascript
   await aipgToken.grantRole(MINTER_ROLE, emissionsControllerAddress);
   ```

2. **StakingVault**: EmissionsController needs `REWARD_DISTRIBUTOR_ROLE` (if integrated)
   ```javascript
   await stakingVault.grantRole(REWARD_DISTRIBUTOR_ROLE, emissionsControllerAddress);
   ```

## Usage Example

### Via SDK (JavaScript)

```javascript
const { EmissionsSDK } = require('./sdk/emissions-sdk');

// Initialize SDK
const sdk = EmissionsSDK.fromDeployment({
  deployment: require('./emissions-deployment.json'),
  rpcUrl: 'https://sepolia.base.org'
}).withSigner(process.env.EMISSIONS_MANAGER_PRIVATE_KEY);

// Get current configuration
const config = await sdk.getConfig();
console.log('Emissions config:', config);

// Batch mint to workers
const workers = [
  '0x1111111111111111111111111111111111111111',
  '0x2222222222222222222222222222222222222222'
];
const amounts = [
  ethers.parseEther('100'),  // 100 AIPG
  ethers.parseEther('50')    // 50 AIPG
];

const receipt = await sdk.batchMint({
  workers,
  amounts,
  epochId: 5,
  uri: 'ipfs://QmXxx...', // IPFS metadata
  gasPriceGwei: 0.003
});

console.log('Batch mint successful:', receipt.transactionHash);
```

### Direct Contract Interaction

```javascript
const { ethers } = require('ethers');

const provider = new ethers.JsonRpcProvider('https://sepolia.base.org');
const wallet = new ethers.Wallet(privateKey, provider);

const abi = [
  'function batchMintWorkers(address[] workers, uint256[] amounts, uint256 epochId, string uri)',
  'function getConfig() view returns (uint256 minAmount, uint256 maxAmount, bool paused)'
];

const controller = new ethers.Contract(contractAddress, abi, wallet);

// Execute batch mint
const tx = await controller.batchMintWorkers(
  workers,
  amounts,
  epochId,
  'ipfs://QmXxx...'
);
await tx.wait();
```

## IPFS Metadata Format

The `uri` parameter should point to IPFS metadata containing:

```json
{
  "epochId": 5,
  "startTime": "2025-01-01T00:00:00Z",
  "endTime": "2025-01-07T23:59:59Z",
  "workers": [
    {
      "address": "0x1111...",
      "amount": "100000000000000000000",
      "tasksCompleted": 42,
      "gpuHours": 168.5,
      "performanceScore": 0.95
    }
  ],
  "totalEmitted": "150000000000000000000",
  "networkMetrics": {
    "totalTasks": 1250,
    "averageLatency": "2.3s"
  }
}
```

## Gas Optimization

- Batch operations significantly reduce gas costs vs individual mints
- Base network typically has very low gas prices (0.002-0.01 gwei)
- Array operations optimized for efficiency

## Testing

The EmissionsControllerV2 contract is currently on Base Sepolia testnet only. See the main README for available interaction scripts.

## Deployment Checklist

Before mainnet deployment:

- [ ] Deploy EmissionsControllerV2 contract
- [ ] Grant `MINTER_ROLE` on AIPGTokenV2 to EmissionsController
- [ ] Grant `EMISSIONS_MANAGER_ROLE` to authorized backend address
- [ ] Test batch minting on testnet
- [ ] Verify contract on BaseScan
- [ ] Set up off-chain emissions calculation service
- [ ] Configure IPFS pinning for metadata

## Future Enhancements

Planned for future audit rounds:

1. **Automatic Epoch Management**: Time-based epoch progression
2. **Emissions Schedule**: Gradual reduction over time (halving events)
3. **Performance-Based Multipliers**: Bonus rewards for high-quality workers
4. **Staking Integration**: Direct rewards to staked positions
5. **Multi-Token Support**: Reward in multiple token types

## Security Considerations

- Only trusted addresses should have `EMISSIONS_MANAGER_ROLE`
- IPFS metadata should be validated off-chain before minting
- Monitor for abnormal minting patterns
- Implement rate limits in off-chain service
- Regular audits of emissions data

## Related Contracts

- **AIPGTokenV2**: The token being minted (requires MINTER_ROLE)
- **StakingVault**: Optional integration for staking rewards
- **BondedWorkerRegistry**: Worker verification and bonding
