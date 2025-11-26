# AI Power Grid - Smart Contracts

Production smart contracts for the AI Power Grid decentralized GPU network.

## ✅ Live on Base Mainnet

| Contract | Address | Link |
|----------|---------|------|
| **AIPGTokenV2** | `0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608` | [BaseScan](https://basescan.org/address/0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608) |
| **StakingVault** | `0x3ED14A6D5A48614D77f313389611410d38fd8277` | [BaseScan](https://basescan.org/address/0x3ED14A6D5A48614D77f313389611410d38fd8277) |

**Staking UI:** [aipowergrid.io/staking](https://aipowergrid.io/staking)

---

## 📁 Structure

```
├── README.md                    ← You are here
├── AUDIT_SCOPE.md               ← What to audit (READ FIRST)
├── SECURITY_AUDIT_REPORT.md     ← Internal security analysis
│
├── contracts/                   ← Solidity source code
│   ├── AIPGTokenV2.sol          ← ERC20 token (PRODUCTION)
│   ├── StakingVault.sol         ← Staking rewards (PRODUCTION)
│   ├── BondedWorkerRegistry.sol ← Worker registry
│   ├── GridNFT.sol              ← AI art NFTs
│   ├── ModelRegistry.sol        ← Model constraints
│   ├── RecipeVault.sol          ← Workflow storage
│   └── interfaces/              ← Contract interfaces
│
├── docs/                        ← Documentation
│   ├── ADDRESSES.md             ← Deployed addresses
│   ├── STAKING.md               ← How staking works
│   └── TOKENOMICS_AND_ECONOMICS.md
│
├── security-analysis/           ← Flattened contracts + findings
│
├── scripts/                     ← Verification scripts
├── sdk/                         ← JavaScript SDKs
└── examples/                    ← Usage examples
```

---

## 🎯 For Auditors

1. **Start here:** `AUDIT_SCOPE.md`
2. **Review contracts:** `contracts/AIPGTokenV2.sol` and `contracts/StakingVault.sol`
3. **Check findings:** `SECURITY_AUDIT_REPORT.md`
4. **Verify on-chain:** Links in table above

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
| BondedWorkerRegistry | 📋 Ready | Deploy when needed |
| GridNFT | 📋 Ready | Deploy when needed |

---

**Network:** Base Mainnet (Chain ID: 8453)  
**License:** MIT
