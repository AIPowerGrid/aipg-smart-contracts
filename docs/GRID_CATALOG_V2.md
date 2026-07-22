# GridCatalogV2

> **Status: implemented and tested, not deployed.** No Base address is
> authoritative until `docs/ADDRESSES.md` and `deployments/base-mainnet.json`
> are updated from a verified deployment receipt.

## Why V2 exists

The Diamond ModelVault and RecipeVault contain legacy Grid records: 32 models
and three recipes as of the 2026-07-22 read-only inventory. They remain useful
history, but they are not a clean catalog for the current text, image, video,
audio, and 3D network.

V2 is a standalone contract instead of another Diamond facet. This gives the
catalog clean storage, an independent audit boundary, and no risk of colliding
with the live Diamond's AppStorage. The Diamond remains the worker, economics,
job-anchor, and settlement layer.

## Trust boundary

`GridCatalogV2` is a governance and provenance registry. It is not a model host,
workflow engine, validator, payment contract, or proof that a worker can execute
a listed model.

- The chain stores immutable hashes, bounded URIs, model dependencies, status,
  and role-governed NFT approval.
- Content-addressed storage carries model manifests and recipe JSON.
- Core downloads content asynchronously, recomputes the canonical hash, checks
  dependencies and policy, and promotes only a verified last-known-good view.
- Inference never performs a Base RPC call in the request path.
- Worker availability and validation remain live off-chain evidence.

## Model identity

A model ID is the SHA-256 digest of its canonical model manifest. The manifest
describes the complete runnable release, including component artifact hashes,
quantization, runtime, source, license, minimum VRAM, modalities, and the exact
model names workers advertise. Registration tooling requires recipe
`_grid.requiredModels` to match those advertised names.

The contract stores:

- `manifestHash` / model ID;
- `artifactRoot`, the SHA-256 commitment to the sorted artifact array;
- hashed canonical slug and version;
- a modality bitmask containing only the defined text, image, video, audio, and
  3D bits;
- minimum VRAM, publisher, manifest URI, timestamp, and active status.

The same slug and version cannot be registered twice. Corrections require a new
version and manifest; historical content is never rewritten.

## Recipe identity

A recipe ID is the SHA-256 digest of canonical recipe JSON, including its
`_grid` policy metadata. The contract stores the content URI, output modalities,
publisher, and 1-8 required V2 model IDs. Required model IDs must be strictly
ascending. This makes the dependency commitment canonical, rejects duplicates,
and keeps on-chain validation linear in the number of dependencies.

A recipe is executable only while it and all required models are active. This
view is a catalog invariant, not proof of current worker capacity.

Recipe registration always starts with `canCreateNfts=false`. A separate
`NFT_APPROVER_ROLE` must explicitly enable it. This flag alone does not mint an
NFT or authorize an NFT contract; any future minting system must independently
bind to the exact V2 recipe ID and require `isRecipeNftEligible(recipeId)`. That
view combines the explicit approval with the current active state of the recipe
and every required model.

## Canonical JSON v1

`scripts/catalog/build-plan.py` is the reference implementation:

1. Parse UTF-8 JSON and reject duplicate object keys.
2. Reject NaN and infinities; manifest numeric fields are integers.
3. Sort object keys recursively.
4. Preserve array order. Model artifact arrays must already be sorted by
   `(role, filename, sha256)`.
   Recipe model IDs are derived by the tool and sorted in ascending byte order.
5. Serialize with UTF-8, no insignificant whitespace, and separators `,` / `:`.
6. Compute SHA-256 over those exact canonical bytes.

Registration plans require `ipfs://` or `ar://` URIs for manifests and recipe
content. Artifact source locations may use HTTPS because the manifest commits
to each artifact's SHA-256 digest and byte size.

Release lookup keys are `keccak256(UTF-8 slug)` and
`keccak256(UTF-8 version)`. Slugs are lowercase ASCII.

## Roles and emergency behavior

| Role | Authority |
|---|---|
| `DEFAULT_ADMIN_ROLE` | Grant/revoke roles. Must be a reviewed Base Safe. A sole-admin, delayed two-step transfer protects changes to this root role. |
| `REGISTRAR_ROLE` | Register and activate/deactivate models and recipes. |
| `PAUSER_ROLE` | Pause/unpause new registrations and positive approvals. |
| `NFT_APPROVER_ROLE` | Explicitly enable or revoke recipe NFT permission. |

While paused, new records, reactivation, and NFT enablement are blocked.
Deactivation and NFT revocation remain available so an emergency freeze cannot
prevent remediation.

The initial default-admin transfer delay is two days. OpenZeppelin's
`AccessControlDefaultAdminRules` governs any delay change and requires the new
admin to accept a scheduled transfer. `publisher` is registrar-approved
attribution metadata; it is not an on-chain signature proving authorship.

## Deployment sequence

1. Complete an independent contract audit and resolve every finding.
2. Create and verify the Base Safe. Use it as `CATALOG_ADMIN`.
3. Choose four distinct admin, registrar, pauser, and NFT-approver addresses so
   the role split is real rather than cosmetic.
4. Run the full Foundry suite and a pinned Base fork deployment.
5. Run `scripts/deployment/deploy-grid-catalog-v2.sh --prepare`.
6. Review role addresses, source digest, bytecode, gas, and target chain.
7. Deploy with `--send` and the Ledger only after explicit approval.
8. Verify source, bytecode, roles, empty counts, and deployment receipt.
9. Update `docs/ADDRESSES.md` and `deployments/base-mainnet.json`.
10. Freeze verified manifests and immutable content URIs.
11. Generate registration calldata with `scripts/catalog/build-plan.py`.
12. Simulate each registration, review the decoded calldata, then sign using
    the registrar hardware wallet or Safe.

## Core migration

V2 must be introduced in phases:

1. **Disabled:** local recipes remain authoritative.
2. **Observe:** sync V2 events/records and compare against the local catalog;
   never dispatch from chain data.
3. **Verify:** fetch every URI, check canonical hashes, model dependencies,
   active status, and allowlisted catalog address.
4. **Shadow:** build a last-known-good V2 cache and report drift.
5. **Enforce:** promote verified V2 entries while retaining cached rollback.

The legacy Diamond vaults remain readable but are never merged automatically
into V2. Migration is explicit and curated, not ID-preserving.

## Local verification record

The 2026-07-22 pre-deployment pass produced the following local evidence:

- full Foundry suite: 80 passed, 0 failed; the Base fork case reported pass but
  explicitly skipped its RPC work because `BASE_RPC_URL` was unset;
- focused `GridCatalogV2Test`: 18 passed, including delayed root-admin transfer,
  role separation, pause behavior, canonical requirements, and lifecycle checks;
- canonical plan-builder unit tests: 6 passed;
- `shellcheck` deployment script and `node --check` read SDK: passed;
- deployed runtime bytecode: 12,871 bytes, below the EIP-170 limit;
- Slither 0.11.3: no actionable finding after manual triage.

Slither reports seven false positives around three zero-hash existence checks
and the NFT-eligibility view. The strict comparisons are intentional sentinels,
and registration rejects zero hashes. Its timestamp detector misattributes
those hash and status checks because the records also contain `createdAt`;
catalog validity does not depend on that timestamp. These results are supporting
evidence only and do not replace the independent audit required before deploy.
