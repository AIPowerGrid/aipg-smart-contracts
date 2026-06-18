# scripts — verification + deployment

## Purpose

Operational scripts: read-only contract verification (JS) and the Diamond deploy/cut + reward
configuration runbook (bash, hardware-wallet signed).

## Ownership

- `interact-aipg-token.js` — read-only AIPGTokenV2 inspection.
- `add-recipe-test.js` — RecipeVault facet smoke interaction.
- `README.md` — script usage.
- **`deployment/`** — mainnet change runbook (run in order, admin hardware wallet):
  - `deploy-reward-facets.sh` — deploy RewardPool/DenReporter/PaymentRouter + cut into the live
    Grid in one atomic `updateModules`.
  - `configure-rewards.sh` — fund pool (`depositRewards`), set period allocation, grant
    `REPORTER_ROLE` to the settlement bot's hot wallet.
  - `deploy-worker-bonding-facet.sh` — cut the WorkerRegistry upgrade (unbond cooldown + slash).
  - `deploy-denmultiplier-facet.sh`, `set-den-multipliers.sh` — ModelVault den-multiplier facet +
    its config.
  - `upgrade-modelvault-facet.js` — prints the diamondCut plan/selectors for a ModelVault upgrade.

## Local Contracts

- **Hardware-wallet signing only** (`--ledger` default, `--trezor`/`HWFLAG` override). No private
  keys ever touch disk or env. Do not add scripts that sign with a raw key.
- Diamond address + RPC come from env / inline constants pinned to the live Grid
  (`0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609`); keep in sync with `docs/ADDRESSES.md`.
- Deploy scripts mutate **live mainnet immutable state**. Run `deployment/` steps in documented
  order; each cut is one-way. Verify selectors and roles before executing.

## Work Guidance

—

## Verification

—

## Child DOX Index

- None — leaf (`deployment/` is covered above, not a separate boundary).
