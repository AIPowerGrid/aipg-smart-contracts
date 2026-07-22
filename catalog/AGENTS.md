# catalog - GridCatalogV2 source manifests and registration plans

## Purpose

Schemas, examples, and eventually reviewed production manifests used to derive
the immutable identifiers registered in `GridCatalogV2`.

## Local Contracts

- Production manifests must contain verified artifact hashes, sizes, sources,
  runtime requirements, and license metadata. Never invent or copy an
  unverified digest from a filename.
- Canonical IDs are produced by `scripts/catalog/build-plan.py`; do not compute
  or edit IDs by hand.
- Example files are not registration candidates and must remain under
  `catalog/examples/`.
- A registration plan may reference reviewed recipes in sibling repos, but a
  frozen copy or immutable content URI must exist before mainnet registration.

## Verification

- `python3 scripts/catalog/build-plan.py catalog/examples/registration-plan.json`
- `python3 -m unittest scripts/catalog/test_build_plan.py`
- Review every generated hash, URI, role address, dependency, and calldata blob
  before any hardware-wallet transaction.

## Child DOX Index

- None.
