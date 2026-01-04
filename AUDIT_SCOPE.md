# Audit Scope

## Focus Contracts (Production)

### 1. AIPGTokenV2 ✅ DEPLOYED

**Status**: Live on Base Mainnet  
**Address**: `0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608`  
**Priority**: CRITICAL - Production contract

ERC20 token contract with fixed supply (150M total). **Minting has been permanently renounced.**

**Key Areas to Audit:**
1. **Access Control & Roles**
   - DEFAULT_ADMIN_ROLE management
   - MINTER_ROLE: **RENOUNCED** (no addresses hold this role)
   - PAUSER_ROLE emergency controls

2. **Token Security**
   - MAX_SUPPLY enforcement (150M cap)
   - Minting permanently disabled (renounced)
   - Burning mechanics
   - Transfer functionality

3. **Emergency Controls**
   - Pause/unpause functionality
   - Admin role transfer safety

---

### 2. StakingVault ✅ DEPLOYED

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

---

### 3. Grid ✅ DEPLOYED

**Status**: Live on Base Mainnet  
**Address**: `0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609`  
**Priority**: HIGH - Production contract

Modular proxy contract (EIP-2535 pattern) combining all Grid compute infrastructure.

**Architecture:**
```
Grid.sol (Proxy) - 0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609
├── modules/
│   ├── ModelVault      - 0xf2A3bA5C4b56E85e022c5079B645120CE7B6d199
│   ├── RecipeVault     - 0x58Dc9939FA30C6DE76776eCF24517721D53A9eA0
│   ├── JobAnchor       - 0x1aee3a3e4F2C05814d86cF2426Cf20Ed5c1bfa32
│   ├── WorkerRegistry  - 0x0a3075b1787070210483d3e4845fE58d41c28438
│   ├── RoleManager     - 0x59144e0730638f652B9717379c5CA634da7CE926
│   ├── ModuleManager   - 0xa55eD5bb1a177d43f1A3FfC57dfd2c0cfe65d297
│   ├── ModuleInspector - 0x517e3eFEE7205318eea5d3c51d0d0ABfaB648672
│   └── Ownership       - 0x27f06726F9F29DCcf22e98030A3d34A090103605
├── libraries/
│   ├── GridStorage.sol     ← Shared storage (AppStorage pattern)
│   └── LibGrid.sol         ← Routing logic
└── interfaces/
```

**Key Areas to Audit:**

1. **Proxy Security (EIP-2535)**
   - Function selector routing
   - Module management (add/replace/remove)
   - Storage collision prevention
   - Initialization safety

2. **Shared Storage (GridStorage.sol)**
   - AppStorage pattern implementation
   - Storage slot positioning
   - Cross-module state integrity

3. **Module Security**
   - ModelVault: Model registration, hash uniqueness
   - RecipeVault: Workflow storage, creator permissions
   - JobAnchor: Merkle root anchoring, job verification
   - WorkerRegistry: Bond handling, slash mechanics

4. **Access Control**
   - Role-based permissions across modules
   - ADMIN_ROLE, REGISTRAR_ROLE, ANCHOR_ROLE
   - Pause functionality

5. **Upgrade Safety**
   - ModuleManager restrictions
   - Owner-only upgrades
   - Function selector conflicts

---

## Audit Deliverables

### For AIPGTokenV2 + StakingVault + Grid:
- [ ] Full security audit report with executive summary
- [ ] Critical/High/Medium/Low severity findings with remediation
- [ ] Gas optimization recommendations
- [ ] Access control analysis for all roles
- [ ] Economic security review
- [ ] Proxy/upgrade security assessment (Grid)
- [ ] Storage collision analysis (Grid)
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
- Grid: [BaseScan](https://basescan.org/address/0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609)

**Network**: Base Mainnet (Chain ID: 8453)

---

**Last Updated**: December 2025
