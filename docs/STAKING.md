# AIPG Staking System

## Overview

The AIPG staking system allows token holders to stake their AIPG and earn rewards. It uses a Synthetix-style reward distribution mechanism with manual funding.

---

## Contract Details

**StakingVault**: `0x3ED14A6D5A48614D77f313389611410d38fd8277`  
**Deployed**: November 1, 2025  
**Admin**: `0x94A3951e6cC9161B753007Cf5b483d6cEEf04897` (Ledger)  
**BaseScan**: https://basescan.org/address/0x3ED14A6D5A48614D77f313389611410d38fd8277

---

## How It Works

### For Users

1. **Stake AIPG**
   - Call `stake(amount)` 
   - Tokens are locked in the contract
   - Rewards start accruing immediately

2. **Earn Rewards**
   - Rewards accrue every second
   - Proportional to your share of total staked
   - No lockup period

3. **Claim Rewards**
   - Call `getReward()` anytime
   - Rewards transferred to your wallet
   - Can claim daily, weekly, or whenever

4. **Unstake**
   - Call `withdraw(amount)` to unstake
   - Call `exit()` to unstake all + claim rewards
   - No penalty for unstaking

### For Admin

1. **Fund Rewards**
   - Transfer AIPG from treasury to StakingVault
   - Call `notifyRewardAmount(amount)`
   - Rewards stream linearly over 7 days

2. **Adjust Duration**
   - Call `setRewardsDuration(seconds)`
   - Can only change when no active reward period

3. **Emergency Controls**
   - `pause()` - Stop new stakes/withdrawals
   - `unpause()` - Resume operations

---

## Economics

### Budget Allocation

- **Total Staking Budget**: 10M AIPG over 1 year
- **Weekly Funding**: 
  - Weeks 1-4: 300K AIPG/week (~60% APY)
  - Months 2-6: 200K AIPG/week (~40% APY)
  - Months 7-12: 150K AIPG/week (~30% APY)

### Eligible Supply

- **Total Supply**: 150M AIPG (max cap, minting disabled)
- **Treasury**: 119M AIPG (excluded from staking)
- **Circulating**: ~31M AIPG (eligible for staking)
- **Expected Participation**: 30-50% (~10-15M AIPG staked)

### Expected APY

| Staked Amount | APY |
|---------------|-----|
| 10M AIPG | 100% |
| 15M AIPG | 67% |
| 20M AIPG | 50% |
| 30M AIPG | 33% |

*Based on 10M AIPG rewards over 1 year*

---

## Technical Details

### Reward Calculation

Rewards are calculated using the Synthetix model:

```
rewardPerToken = rewardPerTokenStored + 
                 ((currentTime - lastUpdateTime) * rewardRate * 1e18) / totalSupply

earned = (userBalance * (rewardPerToken - userRewardPerTokenPaid)) / 1e18 + storedRewards
```

### Reward Distribution

- Rewards stream linearly over `rewardsDuration` (default 7 days)
- `rewardRate` = total rewards / duration (in seconds)
- Users earn proportional to their share of `totalSupply`

### Security Features

- **ReentrancyGuard**: Prevents reentrancy attacks
- **Pausable**: Admin can pause in emergency
- **AccessControl**: Role-based permissions
- **SafeERC20**: Safe token transfers

---

## Roles

### DEFAULT_ADMIN_ROLE

- Granted to: `0x94A3951e6cC9161B753007Cf5b483d6cEEf04897` (Ledger)
- Can:
  - Grant/revoke REWARD_DISTRIBUTOR_ROLE
  - Set rewards duration
  - Pause/unpause contract

### REWARD_DISTRIBUTOR_ROLE

- Granted to: Admin (Ledger)
- Can:
  - Call `notifyRewardAmount()` to fund rewards

---

## User Functions

### stake(uint256 amount)
Stakes AIPG tokens to earn rewards.

**Parameters:**
- `amount`: Amount of AIPG to stake (in wei)

