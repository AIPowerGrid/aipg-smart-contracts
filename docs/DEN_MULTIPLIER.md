# On-chain den multiplier (ModelVault)

The **den multiplier** is a model's reward "size" weight — bigger models earn
more den (work-credit) per unit of output. To make pricing transparent and
governable (and impossible for a worker to fake by lying about a model name),
the multiplier lives **on-chain in ModelVault**, and the off-chain grid caches
it on an interval.

## Storage & API

`GridStorage.AppStorage` (append-only zone):

```solidity
mapping(uint256 => uint256) denMultiplierE3;  // multiplier x1000
```

`ModelVault` functions (admin-gated):

| Function | Selector | Purpose |
|----------|----------|---------|
| `setDenMultiplier(uint256 modelId, uint256 e3)` | `0x495a7e60` | Set one model's multiplier |
| `setDenMultipliers(uint256[] ids, uint256[] e3)` | `0x35172d70` | Batch set (repopulation) |
| `getDenMultiplier(uint256 modelId) view` | `0xb1a673ed` | Read (0 = unset) |

**Units:** `denMultiplierE3` is the multiplier × 1000, so fractional values are
exact — a 27B model → `27000`, a 7B → `7000`, a 1.5B → `1500`. `0` means unset
(the grid then applies its conservative `DEFAULT_MULTIPLIER`).

## On-chain rollout (admin / hardware wallet)

1. **Cut the facet:** `scripts/deployment/deploy-denmultiplier-facet.sh`
   (deploys a new ModelVault impl and `updateModules`-ADDs the 3 selectors —
   verified the live diamond uses `updateModules` `0xce06baad`, not `diamondCut`).
2. **Register current models** in ModelVault if they aren't already (the live
   registry today holds only legacy image checkpoints; the production text/image
   models need `registerModel`).
3. **Set multipliers:** `scripts/deployment/set-den-multipliers.sh`.

## Grid integration (off-chain, zero hot-path latency)

The grid reads ModelVault on a timer, not per request:

- `grid_api/services/model_registry.py::sync_from_modelvault()` — reads
  `getModelCount`/`getModel`/`getDenMultiplier`, merges active models +
  multipliers into `den.MODEL_REGISTRY`, and sets `den.APPROVED_MODELS`.
- Wired into `main.py` startup + a `MODELVAULT_SYNC_SECONDS` (default 600) loop.
- Reads stay local: `den.estimate_model_multiplier()` / `den.is_model_approved()`.

Enable by setting on the grid: `MODELVAULT_ADDRESS` = the Grid diamond proxy
(`0x79F39f…`), `BASE_RPC_URL` = a Base RPC. Until set, the sync no-ops and the
seeded registry stays authoritative.

**Gating is soft today** (`den.is_model_approved` returns true when the approved
set is empty) so a sync can never strand the live grid by hiding models that
simply aren't registered on-chain yet. Flip to hard enforcement once the real
models are in ModelVault. `getDenMultiplier` is feature-detected, so the grid
sync is safe to run before *and* after the facet is cut.
