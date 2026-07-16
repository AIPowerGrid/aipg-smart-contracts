# scripts — verification + deployment

## Purpose

Operational scripts: read-only contract verification (JS) and the Diamond deploy/cut + reward
configuration runbook (bash, hardware-wallet signed).

## Ownership

- `interact-aipg-token.js` — read-only AIPGTokenV2 inspection.
- `add-recipe-test.js` — legacy read-only RecipeVault/FLUX smoke interaction;
  its former raw-private-key send path is retired.
- `README.md` — script usage.
- **`deployment/`** — mainnet change runbook (run in order, admin hardware wallet):
  - `deploy-reward-facets.sh` — deploy RewardPool/DenReporter/PaymentRouter + cut into the live
    Grid in one atomic `updateModules`.
  - `configure-rewards.sh` — fund pool (`depositRewards`), set period allocation, grant
    `REPORTER_ROLE` to the settlement bot's hot wallet.
  - `deploy-worker-bonding-facet.sh` — **NOT YET WRITTEN (do not deploy the WorkerRegistry
    facet until it exists + is reviewed).** Will cut the WorkerRegistry upgrade (unbond
    cooldown + slash — task in progress — plus the shipped dedup fix + new `getWorkerCount()`
    view, selector `0x4d7599f1`). The diamondCut MUST **Replace** the currently-live WorkerRegistry
    selectors (`registerWorker`,`unbond`,`getWorker`,`isWorkerActive`,`getTotalBonded`) AND **Add**
    `getWorkerCount()` `0x4d7599f1` — a Replace-only cut would leave the new selector unrouted.
    Verify the full selector set against the deployed facet before executing (one-way cut).
  - `deploy-denmultiplier-facet.sh`, `set-den-multipliers.sh` — ModelVault den-multiplier facet +
    its config.
  - `register-ace-step-recipe.sh` — prepares canonical Worker Profile V1 recipe bytes and
    SHA-256 locally; `--send` registers them through the live Diamond with a hardware wallet.
  - `upgrade-modelvault-facet.js` — prints the diamondCut plan/selectors for a ModelVault upgrade.

## Local Contracts

- **Hardware-wallet signing only** (`--ledger` default, `--trezor`/`HWFLAG` override). No private
  keys ever touch disk or env. Do not add scripts that sign with a raw key.
- Diamond address + RPC come from env / inline constants pinned to the live Grid
  (`0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609`); keep in sync with `docs/ADDRESSES.md`.
- Deploy scripts mutate **live mainnet immutable state**. Run `deployment/` steps in documented
  order; each cut is one-way. Verify selectors and roles before executing.
- RecipeVault does not recompute `recipeRoot` from `workflowData`; registration scripts must
  canonicalize and verify the content digest before any hardware-wallet broadcast. A stored
  recipe is provenance data, not Core authorization; the signed profile allowlist is authoritative.

## Work Guidance

—

## Verification

—

## Child DOX Index

- None — leaf (`deployment/` is covered above, not a separate boundary).
