# Audit Scope & Priorities

## Primary Focus: AIPGTokenV2 (DEPLOYED)

**Status**: ✅ **DEPLOYED TO BASE MAINNET**  
**Address**: `0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608`  
**Priority**: **CRITICAL - IMMEDIATE AUDIT REQUIRED**

This is our primary asset token contract currently live on Base Mainnet. This contract is the foundation of our bridge and token ecosystem.

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

## Secondary Contracts (NOT YET DEPLOYED)

**Status**: 🟡 **TESTNET ONLY (Base Sepolia)**  
**Timeline**: Deployment planned for coming weeks after initial audit completion  
**Next Audit Round**: Will be included in subsequent audit grants

### Contracts in Development:
1. **EmissionsControllerV2** - Manages token emissions and rewards distribution
2. **GridNFT** - NFT contract for AI model/recipe ownership
3. **ModelRegistry** - Registry for AI models
4. **RecipeVault** - Storage for ComfyUI recipes
5. **StakingVault** - Token staking mechanism

These contracts are included for **reference and preliminary review**, but are NOT production-critical at this time.

## Audit Deliverables Requested

### For AIPGTokenV2 (Primary):
- [ ] Full security audit report
- [ ] Critical/High/Medium/Low severity findings
- [ ] Gas optimization recommendations
- [ ] Access control analysis
- [ ] Economic security review
- [ ] Test coverage recommendations

### For Secondary Contracts (Optional):
- [ ] Preliminary security review
- [ ] Architecture feedback
- [ ] Inter-contract interaction analysis
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
