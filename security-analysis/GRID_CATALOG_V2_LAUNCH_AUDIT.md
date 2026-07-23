# GridCatalogV2 Launch Audit

**Review date:** 2026-07-22 to 2026-07-23
**Target:** `contracts/GridCatalogV2.sol` and its catalog/deployment tooling
**Network:** Base mainnet (8453), with Base Sepolia (84532) permitted for rehearsal
**Deployment status:** NOT DEPLOYED
**Internal verdict:** Code-ready launch candidate; mainnet deployment remains on hold

This is an internal senior-engineering security review, not an independent
third-party audit. It records the exact evidence and unresolved launch gates so
the contract is not promoted on confidence alone.

## Audited Build Boundary

| Item | Audited value |
|---|---|
| Solidity | `0.8.24` (exact pragma) |
| Foundry | v1.5.1 |
| EVM target | Cancun |
| Optimizer | enabled, 200 runs, `via_ir=true` |
| OpenZeppelin Contracts | v4.9.6, `dc44c9f1a4c3b10af99492eed84f83ed244203f6` |
| forge-std | v1.16.1, `620536fa5277db4e3fd46772d5cbc1ea0696fb43` |
| Contract source SHA-256 | `b9db9395d2a2d2f58b26314b39eb5c8b50313d0e4b2f794c90ca4d3ab5dac7cc` |
| Creation bytecode keccak256 | `0xf2dd263a11fbe0057efc55cae23dc9b2a07e183df05362ce6d80ac7462446f04` |
| Runtime bytecode keccak256 | `0x3f4f16672622bdc42785e8995200bd7f1a79dbaee28baa2d3621b3d90ac655f0` |
| Runtime size | 12,801 bytes; 11,775 bytes below EIP-170 |

OpenZeppelin and forge-std are tracked as git submodules. The deployment script
fingerprints these commits and both bytecodes, refuses a dirty worktree or
modified top-level submodule, and verifies exact runtime bytecode after
broadcast.

## Security Model Reviewed

- Model and recipe records are immutable; lifecycle changes are explicit status
  toggles.
- Slug/version release keys and content IDs cannot be registered twice.
- Recipes require 1-8 unique, strictly sorted, currently active model IDs.
- Executability and NFT eligibility are derived from current recipe/model state.
- NFT permission starts false and belongs to a distinct approver role.
- Pause blocks registration, reactivation, and positive NFT approval while
  preserving emergency deactivation and revocation.
- The default admin uses OpenZeppelin's delayed two-step transfer.
- Admin, registrar, pauser, and NFT approver are required to be four distinct
  nonzero addresses by deployment tooling.
- Registration inputs bind content, release metadata, dependencies, publisher,
  catalog address, and Base chain ID.
- The contract is a provenance/governance registry, not a claim that a worker is
  live, honest, or capable.

## Findings Remediated

### C2-01: Unpinned dependencies

**Severity:** High operational risk
**Resolution:** Fixed

The original checkout relied on ignored, untracked `lib/` contents. A fresh
clone could compile different dependency code or fail entirely. OpenZeppelin
v4.9.6 and forge-std v1.16.1 are now pinned git submodules and are part of the
deployment fingerprint.

### C2-02: Cross-language content IDs were not canonical

**Severity:** High integrity risk
**Resolution:** Fixed

Python's sorted `json.dumps` differs from ECMAScript for values such as `-0.0`,
`1.0`, and `1e-7`. Model and recipe IDs now use the dependency-free RFC 8785 JCS
implementation in `scripts/catalog/canonicalize.mjs`, with an RFC number-vector
regression test.

### C2-03: Recipe dependency metadata was not bound into recipe content

**Severity:** Medium integrity risk
**Resolution:** Fixed

Registration-plan dependencies and output modalities could previously diverge
from the hashed recipe. `_grid.catalog` now binds schema, slug, version, output
modalities, and required model releases into recipe bytes, and the builder
requires exact agreement.

### C2-04: Artifact-root construction lacked explicit framing

**Severity:** Medium integrity risk
**Resolution:** Fixed

The artifact commitment now hashes a versioned domain, a four-byte artifact
count, and ordered raw SHA-256 digests. This removes ambiguity and gives future
root formats a clean upgrade namespace.

### C2-05: Generated Ledger command was invalid and not chain-bound

**Severity:** High deployment risk
**Resolution:** Fixed

Current `cast send` does not accept the generated `--data` form. Commands now
pass calldata positionally and set explicit registrar, Base chain ID, and RPC.
Plans reject chains other than 8453 and 84532.

### C2-06: Deployment command could swallow signer/RPC flags

**Severity:** Critical deployment risk
**Resolution:** Fixed and rehearsed

Variadic constructor arguments preceded later options, allowing Foundry to
consume options as constructor values and fall back to its default RPC. The
script now builds an argument array with RPC, signer, and broadcast options
before constructor arguments.

### C2-07: Deployment did not prove the broadcast artifact

