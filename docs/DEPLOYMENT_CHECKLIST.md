# StakingVault Deployment & Operations Checklist

## ✅ Deployed Contracts

| Contract | Address | Status |
|----------|---------|--------|
| AIPGTokenV2 | `0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608` | ✅ Live |
| StakingVault | `0x3ED14A6D5A48614D77f313389611410d38fd8277` | ✅ Live |

## 🔧 Operations

### Funding Rewards

Rewards are funded manually from treasury wallet:

1. **Transfer AIPG to StakingVault**
```bash
# Send AIPG tokens directly to StakingVault address
# 0x3ED14A6D5A48614D77f313389611410d38fd8277
```

2. **Start Reward Period**
```javascript
// Account with REWARD_DISTRIBUTOR_ROLE calls:
await vault.notifyRewardAmount(rewardAmount);
// This starts a 7-day reward period with linear distribution
```

### Checking Status

```bash
# Check vault balance and reward status
node check-staking-balance.js
```

### Restarting Rewards

```bash
# When reward period ends, restart with available funds
node restart-rewards-fixed.js AUTO
```

## 🔑 Roles

### StakingVault Roles

| Role | Purpose | Current Holder |
|------|---------|----------------|
| DEFAULT_ADMIN_ROLE | Grant/revoke roles | Ledger multisig |
| REWARD_DISTRIBUTOR_ROLE | Call notifyRewardAmount() | Treasury wallet |
| PAUSER_ROLE | Emergency pause | Admin |

### Granting Roles

```javascript
// Grant REWARD_DISTRIBUTOR_ROLE to an address
const REWARD_DISTRIBUTOR_ROLE = await vault.REWARD_DISTRIBUTOR_ROLE();
await vault.grantRole(REWARD_DISTRIBUTOR_ROLE, rewardManagerAddress);
```

## 📊 Reward Distribution

### How It Works

1. **Fund Vault**: Send AIPG tokens to StakingVault address
2. **Notify**: Call `notifyRewardAmount(amount)` with available balance
3. **Distribution**: Rewards stream linearly over 7 days (604800 seconds)
4. **Repeat**: When period ends, refund and restart

### Reward Rate Calculation

```
rewardRate = rewardAmount / rewardsDuration
dailyRewards = rewardRate * 86400
weeklyRewards = rewardRate * 604800
```

### Example

| Funded Amount | Duration | Daily Rate | Weekly Rate |
|---------------|----------|------------|-------------|
| 157,500 AIPG | 7 days | 22,500 AIPG | 157,500 AIPG |
| 100,000 AIPG | 7 days | 14,286 AIPG | 100,000 AIPG |
| 50,000 AIPG | 7 days | 7,143 AIPG | 50,000 AIPG |

## 🧪 Verification

### Check Staking Status
```bash
node check-staking-balance.js
```

Output shows:
- Vault balance
- Total staked
- Available for rewards
- Current reward rate
- Time remaining in period

### Verify on BaseScan
- [AIPGTokenV2](https://basescan.org/address/0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608)
- [StakingVault](https://basescan.org/address/0x3ED14A6D5A48614D77f313389611410d38fd8277)

## 🚨 Emergency Procedures

### Pause Staking
```javascript
// PAUSER_ROLE required
await vault.pause();
```

### Unpause Staking
```javascript
// PAUSER_ROLE required
await vault.unpause();
```

### Recovery
If rewards run out, the vault continues to function - users can still stake/unstake. Rewards simply stop accruing until a new period is started.

## 📝 Maintenance Schedule

| Task | Frequency | Command |
|------|-----------|---------|
| Check status | Daily | `node check-staking-balance.js` |
| Fund rewards | Weekly | Transfer + `notifyRewardAmount()` |
| Monitor APY | Weekly | Calculate from reward rate |

## 🔗 Links

- [Staking UI](https://aipowergrid.io/staking)
- [StakingVault on BaseScan](https://basescan.org/address/0x3ED14A6D5A48614D77f313389611410d38fd8277)
- [Token on BaseScan](https://basescan.org/address/0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608)
