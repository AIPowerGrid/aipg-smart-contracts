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
| `BondedWorkerRegistry.sol` | Reference | Worker registry with slashing |
| `GridNFT.sol` | Reference | AI-generated art NFTs |
| `ModelRegistry.sol` | Legacy | Replaced by Grid.ModelVault |
| `RecipeVault.sol` | Legacy | Replaced by Grid.RecipeVault |
| `interfaces/` | - | Contract interfaces |

## contracts/grid/ (NEW)
Modular Grid architecture using EIP-2535 pattern.

| File | Description |
|------|-------------|
| `Grid.sol` | Main proxy contract - single entry point |
| `GridInit.sol` | Initialization helper |

### contracts/grid/modules/
| Module | Description |
|--------|-------------|
| `ModelVault.sol` | AI model registry with IPFS/HTTP storage |
| `RecipeVault.sol` | ComfyUI workflow storage |
| `JobAnchor.sol` | Daily job anchoring with merkle proofs |
| `WorkerRegistry.sol` | Worker bonding and tracking |
| `RoleManager.sol` | Access control (ADMIN, REGISTRAR, ANCHOR roles) |
| `ModuleManager.sol` | Add/replace/remove modules |
| `ModuleInspector.sol` | Introspection (list modules/functions) |
| `Ownership.sol` | ERC-173 ownership |

### contracts/grid/libraries/
| Library | Description |
|---------|-------------|
| `GridStorage.sol` | Shared storage (AppStorage pattern) |
| `LibGrid.sol` | Proxy routing logic |

### contracts/grid/interfaces/
| Interface | Description |
|-----------|-------------|
| `IModuleManager.sol` | Module management |
| `IModuleInspector.sol` | Introspection |
| `IERC165.sol` | Interface detection |
| `IERC173.sol` | Ownership standard |

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
