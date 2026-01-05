# AI Power Grid - Smart Contracts

Production smart contracts for the AI Power Grid decentralized GPU network.

## ✅ Live on Base Mainnet

| Contract | Address | Link |
|----------|---------|------|
| **AIPGTokenV2** | `0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608` | [BaseScan](https://basescan.org/address/0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608) |
| **StakingVault** | `0x3ED14A6D5A48614D77f313389611410d38fd8277` | [BaseScan](https://basescan.org/address/0x3ED14A6D5A48614D77f313389611410d38fd8277) |
| **Grid** | `0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609` | [BaseScan](https://basescan.org/address/0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609) |

**Staking UI:** [aipowergrid.io/staking](https://aipowergrid.io/staking)

---

## 📁 Structure

```
├── README.md                    ← You are here
├── AUDIT_SCOPE.md               ← What to audit (READ FIRST)
├── SECURITY_AUDIT_REPORT.md     ← Internal security analysis
│
├── contracts/
│   ├── AIPGTokenV2.sol          ← ERC20 token (PRODUCTION)
│   ├── StakingVault.sol         ← Staking rewards (PRODUCTION)
│   │
│   └── grid/                    ← Modular Grid Architecture (PRODUCTION)
│       ├── Grid.sol             ← Main proxy contract
│       ├── GridInit.sol         ← Initialization
│       ├── modules/
│       │   ├── ModelVault.sol   ← AI model registry
│       │   ├── RecipeVault.sol  ← Workflow storage
│       │   ├── JobAnchor.sol    ← Job tracking
│       │   ├── WorkerRegistry.sol
│       │   ├── RoleManager.sol
│       │   └── ...
│       ├── libraries/
│       │   ├── GridStorage.sol  ← Shared state
│       │   └── LibGrid.sol      ← Routing logic
│       └── interfaces/
│
├── docs/                        ← Documentation
├── security-analysis/           ← Flattened contracts + findings
├── scripts/                     ← Verification scripts
├── sdk/                         ← JavaScript SDKs
└── examples/                    ← Usage examples
```

---

## 🔷 Grid Architecture (EIP-2535)

Grid uses a **modular proxy pattern** where one contract routes calls to specialized modules:

```
┌─────────────────────────────────────────────────────────┐
│                         GRID                            │
│              0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609 │
├─────────────────────────────────────────────────────────┤
│  registerModel()  →  ModelVault Module                  │
│  storeRecipe()    →  RecipeVault Module                 │
│  anchorDay()      →  JobAnchor Module                   │
│  registerWorker() →  WorkerRegistry Module              │
│  grantRole()      →  RoleManager Module                 │
└─────────────────────────────────────────────────────────┘
```

### Grid Module Addresses (Mainnet)

| Module | Address |
|--------|---------|
| ModuleManager | `0xa55eD5bb1a177d43f1A3FfC57dfd2c0cfe65d297` |
| ModuleInspector | `0x517e3eFEE7205318eea5d3c51d0d0ABfaB648672` |
| Ownership | `0x27f06726F9F29DCcf22e98030A3d34A090103605` |
| RoleManager | `0x59144e0730638f652B9717379c5CA634da7CE926` |
| ModelVault | `0xf2A3bA5C4b56E85e022c5079B645120CE7B6d199` |
| RecipeVault | `0x58Dc9939FA30C6DE76776eCF24517721D53A9eA0` |
| JobAnchor | `0x1aee3a3e4F2C05814d86cF2426Cf20Ed5c1bfa32` |
| WorkerRegistry | `0x0a3075b1787070210483d3e4845fE58d41c28438` |

**Benefits:**
- Single address for all compute infrastructure
- Upgradeable modules without redeployment
- Shared storage across all modules
- Gas-efficient routing

---

## 🎯 For Auditors

1. **Start here:** `AUDIT_SCOPE.md`
2. **Review contracts:** `contracts/AIPGTokenV2.sol` and `contracts/StakingVault.sol`
3. **Review Grid:** `contracts/grid/` (modular architecture)
4. **Check findings:** `SECURITY_AUDIT_REPORT.md`
5. **Verify on-chain:** Links in tables above

---

## 🔧 Quick Start

```bash
npm install
node scripts/interact-aipg-token.js
```

---

## 📋 Production Status

| Contract | Status | Notes |
|----------|--------|-------|
| AIPGTokenV2 | ✅ Live | 150M supply, **minting renounced** |
| StakingVault | ✅ Live | Synthetix-style, no lock period |
| Grid | ✅ Live | Modular proxy (EIP-2535) |
| GridNFT | 📋 Ready | AI-generated art NFTs |

---

**Network:** Base Mainnet (Chain ID: 8453)  
**License:** MIT  
**Last Updated:** 2025-01-05
