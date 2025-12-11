# AI Power Grid - Smart Contracts

Production smart contracts for the AI Power Grid decentralized GPU network.

## ✅ Live on Base Mainnet

| Contract | Address | Link |
|----------|---------|------|
| **AIPGTokenV2** | `0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608` | [BaseScan](https://basescan.org/address/0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608) |
| **StakingVault** | `0x3ED14A6D5A48614D77f313389611410d38fd8277` | [BaseScan](https://basescan.org/address/0x3ED14A6D5A48614D77f313389611410d38fd8277) |

**Staking UI:** [aipowergrid.io/staking](https://aipowergrid.io/staking)

## 🧪 Testnet (Base Sepolia)

| Contract | Address | Link |
|----------|---------|------|
| **Grid** | `0xd66456855dF1A24064000556eef41341a1043FA2` | [BaseScan](https://sepolia.basescan.org/address/0xd66456855dF1A24064000556eef41341a1043FA2) |

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
│   └── grid/                    ← NEW: Modular Grid Architecture
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
│         Single address for all Grid functions           │
├─────────────────────────────────────────────────────────┤
│  registerModel()  →  ModelVault Module                  │
│  storeRecipe()    →  RecipeVault Module                 │
│  anchorDay()      →  JobAnchor Module                   │
│  registerWorker() →  WorkerRegistry Module              │
│  grantRole()      →  RoleManager Module                 │
└─────────────────────────────────────────────────────────┘
```

**Benefits:**
- Single address for all compute infrastructure
- Upgradeable modules without redeployment
- Shared storage across all modules
- Gas-efficient routing

---

## 🎯 For Auditors

1. **Start here:** `AUDIT_SCOPE.md`
2. **Review contracts:** `contracts/AIPGTokenV2.sol` and `contracts/StakingVault.sol`
3. **Review Grid:** `contracts/grid/` (new modular architecture)
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
| Grid | 🧪 Testnet | Modular proxy (Base Sepolia) |
| GridNFT | 📋 Ready | AI-generated art NFTs |

---

**Network:** Base Mainnet (Chain ID: 8453)  
**Testnet:** Base Sepolia (Chain ID: 84532)  
**License:** MIT
