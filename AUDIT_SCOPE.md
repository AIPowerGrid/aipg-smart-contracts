# Audit Scope & Priorities

## 🎯 Audit Round 1 - Three Contracts

This audit focuses on **THREE contracts**:

### 1. AIPGTokenV2 (DEPLOYED)

**Status**: ✅ **DEPLOYED TO BASE MAINNET**  
**Address**: `0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608`  
**Priority**: **CRITICAL - PRODUCTION CONTRACT**

This is our primary asset token contract currently live on Base Mainnet. This contract is the foundation of our bridge and token ecosystem.

### 2. EmissionsControllerV2 (PENDING DEPLOYMENT)

**Status**: 🔵 **READY FOR DEPLOYMENT**  
**Priority**: **HIGH - DEPLOYMENT PENDING AUDIT**

This contract manages token emissions and distributes rewards to GPU workers. Will be deployed to Base Mainnet immediately after audit approval.

### 3. BondedWorkerRegistry (PENDING DEPLOYMENT)

**Status**: 🔵 **READY FOR DEPLOYMENT**  
**Priority**: **HIGH - DEPLOYMENT PENDING AUDIT**

This contract manages bonded worker registration, staking, and slashing mechanisms. Workers stake AIPG tokens to participate in the network. Will be deployed to Base Mainnet immediately after audit approval.

---

## 📋 AIPGTokenV2 - Audit Focus

### Key Areas to Audit:
1. **Access Control & Roles**
   - DEFAULT_ADMIN_ROLE management
   - MINTER_ROLE security (used by bridge)
   - PAUSER_ROLE emergency controls
   
2. **Bridge Minting Security**
   - `bridgeMint` function with EIP-712 signatures
   - UUID replay protection
   - Signature verification
   - Deadline enforcement
   
3. **Token Economics**
   - MAX_SUPPLY cap (150M tokens)
   - Mint/burn mechanics
   - Transfer restrictions (if any)
   
4. **Emergency Controls**
   - Pause/unpause functionality
   - Admin role transfer safety
   
5. **EIP-712 Implementation**
   - Domain separator correctness
   - Signature replay protection across chains

---

## 📋 EmissionsControllerV2 - Audit Focus

### Key Areas to Audit:
1. **Access Control & Roles**
   - EMISSIONS_MANAGER_ROLE security
   - WORKER_ROLE management
   - SIGNER_ROLE for EIP-712 signatures
   
2. **Worker Reward Distribution**
   - EIP-712 signature verification for worker claims
   - Nonce-based replay protection
   - Deadline enforcement
   - Token minting via IAIPGToken interface
   
3. **Economic Model**
   - Era-based emission schedule (7 eras)
   - Reward splits: 60% workers, 30% stakers, 10% treasury
   - MAX_SUPPLY enforcement (150M tokens)
   - Reward per hour calculations
   
4. **Staking Integration**
   - IStakingVault interface calls
   - notifyRewardAmount() security
   - Handling zero/invalid vault address
   
5. **Emergency Controls**
   - Emissions pause mechanism
   - Era progression safety
   - Treasury/vault address updates
   
6. **EIP-712 Implementation**
   - WorkerClaim signature verification
   - Domain separator correctness
   - Nonce management

### Integration Requirements:
- Requires MINTER_ROLE on AIPGTokenV2
- Requires REWARD_DISTRIBUTOR_ROLE on StakingVault (optional)
- Must interact securely with external contracts

---

## 📋 BondedWorkerRegistry - Audit Focus

### Key Areas to Audit:
1. **Access Control & Roles**
   - ADMIN_ROLE management
   - EMISSIONS_CONTROLLER_ROLE for reward tracking
   - Emergency pause controls
   
2. **Staking Mechanism**
   - Worker registration and staking
   - Minimum/maximum stake enforcement
   - Stake withdrawal process
   - Emergency unstaking scenarios
   
3. **Slashing System**
   - Slash amount calculation and limits
   - Slashing authorization controls
   - Slashed funds distribution to treasury
   - Protection against excessive slashing
   
4. **Worker Management**
   - Worker activation/deactivation
   - Model support registration
   - Worker ID to address mapping
   - Off-chain worker ID validation
   
5. **Economic Security**
   - Stake-to-reward ratio
   - Slashing penalties vs network security
   - Minimum stake requirements
   - Worker incentive alignment
   
6. **Token Handling**
   - Safe AIPG token transfers
   - Reentrancy protection on stake/unstake
   - Emergency token recovery
   - Slashed token distribution

### Integration Requirements:
- Requires AIPG token approval from workers
- Called by EmissionsControllerV2 for reward tracking
- Interacts with AIPGTokenV2 for staking

---

## 📚 Additional Contracts (For Reference Only)

**Status**: 🟡 **NOT PART OF THIS AUDIT**  
**Timeline**: Will be audited in future rounds

The following contracts are included in this repository for context and future audit rounds:

1. **GridNFT** - NFT contract for AI-generated art with on-chain parameters
2. **ModelRegistry** - Registry for AI models with constraints
3. **RecipeVault** - Storage for ComfyUI workflow templates
4. **StakingVault** - Token staking mechanism (needed by EmissionsController)

**These are for reference only and NOT part of Audit Round 1.**

## 📝 Audit Deliverables Requested

### For All Three Contracts (AIPGTokenV2 + EmissionsControllerV2 + BondedWorkerRegistry):
- [ ] Full security audit report with executive summary
- [ ] Critical/High/Medium/Low severity findings with remediation steps
- [ ] Gas optimization recommendations
- [ ] Access control analysis for all roles
- [ ] Economic security review (tokenomics, emissions schedule, staking economics)
- [ ] EIP-712 signature implementation review
- [ ] Integration security between all three contracts
- [ ] Slashing mechanism security analysis
- [ ] Test coverage recommendations
- [ ] Deployment checklist and recommendations

### Timeline:
- **Target**: Complete audit within 2-4 weeks
- **Deployment**: EmissionsControllerV2 and BondedWorkerRegistry deployed immediately after approval
- [ ] Recommendations for improvement before mainnet deployment

## Testing Information

All contracts are compiled with:
- Solidity `0.8.24`
- OpenZeppelin contracts (see imports)
- Hardhat development environment

Test deployments available on:
- **Base Sepolia**: Testnet addresses in `docs/ADDRESSES.md`
- **Base Mainnet**: AIPGTokenV2 only (see above)

## Timeline

1. **Week 1-2**: AIPGTokenV2 primary audit
2. **Week 2-3**: Fix findings, prepare deployment plan for secondary contracts
3. **Week 4+**: Deploy secondary contracts, schedule next audit round

## Contact & Questions

For questions about:
- **Architecture**: See `docs/` directory
- **Deployment details**: See `ADDRESSES.md`
- **Test environment**: Hardhat setup in `../production/`

---

**Last Updated**: September 30, 2025  
**Audit Grant Round**: 1 of N (iterative approach)
