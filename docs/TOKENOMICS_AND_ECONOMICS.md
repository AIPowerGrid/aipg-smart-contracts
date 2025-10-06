# AIPG Token Economics and Payment Flow

## Overview

AIPG (AI Power Grid) implements a decentralized AI compute network where AI workers perform compute tasks and receive payment in AIPG tokens. The system uses a hybrid on-chain/off-chain architecture for efficiency and scalability.

## Core Economic Components

### 1. Token Supply and Distribution

- **Maximum Supply**: 150,000,000 AIPG (capped via ERC20Capped)
- **Current Circulating**: ~15,016,680 AIPG (migrated from legacy chain)
- **Token Standard**: ERC20 with Permit, Pausable, Burnable extensions
- **Deployment**: Base L2 (Ethereum scaling solution)

### 2. Emissions Controller

The `EmissionsControllerV2` contract manages token issuance and distribution through several mechanisms:

#### Daily Emissions Schedule
- Emissions decay over time following a predetermined schedule
- Maximum daily emissions decrease as the network matures
- Emissions are distributed across multiple pools:
  - **Worker Rewards Pool**: AI compute workers
  - **Staking Rewards Pool**: Token stakers
  - **Development Pool**: Core development funding
  - **Marketing Pool**: Growth and adoption initiatives

#### Key Parameters
- `lastEmissionTime`: Tracks when emissions were last distributed
- `totalEmitted`: Running total of all emissions
- `emissionSchedule`: Array defining daily emission rates over time
- Emissions can be triggered by anyone after the cooldown period expires

### 3. AI Worker Payment Flow

#### Off-Chain Computation → On-Chain Settlement

The system uses a **batch payment model** to minimize gas costs:

1. **Off-Chain Sentry Monitors Work**
   - Grid Rewards Sentry (Python service) monitors AI workers
   - Tracks compute jobs, GPU hours, and task completion
   - Validates work quality and uptime
   - Aggregates earnings for each worker address

2. **Batch Signature Generation**
   - Sentry calculates total earnings for the period
   - Creates EIP-712 typed signature for batch payment
   - Signature includes: worker address, amount, nonce, deadline
   - Signed by authorized EMISSIONS_MANAGER role

3. **On-Chain Claim**
   - Worker calls `claimWorkerReward(amount, deadline, v, r, s)`
   - Contract verifies EIP-712 signature
   - Checks nonce to prevent double-claiming
   - Mints tokens directly to worker address
   - Emits `WorkerRewardClaimed` event for transparency

#### Security Features
- **Nonce System**: Each worker has incrementing nonce to prevent replay attacks
- **Deadline**: Signatures expire after specified timestamp
- **Role-Based Access**: Only EMISSIONS_MANAGER can sign valid claims
- **Reentrancy Protection**: Uses OpenZeppelin's ReentrancyGuard

### 4. Bonded Worker Registry

AI workers must stake AIPG tokens as collateral to participate in the network.

#### Bonding Process
1. Worker stakes minimum required AIPG tokens
2. Tokens are locked in `BondedWorkerRegistry` contract
3. Worker receives permission to accept compute jobs
4. Stake acts as insurance against misbehavior

#### Slashing Conditions
Workers can be slashed (lose staked tokens) for:
- Submitting invalid work results
- Extended downtime without notice
- Malicious behavior or attacks on the network
- Failing quality audits from the sentry system

#### Unbonding
- Workers can request to unbond and exit
- Unbonding period (e.g., 7-14 days) allows dispute resolution
- After period expires, stake is returned minus any slashing penalties

### 5. Staking Vault

Token holders can stake AIPG to earn passive rewards.

#### Mechanics
- Users deposit AIPG tokens into `StakingVault`
- Rewards are distributed proportionally to stake size
- Rewards funded by:
  - Portion of daily emissions
  - Protocol fees (future implementation)
  - Network transaction taxes (if enabled)

#### Key Features
- **Real-time Reward Accrual**: Rewards calculate per-block using `rewardPerToken`
- **Flexible Withdrawals**: Users can withdraw stake + rewards anytime
- **Emergency Stop**: Pausable in case of critical issues
- **Reentrancy Protection**: Secure withdraw/claim functions

