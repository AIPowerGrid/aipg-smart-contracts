# GridNFT System - Product Boundary

## Current Status

`GridNFT.sol` is reference/testnet code. It is not deployed on Base mainnet and
there is no live Grid NFT minting API or production mint workflow. See
[GRIDNFT.md](GRIDNFT.md) for the contract interface and current deployment
status.

## What GridNFT Is For

The proposed GridNFT records provenance for a deterministic, approved media
generation. A mint can commit the inputs needed to identify or reproduce that
artifact, including:

- model and approved workflow/recipe identifiers;
- seed and generation parameters;
- target worker address;
- metadata URI and payment split.

This is most meaningful for approved deterministic image workflows where the
network can reproduce the generation and compare the resulting artifact. It is
not a general proof that arbitrary AI output is correct.

## What GridNFT Is Not

- It does not represent ownership of a worker, GPU, or validator.
- It does not register, activate, bond, rank, or authorize a worker.
- Transferring an NFT does not transfer a worker account, payout wallet,
  hardware, reputation, or future earnings.
- Holding an NFT does not grant network governance, staking boosts, validator
  authority, or premium access.
- Worker identity and collateral belong to WorkerRegistry and the core's
  authenticated worker/account records, not ERC-721 ownership.

These boundaries must remain explicit in product copy and integrations. Any
future revenue-right, dynamic-worker, or governance design would be a separate
economic and legal system requiring its own specification and audit.

## Proposed Mint Boundary

A production mint should only be considered after all of the following exist:

1. The model and recipe are approved in the canonical registries.
2. The client explicitly requests deterministic generation and supplies or
   accepts a recorded seed.
3. The completed artifact is stored durably and its content/provenance digest
   is committed.
4. The generation receipt is bound to the actual worker and job.
5. The mint transaction, fee split, metadata mutability, and failure/refund
   behavior are audited.
6. The contract is deployed and its address is added to `ADDRESSES.md`.

Ordinary text, image, and video jobs do not need NFTs. Hot inference remains
off-chain; minting is an optional post-generation action for supported media
workflows.

## Verification Model

Determinism is model- and workflow-specific. For supported image pipelines,
validators may compare a candidate artifact against a trusted re-execution
using cryptographic hashes for exact files and perceptual similarity only where
the specification permits implementation variance. Video and nondeterministic
workflows require a different evidence policy and must not inherit an image
pHash rule by assumption.

## Before Mainnet

- Complete an independent contract audit and address all deployment gates in
  `AUDIT_SCOPE.md`.
- Define immutable versus admin-updatable metadata and disclose that policy.
- Verify model/recipe lookup against the actual Grid modules and ABIs.
- Add end-to-end tests for mint authorization, replay/idempotency, fee splits,
  failed generation, metadata validation, and withdrawal controls.
- Build the user-facing confirmation and transaction-status flow without
  placing a chain transaction in the normal inference request path.