**Requirements:**
- Contract not paused
- User has sufficient AIPG balance
- User has approved StakingVault to spend AIPG

### withdraw(uint256 amount)
Withdraws staked AIPG tokens.

**Parameters:**
- `amount`: Amount of AIPG to withdraw (in wei)

**Requirements:**
- User has sufficient staked balance

### getReward()
Claims accumulated rewards.

**Returns:** Transfers earned AIPG rewards to caller

### exit()
Withdraws all staked tokens and claims all rewards in one transaction.

---

## View Functions

### balanceOf(address account)
Returns the amount of AIPG staked by an account.

### earned(address account)
Returns the amount of rewards earned by an account.

### totalSupply()
Returns the total amount of AIPG currently staked.

### rewardRate()
Returns the current reward rate (AIPG per second).

### periodFinish()
Returns the timestamp when the current reward period ends.

### rewardsDuration()
Returns the duration of reward periods (in seconds).

---

## Admin Functions

### notifyRewardAmount(uint256 reward)
Funds a new reward period.

**Requirements:**
- Caller has REWARD_DISTRIBUTOR_ROLE
- Contract not paused
- StakingVault has sufficient AIPG balance

**Parameters:**
- `reward`: Amount of AIPG to distribute over the reward period

### setRewardsDuration(uint256 duration)
Changes the reward period duration.

**Requirements:**
- Caller has DEFAULT_ADMIN_ROLE
- No active reward period

**Parameters:**
- `duration`: New duration in seconds

### pause() / unpause()
Emergency controls to pause/resume staking.

**Requirements:**
- Caller has DEFAULT_ADMIN_ROLE

---

## Integration Guide

### For Frontend Developers

1. **Connect to Contract**
```javascript
const stakingVault = new ethers.Contract(
  '0x3ED14A6D5A48614D77f313389611410d38fd8277',
  STAKING_VAULT_ABI,
  signer
);
```

2. **Check User Balance**
```javascript
const staked = await stakingVault.balanceOf(userAddress);
const earned = await stakingVault.earned(userAddress);
```

3. **Stake Tokens**
```javascript
// First approve
await aipgToken.approve(stakingVaultAddress, amount);
// Then stake
await stakingVault.stake(amount);
```

4. **Claim Rewards**
```javascript
await stakingVault.getReward();
```

5. **Unstake**
```javascript
await stakingVault.withdraw(amount);
// Or unstake all + claim
await stakingVault.exit();
```

---

## Deployment Info

- **Network**: Base Mainnet (Chain ID: 8453)
- **Deployment Date**: November 1, 2025
- **Deployment Tx**: `0x31334f80a5371572aa691e9f9a1081f00eeb40585db98486a85a287654637362`
- **Deployer**: `0x94A3951e6cC9161B753007Cf5b483d6cEEf04897` (Ledger)
- **Constructor Args**:
  - `stakingToken`: `0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608` (AIPG)
  - `rewardsToken`: `0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608` (AIPG)

---

## Audit Notes

### Design Decisions

1. **No EmissionsController**: Simplified to manual reward funding
2. **No Minimum Stake**: Any amount > 0 can be staked
3. **No Lockup**: Users can withdraw anytime
4. **No Blacklist**: Fungible tokens make blacklists ineffective

### Known Limitations

1. **Manual Funding**: Admin must fund rewards weekly/monthly
2. **No Auto-Compound**: Users must claim rewards manually
3. **No Boosting**: All stakers earn same APY (proportional to stake)

### Security Considerations

1. **Reward Funding**: Admin must ensure StakingVault has sufficient AIPG before calling `notifyRewardAmount()`
2. **Reward Duration**: Cannot change duration during active reward period
3. **Emergency Pause**: Admin can pause to prevent new stakes/withdrawals if needed

---

## Testing

See `audit-package/scripts/test-staking-vault.js` for integration tests.

---

## Support

- **Documentation**: https://docs.aipowergrid.io/staking
- **Discord**: https://discord.gg/aipowergrid
- **Twitter**: https://twitter.com/aipowergrid


