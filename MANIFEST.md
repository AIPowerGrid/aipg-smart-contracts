# Package Contents

## Root Files
| File | Purpose |
|------|---------|
| `README.md` | Overview and quick start |
| `AUDIT_SCOPE.md` | **READ FIRST** - What to audit |
| `SECURITY_AUDIT_REPORT.md` | Internal security analysis |
| `LICENSE` | MIT License |

## contracts/
Production smart contracts.

| File | Status | Description |
|------|--------|-------------|
| `AIPGTokenV2.sol` | ✅ Production | ERC20 token (150M fixed, minting renounced) |
| `StakingVault.sol` | ✅ Production | Synthetix-style staking |
| `BondedWorkerRegistry.sol` | Ready | Worker registry with slashing |
| `GridNFT.sol` | Ready | AI-generated art NFTs |
| `ModelRegistry.sol` | Ready | Model constraints |
| `RecipeVault.sol` | Ready | ComfyUI workflow storage |
| `interfaces/` | - | Contract interfaces |

## docs/
| File | Description |
|------|-------------|
| `ADDRESSES.md` | All deployed addresses |
| `STAKING.md` | Staking system documentation |
| `TOKENOMICS_AND_ECONOMICS.md` | Economic model |
| `DEPLOYMENT_CHECKLIST.md` | Deployment guide |
| `GRIDNFT.md` | NFT contract docs |
| `NFT_SYSTEM_EXPLAINED.md` | NFT system overview |

## security-analysis/
Flattened contracts for security tools + analysis results.

| File | Description |
|------|-------------|
| `FINDINGS.md` | Security findings summary |
| `*_Flattened.sol` | Flattened contracts |

## scripts/
| File | Description |
|------|-------------|
| `interact-aipg-token.js` | Verify token contract |
| `README.md` | Script documentation |

## sdk/
JavaScript SDKs for contract interaction.

## examples/
Reference implementations and usage patterns.

---

## 🔒 Security
- ✅ No secrets or private keys
- ✅ Safe to share with auditors
