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
  - `deploy-reward-facets.sh` — prepare-by-default atomic RewardPool + PaymentRouter
    replacement that preserves DenReporter and verifies reward/bond accounting before and
    after the Safe cut. Its current purpose is the bond-principal reserve guard. The send path
    requires the reviewed Grid, clean commit, both runtime hashes, owner, both legacy facets,
    complete legacy-selector coverage, and the full accounting/token-balance snapshot emitted
    by `--prepare`; post-cut verification requires the same reviewed source and snapshot.
  - `configure-rewards.sh` — fund pool (`depositRewards`), set period allocation, grant
    `REPORTER_ROLE` to the settlement bot's hot wallet.
  - `deploy-worker-bonding-facet.sh` — prepare-first runbook for the **undeployed**
    WorkerRegistry candidate. Default `--prepare` builds/tests, derives and validates all 16
    selectors, and reads the live routing without a transaction. `--send` requires explicit
    confirmation, clean reviewed source, Base mainnet, and a hardware wallet; contract/Safe
    ownership produces reviewable calldata instead of attempting the cut. `--verify` rebuilds
    the clean reviewed source, matches exact runtime bytecode and every selector route, and
    requires the pre-cut `totalBonded` value. It never grants `SLASHER_ROLE` or changes bond
    parameters. The send path also requires the reviewed commit, runtime hash, Grid, owner,
    legacy facet, and `totalBonded` snapshot emitted by `--prepare`; it refuses any drift. The
    preflight reads every selector owned by the legacy facet and refuses a partial replacement.
  - `deploy-denmultiplier-facet.sh`, `set-den-multipliers.sh` — ModelVault den-multiplier facet +
    its config.
  - `register-ace-step-recipe.sh` — prepares canonical Worker Profile V1 recipe bytes and
    SHA-256 locally; `--send` registers them through the live Diamond with a hardware wallet.
  - `deploy-grid-catalog-v2.sh` — prepare-by-default standalone V2 catalog deployment;
    requires explicit role addresses, enforces chain ID, uses a hardware wallet, and verifies
    roles plus empty initial state after broadcast. No deployment has been authorized yet.
  - `upgrade-modelvault-facet.js` — prints the diamondCut plan/selectors for a ModelVault upgrade.
- **`catalog/build-plan.py`** — validates canonical model manifests and recipes, derives SHA-256
  IDs / artifact roots and keccak release keys, then emits deterministic `cast` calldata plus
  Ledger commands. It never signs or broadcasts.
- **`catalog/canonicalize.mjs`** — dependency-free RFC 8785 JCS implementation used by the plan
  builder so Python, JavaScript, Rust, and Go verifiers derive the same content IDs.
- `catalog/test_build_plan.py` covers deterministic output, Base chain binding, JCS number
  serialization, duplicate-key rejection, immutable URIs, recipe metadata, and the
  worker-advertised model-name dependency check.

## Local Contracts

- **Hardware-wallet signing only** (`--ledger` default, `--trezor`/`HWFLAG` override). No private
  keys ever touch disk or env. Do not add scripts that sign with a raw key.
- Diamond address + RPC come from env / inline constants pinned to the live Grid
  (`0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609`); keep in sync with `docs/ADDRESSES.md`.
- Deploy scripts mutate **live mainnet immutable state**. Run `deployment/` steps in documented
  order; each cut is one-way. Verify selectors and roles before executing.
- Reward and worker-bond facets share one token custodian. Upgrade RewardPool and
  PaymentRouter atomically before enabling bonded workers; never deploy a bonding facet while
  live claims can treat `totalBonded` as reward liquidity.
- WorkerRegistry cuts must replace every selector currently owned by the live WorkerRegistry
  facet and add only previously unrouted selectors. Abort if any candidate selector belongs to
  another facet or any legacy selector is absent from the replacement plan. Preserve and compare
  `totalBonded` across the cut.
- RecipeVault does not recompute `recipeRoot` from `workflowData`; registration scripts must
  canonicalize and verify the content digest before any hardware-wallet broadcast. A stored
  recipe is provenance data, not Core authorization; the signed profile allowlist is authoritative.

## Work Guidance

—

## Verification

- `python3 -m unittest scripts/catalog/test_build_plan.py`
- `node --check scripts/catalog/canonicalize.mjs`
- `shellcheck scripts/deployment/deploy-grid-catalog-v2.sh`
- `shellcheck scripts/deployment/deploy-reward-facets.sh`
- `bash -n scripts/deployment/deploy-worker-bonding-facet.sh`
- `shellcheck scripts/deployment/deploy-worker-bonding-facet.sh`

## Child DOX Index

- None — leaf (`deployment/` is covered above, not a separate boundary).
