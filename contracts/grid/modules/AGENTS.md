# grid/modules — Diamond facets

## Purpose

The business logic of the Grid Diamond. Each facet is delegatecalled by `Grid.sol` and operates
on the shared `GridStorage.AppStorage`. Grouped: infrastructure (Diamond plumbing), registries,
and the reward/settlement economy.

## Ownership

**Diamond plumbing**
- `ModuleManager.sol` — owner-only `updateModules` (add/replace/remove facets). The upgrade lever.
- `ModuleInspector.sol` — introspection: list facets + their selectors (ERC-165 + loupe).
- `Ownership.sol` — ERC-173 owner get/transfer (gates upgrades, not business calls).
- `RoleManager.sol` — grant/revoke `GridStorage` roles; pause/unpause. Admin-gated.

**Registries**
- `ModelVault.sol` — AI model registry (rich metadata: type, IPFS CID / download URL, vram,
  quant/format, capability flags, NSFW). REGISTRAR-gated. Mirrors off-chain ModelVault sync.
- `RecipeVault.sol` — ComfyUI workflow/recipe storage on-chain (creator attribution, NFT/public
  permission flags, `maxWorkflowBytes` cap).
- `JobAnchor.sol` — daily job-receipt anchoring as Merkle roots (root + totals per day); the
  pairwise-hash convention the den settlement reuses.

**Economy (reward/settlement)**
- `WorkerRegistry.sol` — worker registration + bonding (stake AIPG) and `unbond`. Enforces
  `minBondAmount`; pulls/returns AIPG via the token. The unbond-cooldown + slash upgrade
  (see `docs/WORKER_BONDING.md`, `scripts/deployment/deploy-worker-bonding-facet.sh`) is not
  yet cut into this facet — the live facet still returns the full bond on `unbond()`.
- `RewardPool.sol` — custodies the AIPG that funds payouts; deposit + period-allocation +
  period-length config (admin-gated). Pool balance and payout rate are intentionally decoupled.
- `DenReporter.sol` — trusted reporter commits per-period den snapshots as Merkle roots (leaves =
  sorted `[worker, den]`). On-chain stores only roots + totals; the formula is off-chain
  (`system-core/grid_api/services/den.py`).
- `PaymentRouter.sol` — permissionless claim: anyone submits a worker's Merkle proof against the
  period den root; `amount = (workerDen / totalDen) * poolAllocation`; AIPG always goes to the
  leaf's worker address. Each `(periodId, worker)` claimable **exactly once**.

## Local Contracts

- All facets: `using GridStorage for GridStorage.AppStorage;` + `GridStorage.appStorage()`. No
  facet declares its own state variables — state lives only in `AppStorage`.
- Role gating via `s.roles[ROLE][msg.sender]`; the upgrade owner (`LibGrid`) is separate.
- **Value-handling facets (WorkerRegistry, RewardPool, PaymentRouter) are the money path:** keep
  claim/bond/slash idempotent, check-effects-interactions, and ERC20 return values. Every change
  here needs a matching `test/` case (these are the tested ones).
- Merkle convention is fixed across `JobAnchor`/`DenReporter`/`PaymentRouter` — keep leaf
  encoding and pairwise hashing byte-identical to the off-chain settlement bot or proofs fail.

## Work Guidance

- New economic logic → extend the relevant facet AND its test under `test/`; never add untested
  value paths.
- New persistent fields → append to `GridStorage.AppStorage` (see grid AGENTS.md), never reorder.

## Verification

- `forge test` — `test/` covers RewardPool, DenReporter, PaymentRouter, WorkerRegistry bonding,
  and the ModelVault den multiplier, all through the Diamond harness.

## Child DOX Index

- None — leaf.
