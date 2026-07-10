# Deployed Contract Addresses

**Network:** Base Mainnet (Chain ID **8453**) · RPC `https://mainnet.base.org` · Explorer https://basescan.org
**Last verified on-chain:** 2026-07-09

> Verified by polling the live contracts directly (`cast`), not from memory. The
> Grid is an EIP-2535 modular diamond — its module set is read from the proxy via
> the DiamondLoupe (`moduleAddresses()`), so this list reflects exactly what is
> live.

---

## ✅ Live on Base Mainnet

### Core

| Contract | Address | Notes |
|----------|---------|-------|
| **AIPGTokenV2** | `0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608` | ERC-20. 150,000,000 max supply, minting permanently disabled. |
| **StakingVault** | `0x3ED14A6D5A48614D77f313389611410d38fd8277` | Deployed 2025-11-01. Passive-rewards program ended; retained for existing-position withdrawals. |
| **Grid (Diamond proxy)** | `0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609` | Modular EIP-2535 proxy. All calls below route through this address. |

### Grid modules (facets behind the proxy)

The proxy currently exposes **12 module implementations**:

| Module | Implementation | Purpose |
|--------|----------------|---------|
| ModuleManager | `0xa55eD5bb1a177d43f1A3FfC57dfd2c0cfe65d297` | Add/replace/remove modules (DiamondCut) |
| ModuleInspector | `0x517e3eFEE7205318eea5d3c51d0d0ABfaB648672` | Introspection (DiamondLoupe) |
| Ownership | `0x27f06726F9F29DCcf22e98030A3d34A090103605` | ERC-173 ownership |
| RoleManager | `0x59144e0730638f652B9717379c5CA634da7CE926` | Access-control roles |
| ModelVault | `0xf2A3bA5C4b56E85e022c5079B645120CE7B6d199` | AI model registry (core fns) |
| **ModelVault — admin updates** | `0xffFbEb80dBA87a7f9004757E55a581d6A988B839` | `updateBaseModel` / `updateModelMetadata` / `updateModelCapabilities`. Added 2026-02-02 (DiamondCut **Add**, tx `0xb3e1a36c…e32f7`). Lets the admin correct fields on already-registered models. |
| RecipeVault | `0x58Dc9939FA30C6DE76776eCF24517721D53A9eA0` | ComfyUI workflow storage |
| JobAnchor | `0x1aee3a3e4F2C05814d86cF2426Cf20Ed5c1bfa32` | Daily job anchoring |
| WorkerRegistry | `0x0a3075b1787070210483d3e4845fE58d41c28438` | GPU worker registry |
| RewardPool | `0x973a82955A3baC4d7d735330090FcE3FDB8E5082` | Period reward pool (deposit + allocation). Added 2026-06-15. |
| DenReporter | `0xf06dEBc2556CeAc3caE09f934AC9aE9529760fd5` | Per-period den Merkle-root snapshots. Added 2026-06-15. |
| PaymentRouter | `0x3fF26503539F3e85E136fDA20042Cf2B4E3Ac65A` | Merkle-proof worker payouts (claim/claimBatch). Added 2026-06-15. |

> **Note — ModelVault spans two implementations.** The original facet
> (`0xf2A3bA…`) serves the core ModelVault functions; the 2026-02-02 upgrade
> *added* three admin-only edit functions in a second implementation
> (`0xffFbEb80…`) without replacing or removing anything. Both are part of the
> same logical ModelVault module and share the diamond's storage. Source:
> `contracts/grid/modules/ModelVault.sol` (selectors `0x1aab6fe9` /
> `0x1852cd90` / `0xb7b66d70` match this source exactly).

### Admin

| Role | Address |
|------|---------|
| Admin / Owner | `0xA218db26ed545f3476e6c3E827b595cf2E182533` |

---

## Reward / settlement contracts (deployed; claim rail not operational)

RewardPool, DenReporter, and PaymentRouter are cut into the diamond (verified
through `moduleAddresses()` on 2026-07-09). Their intended flow is: meter den
off-chain, report a period Merkle root, then claim pro-rata AIPG with proofs.

That intended claim rail is **not the current operational worker payout path**.
Grid core still pays the live bootstrap rail through its custodial hourly AIPG
sender; the Merkle publisher in core remains a scaffold without a live claim
workflow. Treat these facets as deployed infrastructure, not proof that periods
are currently reported or workers currently claim through PaymentRouter.

> Reporting is gated by `REPORTER_ROLE`. Until validator challenges / federation
> co-signing land, a single reporter's risk is bounded to one period's
> allocation. Unaudited — proceed accordingly.

---

## 🗄️ Deprecated / superseded

Earlier standalone testnet contracts (Base Sepolia) have been **superseded by the
Grid modular architecture** and are no longer used:

- `GridNFT` (Sepolia `0xa87Eb645…`) — testnet only
- standalone `RecipeVault` (Sepolia `0x26FAd526…`) → replaced by the Grid RecipeVault module
- standalone `ModelRegistry` (Sepolia `0xe660455D…`) → replaced by the Grid ModelVault module

---

## Token details

**Name:** AI Power Grid · **Symbol:** AIPG · **Decimals:** 18
**Max supply:** 150,000,000 AIPG (minting renounced)
