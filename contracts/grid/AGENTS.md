# grid — the Grid Diamond (EIP-2535)

## Purpose

The live, upgradeable proxy that unifies all grid compute + economic infrastructure behind one
address (`0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609`). Calls route by function selector to
facet ("module") contracts that all share one storage slot. Single address, hot-swappable
facets, shared state.

## Ownership

- **`Grid.sol`** — the proxy. Constructor cuts in the initial facets, sets owner, registers
  ERC-165/ModuleManager/ModuleInspector interfaces. `fallback` delegatecalls to the facet that
  owns the called selector. Holds no logic of its own beyond routing.
- **`GridInit.sol`** — one-shot initializer (delegatecalled during a cut): seeds token/staking
  addresses, grants the admin the DEFAULT_ADMIN/ADMIN/REGISTRAR/ANCHOR/PAUSER roles (reward/
  reporter roles are granted later via `scripts/deployment/configure-rewards.sh`), and sets
  `minBondAmount` (1000 AIPG) and `maxWorkflowBytes` (100KB) defaults.
- **`libraries/`**
  - `LibGrid.sol` — EIP-2535 routing core: selector→facet map, `updateModules` (add/replace/
    remove), `enforceIsOwner`, owner storage. Its own dedicated storage slot
    (`aipg.grid.core.storage`), separate from app data.
  - `GridStorage.sol` — the **AppStorage** struct + slot (`aipg.grid.storage`): all facet
    business state (models, recipes, workers, roles, den reports, reward pool config) plus enums,
    structs, and role constants. The single source of layout truth.
- **`modules/`** — the facets. Owned in its own AGENTS.md.
- **`interfaces/`** — `IModuleManager`, `IModuleInspector`, `IERC165`, `IERC173`. Standard
  Diamond/EIP interfaces. Trivial; no DOX child.

## Local Contracts

- **One storage slot, append-only layout.** Every facet does
  `GridStorage.AppStorage storage s = GridStorage.appStorage();`. NEVER reorder/insert/retype
  existing fields in `GridStorage.AppStorage` — only append. Reordering corrupts live state.
  Routing storage (`LibGrid`) and app storage (`GridStorage`) live in separate slots; keep them so.
- **Facets are delegatecall-only.** They have no usable state in isolation; never deploy a facet
  expecting it to hold funds or be called directly. Test through the Diamond (see `test/`).
- **Selector uniqueness.** Two facets must not export the same 4-byte selector; a cut that
  clashes is rejected by `LibGrid.updateModules`. Verify selectors before any cut.
- **Owner/role split:** `LibGrid` owner gates *upgrades* (`updateModules`, ownership transfer);
  `GridStorage` roles (ADMIN/REGISTRAR/ANCHOR/PAUSER/DEFAULT_ADMIN, + reward/reporter roles) gate
  *business* calls inside facets. Do not conflate them.

## Work Guidance

- Adding a facet: write the contract under `modules/`, add its tests under `test/`, then cut it
  in via `scripts/deployment/*` (hardware-wallet signed). Update `docs/ADDRESSES.md`.
- New persistent state goes only as appended fields in `GridStorage.AppStorage`.

## Verification

- `forge test` exercises the production delegatecall path via the Diamond harness in `test/utils/`.

## Child DOX Index

- [modules/AGENTS.md](modules/AGENTS.md) — the facets (registries, anchoring, bonding, settlement).
