# Audit Scope & Priorities

## Audit Round 2 - Autonomous Fund

**See**: `AUDIT_SCOPE_AUTONOMOUS_FUND.md` for complete audit scope of the Autonomous Fund system.

The Autonomous Fund contracts are **DEPLOYED TO BASE MAINNET** and are ready for audit.

---

## Audit Round 1 - Two Contracts

This audit focuses on **TWO contracts**:

### 1. AIPGTokenV2 (DEPLOYED)

**Status**: - **DEPLOYED TO BASE MAINNET**  
**Address**: `0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608`  
**Priority**: **CRITICAL - PRODUCTION CONTRACT**

This is our primary asset token contract currently live on Base Mainnet. This contract is the foundation of our bridge and token ecosystem.

### 2. EmissionsControllerV2 (PENDING DEPLOYMENT)

**Status**: - **READY FOR DEPLOYMENT**  
**Priority**: **HIGH - DEPLOYMENT PENDING AUDIT**

This contract manages token emissions and distributes rewards to GPU workers. Will be deployed to Base Mainnet immediately after audit approval.

---

## AIPGTokenV2 - Audit Focus

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

## EmissionsControllerV2 - Audit Focus

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

## Additional Contracts (For Reference Only)

**Status**: NOT PART OF THIS AUDIT  
**Timeline**: Will be audited in future rounds

The following contracts are included in this repository for context and future audit rounds:

1. **BondedWorkerRegistry** - Worker staking and slashing registry
2. **GridNFT** - NFT contract for AI-generated art with on-chain parameters
3. **ModelRegistry** - Registry for AI models with constraints
4. **RecipeVault** - Storage for ComfyUI workflow templates
5. **StakingVault** - Token staking mechanism (needed by EmissionsController)

These are for reference only and NOT part of Audit Round 1.

## Audit Deliverables Requested

### For Both Contracts (AIPGTokenV2 + EmissionsControllerV2):
- [ ] Full security audit report with executive summary
- [ ] Critical/High/Medium/Low severity findings with remediation steps
- [ ] Gas optimization recommendations
- [ ] Access control analysis for all roles
- [ ] Economic security review (tokenomics, emissions schedule)
- [ ] EIP-712 signature implementation review
- [ ] Integration security between the two contracts
- [ ] Test coverage recommendations
- [ ] Deployment checklist and recommendations

### Timeline:
- Target: Complete audit within 2-4 weeks
- Deployment: EmissionsControllerV2 deployed immediately after approval
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
