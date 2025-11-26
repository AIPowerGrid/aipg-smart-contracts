# AIPG Token Economics

## Overview

AIPG (AI Power Grid) powers a decentralized AI compute network where GPU workers perform compute tasks and earn AIPG tokens. The token also serves as staking collateral and a means of governance.

## Token Distribution

| Metric | Value |
|--------|-------|
| **Maximum Supply** | 150,000,000 AIPG (capped) |
| **Total Minted** | 150,000,000 AIPG (all pre-minted) |
| **Minting Status** | **RENOUNCED** (permanently disabled) |
| **Network** | Base L2 (Chain ID: 8453) |

> ⚠️ **Security Note:** Minting capability has been permanently renounced. No address holds MINTER_ROLE, ensuring the supply cannot be inflated.

## Economic Components

### 1. AIPGTokenV2

The core token contract:
- ERC20 with Permit, Pausable, Burnable extensions
- 150M fixed supply (all pre-minted)
- **Minting permanently renounced** (MINTER_ROLE revoked)
- Emergency pause controls
- Supply cannot be inflated

**Address**: `0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608`

### 2. StakingVault

Synthetix-style staking mechanism for passive rewards:

- Users stake AIPG to earn rewards
- Rewards funded manually from treasury
- Linear distribution over 7-day periods
- No lock period (unstake anytime)
- Real-time reward accrual

**Address**: `0x3ED14A6D5A48614D77f313389611410d38fd8277`

#### How Staking Works

1. **Fund Vault**: Treasury sends AIPG to StakingVault
2. **Start Period**: Admin calls `notifyRewardAmount(amount)`
3. **Distribution**: Rewards stream linearly over 7 days
4. **User Claims**: Users call `getReward()` anytime
5. **Repeat**: When period ends, refund and restart

#### Reward Formula

```
rewardPerToken = rewardPerTokenStored + (
    (currentTime - lastUpdateTime) * rewardRate * 1e18 / totalSupply
)

userEarned = (userStake * (rewardPerToken - userPaidReward)) / 1e18 + storedRewards
```

### 3. BondedWorkerRegistry

GPU workers stake AIPG as collateral to participate in the network:

- **Bonding**: Workers stake minimum AIPG to register
- **Activity Tracking**: Jobs completed, rewards earned
- **Slashing**: Misbehavior results in stake reduction
- **Unbonding**: Workers can exit and withdraw stake

#### Worker Rewards

Worker rewards are tracked separately from staker rewards:
- Treasury/admin records job completions via `recordJobCompletion()`
- Workers receive AIPG transfers from treasury for completed work
- BondedWorkerRegistry tracks statistics (jobs, earnings)

### 4. GridNFT

AI-generated art NFTs with on-chain workflow parameters:
- Minting fee in AIPG
- Deterministic reproduction from stored parameters
- Model and recipe constraints enforced on-chain

## Reward Distribution Model

### For Stakers (Passive Income)

| Source | Mechanism | Frequency |
|--------|-----------|-----------|
| Treasury funding | `notifyRewardAmount()` | Weekly |

### For Workers (Active Income)

| Source | Mechanism | Frequency |
|--------|-----------|-----------|
| Treasury payment | Direct transfer | Per job/batch |

## Economic Incentives

### For Stakers
- **Earn**: Passive AIPG rewards proportional to stake
- **Risk**: Smart contract risk, opportunity cost
- **Benefit**: No active participation required

### For Workers
- **Earn**: AIPG for completed compute jobs
- **Risk**: Stake slashing for misbehavior
- **Benefit**: Revenue from GPU utilization

### For Token Holders
- **Value**: Capped supply, utility demand
- **Governance**: Future DAO voting (planned)
- **Deflation**: Optional burn mechanisms

## Security Considerations

### Access Control
- **REWARD_DISTRIBUTOR_ROLE**: Required for `notifyRewardAmount()`
- **REWARD_MANAGER_ROLE**: Required for `recordJobCompletion()`
- **ADMIN_ROLE**: Required for slashing, config changes
- **PAUSER_ROLE**: Emergency pause capability

### Attack Prevention
- **Reentrancy**: All contracts use ReentrancyGuard
- **Flash Loan**: Time-weighted reward accrual
- **Overflow**: Solidity 0.8+ safe math
- **Sybil**: Bonding requirement for workers

## Auditor Focus Areas

1. **Reward Calculations**: Verify no precision loss
2. **Access Control**: All privileged functions protected
3. **State Updates**: State changes before external calls
4. **Emergency Stops**: Pause mechanisms work correctly
5. **Token Transfers**: SafeERC20 used throughout
6. **Edge Cases**: Zero balances, zero stakers, late claims

## Contract References

| Contract | Purpose | Status |
|----------|---------|--------|
| AIPGTokenV2 | Core ERC20 token | ✅ Production |
| StakingVault | Staker rewards | ✅ Production |
| BondedWorkerRegistry | Worker tracking | Reference |
| GridNFT | AI art NFTs | Reference |
| ModelRegistry | Model constraints | Reference |
| RecipeVault | Workflow storage | Reference |

## Links

- [Stake AIPG](https://aipowergrid.io/staking)
- [Token Contract](https://basescan.org/address/0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608)
- [Staking Contract](https://basescan.org/address/0x3ED14A6D5A48614D77f313389611410d38fd8277)
