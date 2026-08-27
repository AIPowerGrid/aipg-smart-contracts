# Worker bonding & slashing (WorkerRegistry)

Workers lock AIPG into the Grid diamond to register. That bond is collateral:
confirmed protocol violations can be **slashed** after review.
Without a bond a free worker has nothing to lose; the bond is what gives the
grid's trust mechanisms teeth.

> **Status: review candidate, not deployed.** The live WorkerRegistry still has
> immediate `unbond()` behavior. No `SLASHER_ROLE` has been granted, Core does
> not yet synchronize finalized bond state into validator assignments, and
> validator evidence cannot trigger slashing or rewards.

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
mapping(bytes32 => bool) usedSlashEvidence; // APPENDED; exactly-once adjudication IDs
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
| `cancelUnbond()` | `0xfe40c4bf` | worker | Abort unbond, return to active; remains available while paused |
| `withdrawBond()` | `0x66eb9cec` | worker | Return bond after cooldown; remains available while paused |
| `slash(address,uint256,bytes32,string)` | `0x773850c2` | SLASHER | Slash part/all of a bond against one finalized evidence ID |
| `setUnbondingPeriod(uint256)` | `0x114eaf55` | ADMIN | Set default (`0`) or 1–30 day cooldown |
| `setMinBond(uint256)` | `0x6eaae824` | ADMIN | Set a nonzero minimum bond |
| `unbondingPeriod() view` | `0x6cf6d675` | — | Effective cooldown |
| `getUnbondInfo(address) view` | `0x0c64afb2` | — | `(unbondingAt, bondAmount, withdrawable)` |
| `getWorker(address) view` | `0xc011b1c3` | — | Full 8-field Worker struct |
| `getWorkerAt(uint256) view` | `0x62e6e84d` | — | Worker address at a stable enumeration index |
| `getWorkerCount() view` | `0x4d7599f1` | — | Number of unique worker addresses ever registered |
| `isWorkerActive(address) view` | `0xc5689dbf` | — | Current active state |
| `getTotalBonded() view` | `0x5c50c356` | — | Aggregate worker collateral |
| `getMinBond() view` | `0x5990dc2b` | — | Current minimum bond |
| `isSlashEvidenceUsed(bytes32) view` | `0xab0e7d53` | — | Whether an adjudication ID has already been consumed |

`slash` rejects empty targets, zero amounts, amounts above the remaining bond,
zero or previously used evidence IDs, and reasons longer than 256 bytes. The
evidence ID should commit to the finalized assignment/adjudication packet, not a
raw prompt or private payload. A partial slash that leaves less than the minimum
bond is promoted to a full slash so an under-collateralized worker cannot remain
in a limbo state. Fully slashed workers may later register with a new bond; their
historical events and off-chain scorecard remain distinct from their current
active state.

`ADMIN_ROLE` cannot call `slash()` unless that address is separately granted
`SLASHER_ROLE`. This makes an ungranted slasher role an effective dark-deployment
gate rather than a documentation-only promise. Granting or revoking the role is
an explicit, event-emitting governance transaction through `RoleManager`.

A global Grid pause prevents new registrations and new unbond requests. It does
not freeze an already-started exit: a worker may still cancel its cooldown or
withdraw a matured bond while paused.

## Slash destination: the reward pool, by accounting

Bonds transfer **into the diamond** on register, so slashed AIPG is already
physically there. `slash()` routes it to the reward pool with **no token
transfer** — pure internal accounting:

```solidity
w.bondAmount    -= amount;
s.totalBonded   -= amount;
s.totalDeposited += amount;   // becomes reward budget for honest workers
```

The same diamond balance backs both bonds and the reward pool, so this just
reclassifies locked collateral as claimable reward budget. A worker slashed below
`minBondAmount` is deactivated and flagged `isSlashed`.

> **Design choice — slashed funds become reward-pool accounting, not treasury
> revenue or a burn.** Redistribution keeps the incentive local: confirmed bad
> work funds honest workers. Changing this destination would alter custody and
> solvency assumptions and requires a separate contract review and migration
> plan; it is not a cosmetic edit.

## On-chain rollout gates

The source being merged does not authorize a deployment. Rollout requires, in
order:

1. Independent contract and storage-layout review of the exact commit.
2. `scripts/deployment/deploy-worker-bonding-facet.sh --prepare` against Base to
   build/test, validate all 16 selectors, classify each live route, and snapshot
   `totalBonded`. This mode signs and broadcasts nothing.
3. Independent review of the facet bytecode and Safe transaction. `--send`
   requires a clean commit, Base chain 8453, `CONFIRM=YES`, and a Ledger/Trezor.
   If the Diamond owner is a contract, it deploys the facet but only prints the
   owner transaction; it cannot execute the cut.
4. Post-cut verification from the clean reviewed commit that deployed runtime
   bytecode matches exactly, every selector resolves to that facet, and
   `totalBonded` is unchanged from the required pre-cut snapshot.
5. A finalized-block Core bond indexer using `getWorkerCount`, `getWorkerAt`, and
   `getWorker`; reconciliation and reorg tests; and a monitored dark canary.
6. A separate governance decision for a narrowly scoped slasher. The deployment
   script deliberately leaves `SLASHER_ROLE` ungranted.

Do not combine the facet cut, role grant, Core eligibility change, and validator
economic activation into one release.

## Grid integration (off-chain)

Slashing is **never auto-triggered from the request hot path or a single
validator verdict.** Validator evidence is stored and aggregated separately;
disputed or inconclusive assignments have no slash effect. A future enforcement
job may prepare a review packet from finalized quorum evidence, signed receipts,
and on-chain bond state, but a human/governance-controlled signer must approve
the transaction.

Core should read bond state asynchronously from finalized Base blocks and cache
it for assignment policy. Chain RPC availability must not sit in the generation
request path. Before the indexer is proven, bond status is informational only;
it must not be presented as a trust guarantee or used to enable validator
economics.
