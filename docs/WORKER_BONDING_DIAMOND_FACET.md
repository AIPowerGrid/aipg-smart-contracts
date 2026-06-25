# Worker bonding & slashing (WorkerRegistry)

Workers lock AIPG into the Grid diamond to register. That bond is collateral:
misbehavior (forged result receipts, repeated garbage output) can be **slashed**.
Without a bond a free worker has nothing to lose; the bond is what gives the
grid's trust mechanisms teeth.

## The slash-escape hole this closes

The original facet let a worker `unbond()` and receive its **full bond back in
the same transaction**. A worker could misbehave and instantly pull its bond
before anyone slashed it — the collateral was never actually at risk.

Unbonding is now **two steps separated by a cooldown**:

```
unbond()        -> mark worker inactive, start cooldown (bond stays locked & slashable)
   ... cooldown (default 7 days) ...
withdrawBond()  -> return the bond, only after the cooldown elapses
```

During the cooldown the bond is **fully slashable**, so a worker can't run from a
slash by quitting. `cancelUnbond()` aborts and returns to active service.

## Storage (append-only, EIP-2535-safe)

`GridStorage`:

```solidity
struct Worker {
    address workerAddress;
    uint256 bondAmount;
    uint256 totalJobsCompleted;
    uint256 totalRewardsEarned;
    uint256 registeredAt;
    bool    isActive;
    bool    isSlashed;
    uint256 unbondingAt;          // APPENDED: 0 = no unbond in progress
}

uint256 unbondingPeriodSeconds;   // APPENDED to AppStorage; 0 => DEFAULT (7 days)
bytes32 constant SLASHER_ROLE = keccak256("SLASHER_ROLE");
```

`unbondingAt` is appended to the **end** of the `Worker` struct. Each `Worker`
lives at its own keccak-spaced region (it's a value in `mapping(address=>Worker)`),
so a trailing field just consumes the next, previously-zero slot — the
already-deployed facets that read the 7-field struct are unaffected. No existing
slot moves.

## Functions

| Function | Selector | Auth | Purpose |
|----------|----------|------|---------|
| `registerWorker(uint256 bond)` | `0x86796f13` | worker | Lock bond, go active (reverts if a prior bond is still in cooldown) |
| `unbond()` | `0x5df6a6bc` | worker | Start cooldown (no transfer) |
| `cancelUnbond()` | `0xfe40c4bf` | worker | Abort unbond, return to active |
| `withdrawBond()` | `0x66eb9cec` | worker | Return bond after cooldown |
| `slash(address,uint256,string)` | `0x678b3ee2` | SLASHER/ADMIN | Slash part/all of a bond |
| `setUnbondingPeriod(uint256)` | `0x114eaf55` | ADMIN | Set cooldown (≤ 30 days) |
| `setMinBond(uint256)` | `0x6eaae824` | ADMIN | Set minimum bond |
| `unbondingPeriod() view` | `0x6cf6d675` | — | Effective cooldown |
| `getUnbondInfo(address) view` | `0x0c64afb2` | — | `(unbondingAt, bondAmount, withdrawable)` |
| `getWorker(address) view` | `0xc011b1c3` | — | Full 8-field Worker struct |
| `isWorkerActive` / `getTotalBonded` / `getMinBond` | — | — | unchanged |

## Slash destination: the reward pool, by accounting

Bonds transfer **into the diamond** on register, so slashed AIPG is already
physically there. `slash()` routes it to the reward pool with **no token
transfer** — pure internal accounting:

```solidity
slashedAmount    = amount;    // or the full bond if `amount` leaves dust below minBond
w.bondAmount     -= slashedAmount;
s.totalBonded    -= slashedAmount;
s.totalDeposited += slashedAmount;   // becomes reward budget for honest workers
```

The same diamond balance backs both bonds and the reward pool, so this just
reclassifies locked collateral as claimable reward budget. A worker slashed below
`minBondAmount` is fully slashed, deactivated, and flagged `isSlashed` so no
below-min dust is stranded in an unusable state.

> **Design choice — slashed funds go to honest workers, not a treasury or burn.**
> Redistribution keeps the incentive local: bad work directly funds the workers
> doing good work. If governance later prefers burn or treasury, that's a
> one-line change in `slash()` (transfer out instead of crediting `totalDeposited`).

## On-chain rollout (admin / hardware wallet)

1. **Preferred security upgrade path:**
   `scripts/deployment/deploy-grid-security-upgrade.sh` — runs the local offline
   suite, deploys only the changed `PaymentRouter` and `WorkerRegistry` facets,
   classifies every selector as ADD or REPLACE, applies one atomic
   `updateModules` cut, and verifies every selector routes to the fresh facet.
   Use:
   `CONFIRM=YES RPC=https://mainnet.base.org HWFLAG=--ledger ./scripts/deployment/deploy-grid-security-upgrade.sh`.
2. **Grant SLASHER_ROLE** to the grid's enforcement key (never the hot request
   path): `grantRole(keccak256("SLASHER_ROLE"), <enforcer>)`.
3. **(Optional)** `setUnbondingPeriod` / `setMinBond` to non-defaults.

`scripts/deployment/deploy-worker-bonding-facet.sh` remains as a focused
WorkerRegistry-only fallback if the payment router has already been upgraded.

## Grid integration (off-chain)

Slashing is **never auto-triggered from the request hot path.** The grid already
collects worker-signed receipts (`ledger.worker_sig`); a forged or mismatched
receipt, or a worker tripping repeated health strikes, is recorded as a
**slashable event** for an operator/enforcement job to review and act on
deliberately. Bond-eligibility is a **soft** signal for routing/priority, not a
gate that can strand the live grid. This mirrors the den-multiplier approach:
on-chain is the source of truth, the grid reads/acts on an interval, and nothing
in the per-request path can block on chain state.
