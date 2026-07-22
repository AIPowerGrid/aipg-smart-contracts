# test — Foundry tests for the Grid Diamond

## Purpose

Foundry (`forge-std`) tests for the Diamond's economic facets, run through a real deployed
Diamond so they exercise the production delegatecall + selector-routing + AppStorage path.

## Ownership

- `RewardPool.t.sol`, `DenReporter.t.sol`, `PaymentRouter.t.sol`, `WorkerRegistryBonding.t.sol`,
  `ModelVaultDenMultiplier.t.sol` — facet-level tests for the value/settlement paths.
- `GridCatalogV2.t.sol` — standalone catalog role, immutable-record, dependency,
  deactivation, NFT-approval, pause, and pagination invariants.
- `utils/DiamondHarness.sol` — base test fixture: deploys a fresh `Grid`, cuts in the facets,
  wires roles, exposes the proxy address typed as each facet interface. Most tests inherit this.
- `utils/MockAIPG.sol` — mock ERC20 stand-in for the AIPG token in bond/reward flows.

## Local Contracts

- Test Diamond facets **through the Diamond** (cast the proxy address to a facet interface), never a facet in
  isolation — facets assume they are delegatecalled with the Diamond's storage slot. Isolated
  unit tests give false confidence and miss selector/storage/role bugs. Standalone contracts such
  as `GridCatalogV2` are tested directly.
- The harness is the canonical setup; new facet tests extend `DiamondHarness` rather than
  re-deploying ad hoc.

## Work Guidance

- Every change to a value-handling facet must land with a passing test here; settlement math and
  exactly-once claim invariants are the priority to cover.

## Verification

- `forge test` (fuzz runs = 256 per foundry.toml).

## Child DOX Index

- None — leaf (`utils/` is a helper dir, not a durable boundary).