**Severity:** High deployment risk
**Resolution:** Fixed

The send path now verifies receipt success, exact deployed runtime bytecode,
roles, admin delay, and empty model/recipe counts. Mainnet administration must
be a deployed contract, and raw-key signing is unsupported.

### C2-08: Pagination used avoidable overflow-prone arithmetic

**Severity:** Low
**Resolution:** Fixed

Pagination now derives `remaining = source.length - offset`, caps a count, and
increments bounded indices unchecked. This avoids `offset + limit` overflow and
reduces repeated storage/length work.

## Automated Evidence

| Tool or test | Result |
|---|---|
| Full Foundry suite | 83 passed, 0 failed |
| Catalog unit tests | 18 passed |
| Stateful invariants | 3 passed; 49,152 calls; 0 reverts/discards |
| Catalog-only coverage | 90.37% lines, 85.63% statements, 47.06% branches, 95.83% functions |
| Builder unit tests | 10 passed |
| Catalog formatting | passed |
| Node syntax / ShellCheck / bash syntax | passed |
| GitHub Actions gate | added with exact action commits and submodule checkout |
| Slither 0.11.3 | 7 findings, all false positives; no actionable result |
| Aderyn 0.6.8 | 0 high, 2 low, both accepted design properties |
| Semgrep 1.134.0 smart-contract rules | 3 INFO performance suggestions, no security finding |
| Mythril Docker bytecode analysis | 32 SWC-101 reports, all unsupported bytecode-only false positives |
| Gitleaks 8.30.1, all history | 1 real legacy credential candidate remains to verify revoked |

Coverage was run in an isolated catalog-only project with `--ir-minimum`.
Foundry warns that this workaround can make source maps imperfect, so coverage
is supporting evidence rather than a security guarantee.

### Static-analysis triage

- Slither's three strict-equality findings are the intentional nonzero content
  hash existence sentinels. Registration rejects zero IDs. Its four timestamp
  findings are misattributed because the returned structs contain `createdAt`;
  none of the reported comparisons depends on time.
- Aderyn reports privileged governance and a revert inside the dependency loop.
  Governance is intentional and split among Safe/operator roles. Atomic failure
  on any invalid dependency is required; the loop is capped at eight.
- Semgrep suggests a payable constructor and caching mapping reads inside
  dependency loops. A payable constructor would allow accidental ETH trapping,
  and mapping reads refer to different IDs, so neither change is appropriate.
- Mythril received optimized runtime bytecode without source/ABI and labels
  Solidity 0.8 checked arithmetic/revert paths as overflow in every function,
  including pure getters. The reports have no usable source location or
  concrete exploit and conflict with source-aware analysis plus fuzz/invariant
  results. They are retained as a tool limitation, not silently discarded.

## Local Lifecycle Rehearsal

On a clean local Anvil chain configured as chain 8453:

1. Deployed the audited bytecode with four distinct role accounts.
2. Verified exact runtime bytecode and initial zero counts.
3. Generated a deterministic model/recipe plan.
4. Registered one model and one dependent recipe.
5. Verified release lookups, active state, and executability.
6. Enabled NFT permission through the independent approver.
7. Deactivated the model and confirmed NFT eligibility became false.
8. Confirmed unauthorized and duplicate registration calls reverted.

This proves local mechanics. It does not replace a Base Sepolia hardware-wallet
rehearsal or mainnet receipt verification.

## Residual Risks and Launch Gates

### Must close before mainnet deployment

- Obtain an independent review of this exact source/dependency boundary.
- Verify the historical Grid API key found in removed
  `frontend/frontend/app.js` is revoked; it also appears in two superseded repos.
  Do not merely allowlist it or assume retired endpoints make it harmless.
- Create/review the Base Safe and final four role addresses.
- Run a Base Sepolia deployment and registration rehearsal with the intended
  hardware wallet or Safe path.
- Run the existing Base fork test with `BASE_RPC_URL` set; the local full suite
  currently records that case as an explicit no-RPC skip.
- Freeze production manifests, artifact hashes/sizes/licenses, immutable
  `ipfs://` or `ar://` URIs, publisher, and decoded calldata.
- Re-run every command in this report from the exact deployment commit.
- Verify source and bytecode on BaseScan, then update
  `docs/ADDRESSES.md` and `deployments/base-mainnet.json`.

### Accepted residual design risks

- Registrars and approvers are trusted governance actors. A compromised role can
  add or approve bad content, but cannot rewrite existing content IDs.
- On-chain state proves governance provenance, not model availability or output
  quality. Core and validators must enforce those independently.
- Storage grows monotonically. Bounded metadata and pagination contain per-call
  cost, but historical records are intentionally permanent.

## Verdict

No unresolved exploitable Critical, High, or Medium issue was found in the
reviewed catalog code or tooling. The implementation is a strong internal
launch candidate and is materially safer than the initial branch.

**Mainnet status remains HOLD** until the external gates above are closed. No
production deployment is authorized by this report.