#### Reward Distribution Formula
```
rewardPerToken = rewardPerTokenStored + (
    (lastUpdateTime - lastRewardTime) * rewardRate * 1e18 / totalSupply
)

userEarned = (userStake * (rewardPerToken - userPaidReward)) / 1e18 + storedRewards
```

### 6. Economic Incentive Alignment

#### For AI Workers
- **Revenue**: Earn AIPG for compute work performed
- **Cost**: Must bond tokens (opportunity cost + slashing risk)
- **Optimization**: Maximize uptime and work quality to earn rewards

#### For Token Stakers
- **Revenue**: Earn portion of network emissions passively
- **Cost**: Locked liquidity, smart contract risk
- **Optimization**: Long-term holding to compound rewards

#### For Token Holders
- **Value Accrual**: Supply capped, demand from AI compute usage
- **Governance**: Future DAO voting rights (planned)
- **Deflationary Pressure**: Bonding locks supply, optional burn mechanisms

## Payment Example Scenario

### Worker Completes 1 Week of AI Compute

1. **Week 1**: Worker runs GPU for 168 hours
2. **Sentry Calculates**: 168 hours × rate = 1,000 AIPG earned
3. **Sentry Signs**: Creates EIP-712 signature for (workerAddress, 1000e18, nonce: 0, deadline: 7d)
4. **Worker Claims**: Submits transaction with signature
5. **Contract Validates**: 
   - Signature is from EMISSIONS_MANAGER ✓
   - Nonce matches (0) ✓
   - Deadline not expired ✓
   - Amount within daily limits ✓
6. **Tokens Minted**: 1,000 AIPG minted to worker address
7. **Nonce Incremented**: Worker nonce → 1 (prevents replay)
8. **Event Emitted**: `WorkerRewardClaimed(worker, 1000e18, 0)`

## Economic Security Considerations

### Centralization Risks
- **EMISSIONS_MANAGER Role**: Currently centralized for sentry signing
  - Mitigation: Multi-sig planned for production
  - Mitigation: On-chain governance for role changes
- **Sentry Infrastructure**: Off-chain component required
  - Mitigation: Multiple redundant sentry nodes (planned)
  - Mitigation: Open-source sentry code for auditability

### Attack Vectors
- **Signature Replay**: Prevented by nonce system
- **Signature Forgery**: Prevented by EIP-712 cryptographic signing
- **Sybil Attacks**: Prevented by bonding requirement
- **Flash Loan Attacks**: Staking vault uses time-weighted rewards
- **Reentrancy**: All state changes before external calls

### Emission Rate Manipulation
- Emission schedule is immutable after deployment
- Only DEFAULT_ADMIN can update schedule (should be DAO/multi-sig)
- Daily emission caps prevent runaway inflation

## Future Economic Enhancements

1. **DAO Governance**: Token voting for protocol parameters
2. **Dynamic Emission Rates**: Adjust based on network usage
3. **Protocol Revenue Sharing**: Route fees to stakers
4. **Cross-Chain Bridges**: Enable AIPG on other L2s/chains
5. **NFT Utility**: Premium features for GridNFT holders
6. **Worker Reputation**: Bonus multipliers for quality work history

## Auditor Focus Areas

When reviewing the economic contracts, pay special attention to:

1. **Emission Rate Calculations**: Verify math doesn't allow overflow or underflow
2. **Signature Verification**: Ensure EIP-712 implementation is correct
3. **Nonce Management**: Confirm no nonce reuse or skipping is possible
4. **Reward Accounting**: Check staking vault reward distribution math
5. **Access Control**: Verify only authorized roles can mint/distribute
6. **Emergency Stops**: Ensure pause mechanisms work correctly
7. **Upgrade Paths**: Check if contracts are upgradeable and how
8. **Integer Arithmetic**: Look for precision loss in reward calculations

## References

- **Main Token Contract**: `AIPGTokenV2.sol`
- **Emissions Controller**: `EmissionsControllerV2.sol`
- **Staking System**: `StakingVault.sol`
- **Worker Bonding**: `BondedWorkerRegistry.sol` (reference only, not deploying yet)
- **EIP-712 Standard**: https://eips.ethereum.org/EIPS/eip-712

