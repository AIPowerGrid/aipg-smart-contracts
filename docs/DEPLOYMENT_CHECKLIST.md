# EmissionsController & StakingVault Deployment Checklist

## ⚠️ CRITICAL: Pre-Deployment Steps

### 1. Deploy Contracts in Order

```bash
# Step 1: Deploy StakingVault
# Constructor args: (stakingToken, rewardsToken)
# Both should be the AIPG token address: 0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608

# Step 2: Deploy EmissionsController
# Constructor args: (token, vault, treasury)
# - token: 0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608
# - vault: <StakingVault address from Step 1>
# - treasury: <Treasury multisig address>
```

### 2. Grant Required Roles

**CRITICAL:** Without these roles, all emissions will fail!

```javascript
// On AIPGTokenV2 contract
const MINTER_ROLE = await token.MINTER_ROLE();
await token.grantRole(MINTER_ROLE, EMISSIONS_CONTROLLER_ADDRESS);

// On StakingVault contract
const REWARD_DISTRIBUTOR_ROLE = await vault.REWARD_DISTRIBUTOR_ROLE();
await vault.grantRole(REWARD_DISTRIBUTOR_ROLE, EMISSIONS_CONTROLLER_ADDRESS);
```

### 3. Verify Configuration

Run the integration test:

```bash
export EMISSIONS_CONTROLLER_ADDRESS=<deployed_address>
export STAKING_VAULT_ADDRESS=<deployed_address>
node scripts/test-emissions-integration.js
```

All checks must pass ✅ before proceeding.

### 4. Start Emissions

Once verified, start the emissions:

```javascript
// This unpauses emissions and sets the migration start time
await emissionsController.startMigration();
```

## 🔧 Configuration Parameters

### EmissionsController

- **Initial State**: `emissionsPaused = true` (starts paused)
- **Default Shares**:
  - Worker: 60% (6000 bps)
  - Staker: 30% (3000 bps)
  - Treasury: 10% (1000 bps)

### Era Schedule

| Era | Length | Reward/Hour | Total Rewards |
|-----|--------|-------------|---------------|
| 0   | 1736 days | 9.375 AIPG | ~390K AIPG |
| 1   | 365 days | 4.6875 AIPG | ~41K AIPG |
| 2   | 365 days | 2.34375 AIPG | ~20.5K AIPG |
| 3   | 365 days | 1.171875 AIPG | ~10.3K AIPG |
| 4   | 362 days | 0.5859375 AIPG | ~5.1K AIPG |
| 5   | 2604 days | 0.5859375 AIPG | ~36.6K AIPG |
| 6   | 730 days | 0.29296875 AIPG | ~5.1K AIPG |
| 7+  | Halving every 730 days | Halves each era | Asymptotic |

### StakingVault

- **Default Rewards Duration**: 7 days
- **Reward Distribution**: Linear streaming over duration
- **Emergency Pause**: Admin can pause vault operations

## 🧪 Testing Flows

### Test 1: Manager Mint (No Signature)

```javascript
// As EMISSIONS_MANAGER_ROLE holder
await emissionsController.mintWorker(workerAddress, hoursWorked);

// Verify:
// - Worker receives 60% of (hoursWorked * rewardPerHour)
// - StakingVault receives 30% 
// - Treasury receives 10%
// - StakingVault.notifyRewardAmount() was called
```

### Test 2: Worker Self-Claim (EIP-712)

```javascript
// Generate EIP-712 signature off-chain
const domain = {
  name: 'AIPG-Emissions',
  version: '1',
  chainId: 8453, // Base mainnet
  verifyingContract: EMISSIONS_CONTROLLER_ADDRESS
};

const types = {
  WorkerClaim: [
    { name: 'worker', type: 'address' },
    { name: 'hoursWorked', type: 'uint256' },
    { name: 'nonce', type: 'uint256' },
    { name: 'deadline', type: 'uint256' }
  ]
};

const value = {
  worker: workerAddress,
  hoursWorked: hours,
  nonce: await emissionsController.nonces(workerAddress),
  deadline: Math.floor(Date.now() / 1000) + 3600
};

const signature = await signer._signTypedData(domain, types, value);

// Worker calls with signature
await emissionsController.claimWithSignature(hoursWorked, deadline, signature);
```

### Test 3: Batch Payout

```javascript
const workers = ['0x...', '0x...', '0x...'];
const amounts = ['1000000000000000000', '2000000000000000000', '1500000000000000000'];
const epochId = 1;
const uri = 'ipfs://Qm...'; // Metadata URI

await emissionsController.batchMintWorkers(workers, amounts, epochId, uri);

// Emits DailyPayout event with aggregated stats
```

### Test 4: Staking Integration

```javascript
// User stakes AIPG
await token.approve(VAULT_ADDRESS, stakeAmount);
await vault.stake(stakeAmount);

// After emissions occur, check earned rewards
const earned = await vault.earned(userAddress);

// Claim rewards
await vault.getReward();
```

## 🚨 Known Issues (Fixed)

### ✅ Fixed Issues

1. **Missing Interface Files** - Added `IAIPGToken.sol` and `IStakingVault.sol`
2. **Wrong EIP-712 Typehash** - Corrected to `0xaf951ae13436754b4e70e550c82e28aab8397a6632b944a5e339bab92dc4e38f`
3. **Missing Pause Check** - Added `whenNotPaused` to `notifyRewardAmount()`

### ⚠️ Audit Focus Areas

- **Reward Accounting**: Verify StakingVault math with real minting
- **Era Transitions**: Test `startNextEra()` at boundary conditions
- **EIP-712 Security**: Verify signature replay protection (nonces)
- **Cap Enforcement**: Ensure emissions stop at 150M max supply
- **Role-Based Access**: Confirm all privileged functions are protected

## 📝 Post-Deployment

1. **Verify contracts on BaseScan**
2. **Grant roles to production addresses** (multisig, not EOAs)
3. **Test with small amounts first**
4. **Monitor events for anomalies**
5. **Set up off-chain signer service** for worker claims
6. **Document all addresses** in `ADDRESSES.md`

## 🔗 Integration Points

- **AIPGTokenV2**: Must have minting permission
- **StakingVault**: Must accept reward notifications
- **Treasury**: Must be a valid address (preferably multisig)
- **Off-chain Signer**: Must have SIGNER_ROLE for worker claims









