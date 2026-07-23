# DOX framework

- DOX is a hierarchy of AGENTS.md files that carry the durable contracts for this repo.
- Agents must follow the DOX chain on every edit.

## Core Contract

- AGENTS.md files are binding work contracts for their subtrees.
- Any work product must stay understandable from the nearest AGENTS.md plus every parent above it.

## Read Before Editing

1. Read this root AGENTS.md.
2. Identify every path you expect to touch.
3. Walk from repo root to each target, reading every AGENTS.md on the way.
4. The nearest AGENTS.md is the local contract; parents hold repo-wide rules.
5. If docs conflict, the closer doc controls local detail, but no child may weaken DOX.

Do not rely on memory — re-read the applicable chain in-session before editing.

## Update After Editing

Every meaningful change requires a DOX pass before the task is done. Update the closest
owning AGENTS.md when a change affects: purpose/scope/ownership; durable structure,
contracts, or workflows; inputs/outputs/permissions/side-effects; or the Child DOX Index.
Remove stale text immediately. Refresh affected parent and child indexes.

## Style

Concise, current, operational. Stable contracts, not diary entries. Broad rules in parents,
concrete detail in children. Delete stale notes instead of explaining history.

---

# aipg-smart-contracts — on-chain layer of the AI Power Grid

## Purpose

The Solidity contracts that hold AIPG value and grid economics on **Base mainnet** (chain
8453): the ERC20 token, Synthetix-style staking, and the **EIP-2535 Diamond ("Grid")** that
carries the model/recipe registries, job anchoring, worker bonding, and reward settlement.
Foundry project (`solc 0.8.24`, `via_ir`). This is the **highest-rigor repo** — code here
moves real money and is immutable once deployed.

## Ownership

- **`contracts/`** — all Solidity. Standalone production tokens + the `grid/` Diamond.
  Owned in its own AGENTS.md.
- **`test/`** — Foundry tests for the Diamond reward/bonding facets. Owned in its own AGENTS.md.
- **`sdk/`** — JavaScript (ethers v6) client SDKs for the Grid modules. Owned in its own AGENTS.md.
- **`scripts/`** — JS verification + bash deployment/cut scripts (hardware-wallet signed).
  Owned in its own AGENTS.md.
- **`docs/`** — `ADDRESSES.md` (source of truth for deployed addresses), tokenomics, staking,
  den-multiplier, worker-bonding, deployment checklist. Read before any deploy.
- **`catalog/`** — GridCatalogV2 schemas, examples, and reviewed registration sources.
- **`deployments/base-mainnet.json`** — machine-readable deployed address manifest.
- **`AUDIT_SCOPE.md` / `SECURITY_AUDIT_REPORT.md` / `security-analysis/`** — audit surface,
  findings, and flattened contracts. Read `AUDIT_SCOPE.md` before touching production contracts.
- **`SECURITY.md`** — private vulnerability-reporting and coordinated-disclosure policy.
- **`.github/workflows/contracts.yml`** — pinned-action CI for build, tests, catalog
  formatting, builder tests, and deployment-script checks.
- **`examples/`, `archive/`** — reference/usage snippets and retired material. Not durable
  boundaries; no DOX child.
- `out/`, `cache/` — generated Foundry output. Never edit or commit.
- `lib/openzeppelin-contracts/`, `lib/forge-std/` — audit-pinned git submodules. Update only
  through an explicit dependency review; never patch vendored code in place.

## Local Contracts

- **Inherit org engineering standards:** `../aipg-documentation/engineering-standards/`
  (core + git + the matching language file). The rules below are repo specializations.
- **Immutable-deploy discipline:** mainnet contracts cannot be patched in place. Treat every
  change as audit-then-deploy; never assume a hotfix path exists.
- **Addresses are canonical in `docs/ADDRESSES.md` + `deployments/base-mainnet.json`.** Do not
  hardcode new addresses elsewhere; update those two and reference them.
- **Production vs reference:** `AIPGTokenV2`, `StakingVault`, and the `grid/` Diamond are live.
  Standalone `ModelRegistry.sol`, `RecipeVault.sol`, `BondedWorkerRegistry.sol`, `GridNFT.sol`
  are reference/superseded — the live equivalents are Diamond facets. Do not confuse them.
- **Off-chain pairing:** the den economy here mirrors `grid-core/grid_api/services/den.py`
  (off-chain den formula) and the settlement bot (cumulative Merkle roots). On-chain stores
  only per-period roots + totals, never per-job/per-worker rows.
- **Token minting is renounced** (150M fixed cap). No code path may assume new mint authority.

## Work Guidance

- Money/settlement paths must stay idempotent and covered by a Foundry test before deploy
  (see `test/`). Each `(periodId, worker)` claim is exactly-once on-chain.
- New env vars / addresses for scripts: read from env, never commit keys; signing is
  hardware-wallet only (Ledger/Trezor) — see `scripts/`.
- Run history-inclusive Gitleaks with `.gitleaks.toml` before public releases.
  Public EVM addresses are allowlisted; a credential finding must be revoked or
  otherwise resolved, never hidden with a broad allowlist.
- Follow the existing Diamond conventions exactly (AppStorage slot, selector cuts, role gating);
  storage layout and selector clashes are silent value-loss bugs.

## Verification

- `git submodule update --init` restores the exact audited dependency commits.
- `forge build` (uses `via_ir`, `solc 0.8.24`) must compile clean.
- `forge test` — facet tests run through a deployed Diamond harness (the production
  delegatecall path), not in isolation. Add/extend tests for any economic change.
- `gitleaks git --redact --config .gitleaks.toml --log-opts='--all' .`

## Child DOX Index

- [contracts/AGENTS.md](contracts/AGENTS.md) — all Solidity: standalone contracts + the Grid Diamond.
- [catalog/AGENTS.md](catalog/AGENTS.md) — V2 catalog manifests and registration-plan inputs.
- [test/AGENTS.md](test/AGENTS.md) — Foundry tests + Diamond harness.
- [sdk/AGENTS.md](sdk/AGENTS.md) — ethers v6 client SDKs.
- [scripts/AGENTS.md](scripts/AGENTS.md) — verification + hardware-wallet deployment scripts.
- [script/AGENTS.md](script/AGENTS.md) — Foundry deployment scripts.
- [docs/AGENTS.md](docs/AGENTS.md) — deployed addresses, economics, and operator docs.
