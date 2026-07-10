# AI Power Grid - Smart Contracts

Production smart contracts for the AI Power Grid decentralized GPU network.

## ✅ Live on Base Mainnet

| Contract | Address | Link |
|----------|---------|------|
| **AIPGTokenV2** | `0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608` | [BaseScan](https://basescan.org/address/0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608) |
| **StakingVault** | `0x3ED14A6D5A48614D77f313389611410d38fd8277` | [BaseScan](https://basescan.org/address/0x3ED14A6D5A48614D77f313389611410d38fd8277) |
| **Grid** | `0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609` | [BaseScan](https://basescan.org/address/0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609) |

The StakingVault remains deployed, but the public passive-rewards program has
ended. Existing stakers can use the
[staking page](https://aipowergrid.io/staking) to review and withdraw positions;
do not describe the deployed contract as an active rewards campaign.

---

## 📁 Structure

```
├── README.md                    ← You are here
├── AUDIT_SCOPE.md               ← What to audit (READ FIRST)
├── SECURITY_AUDIT_REPORT.md     ← Internal security analysis
│
├── contracts/
│   ├── AIPGTokenV2.sol          ← ERC20 token (PRODUCTION)
│   ├── StakingVault.sol         ← Deployed vault; rewards program ended
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

The proxy currently exposes 12 implementations, including the administrative
ModelVault extension and the RewardPool, DenReporter, and PaymentRouter reward
facets. The canonical, on-chain-verified inventory is
[docs/ADDRESSES.md](docs/ADDRESSES.md); do not maintain a second address table
here.

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
