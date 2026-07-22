# contracts — all Solidity (standalone + Grid Diamond)

## Purpose

Every on-chain contract. Two worlds: standalone production contracts at this level, and the
EIP-2535 Diamond under `grid/`.

## Ownership

- **`AIPGTokenV2.sol`** — production ERC20 (OZ Capped/Permit/Burnable/Pausable + AccessControl).
  150M fixed cap, **minting renounced**. Live: `0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608`.
- **`StakingVault.sol`** — production Synthetix-style staking (per-second accrual, manual
  `notifyRewardAmount`, no lock). Live: `0x3ED14A6D5A48614D77f313389611410d38fd8277`.
- **`GridCatalogV2.sol`** — standalone, content-addressed model-manifest and recipe registry.
  It supersedes the legacy Diamond vault data once deployed; no mainnet address exists yet.
- **`grid/`** — the live Grid Diamond (proxy + facets + storage). Owned in its own AGENTS.md.
- **`interfaces/`** — `IAIPGToken`, `IStakingVault`, `ISynthetix`. Shared ABIs for the standalone
  contracts. Trivial; no DOX child.
- **Reference / superseded (NOT the live path):** `ModelRegistry.sol`, `RecipeVault.sol`,
  `BondedWorkerRegistry.sol`, `GridNFT.sol`. The live model/recipe/worker logic is now Diamond
  facets under `grid/modules/`. `GridNFT` is Sepolia-only ("Ready", not mainnet). Do not extend
  these as if they were production.

## Local Contracts

- OZ imports resolve via the `@openzeppelin/` remapping (foundry.toml) → `lib/openzeppelin-contracts/`.
- Standalone contracts are independently deployed and use OZ `AccessControl` roles; the Diamond
  uses its own role system in `grid/libraries/GridStorage.sol`. Do not mix the two role models.
- Any change to a live contract is immutable-deploy: audit first, update `docs/ADDRESSES.md`.

## Work Guidance

—

## Verification

- `forge build` must compile all of `contracts/` clean under `solc 0.8.24` + `via_ir`.

## Child DOX Index

- [grid/AGENTS.md](grid/AGENTS.md) — the EIP-2535 Diamond (proxy, storage, facets).
