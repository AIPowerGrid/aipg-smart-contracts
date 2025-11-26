# Audit Scope

## Focus Contracts (Production)

### 1. AIPGTokenV2 ✅ DEPLOYED

**Status**: Live on Base Mainnet  
**Address**: `0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608`  
**Priority**: CRITICAL - Production contract

ERC20 token contract with pre-minted supply (150M total).

**Key Areas to Audit:**
1. **Access Control & Roles**
   - DEFAULT_ADMIN_ROLE management
   - MINTER_ROLE security (used by bridge)
   - PAUSER_ROLE emergency controls

2. **Token Security**
   - MAX_SUPPLY enforcement (150M cap)
   - Minting/burning mechanics
   - Transfer functionality

3. **Emergency Controls**
   - Pause/unpause functionality
   - Admin role transfer safety

4. **EIP-712 Implementation** (if applicable)
   - Signature verification
   - Replay protection

---

### 2. StakingVault ✅ LIVE

**Status**: Live on Base Mainnet  
**Address**: `0x3ED14A6D5A48614D77f313389611410d38fd8277`  
**Priority**: HIGH - Production contract

Synthetix-style staking mechanism with manual reward distribution.

**Key Areas to Audit:**
1. **Staking Mechanics**
   - Stake/withdraw functions
   - Reward accrual calculations
   - No lock period enforcement

2. **Reward Distribution**
   - notifyRewardAmount() function
   - REWARD_DISTRIBUTOR_ROLE security
   - Linear reward streaming over duration

3. **Access Control**
   - Role management (DEFAULT_ADMIN_ROLE, REWARD_DISTRIBUTOR_ROLE)
   - Admin function restrictions
   - Pausable functionality

4. **Economic Security**
   - Reward rate calculations
   - Edge cases (zero stakers, late claims)
   - Total supply tracking

5. **Integration with AIPGTokenV2**
   - Token transfer security
   - Proper ERC20 interface usage

---

## Additional Contracts (Reference)

The following contracts are included for context:

- **GridNFT** - AI-generated NFT contract
- **ModelRegistry** - Model constraints registry
- **RecipeVault** - ComfyUI workflow storage
- **BondedWorkerRegistry** - Worker registry

These are **NOT** part of this audit round but provide context for the token ecosystem.

---

## Audit Deliverables

### For AIPGTokenV2 + StakingVault:
- [ ] Full security audit report with executive summary
- [ ] Critical/High/Medium/Low severity findings with remediation
- [ ] Gas optimization recommendations
- [ ] Access control analysis for all roles
- [ ] Economic security review
- [ ] Integration security between contracts
- [ ] Test coverage recommendations
- [ ] Deployment verification checklist

---

## Testing & Verification

All contracts compiled with:
- Solidity `0.8.24`
- OpenZeppelin contracts
- Hardhat environment

**Mainnet Verification:**
- AIPGTokenV2: [BaseScan](https://basescan.org/address/0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608)
- StakingVault: [BaseScan](https://basescan.org/address/0x3ED14A6D5A48614D77f313389611410d38fd8277)

**Network**: Base Mainnet (Chain ID: 8453)

---

**Last Updated**: November 2025
