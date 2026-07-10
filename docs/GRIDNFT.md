# GridNFT Contract

## Status

`contracts/GridNFT.sol` is reference/testnet code deployed on Base Sepolia at
`0xa87Eb64534086e914A4437ac75a1b554A10C9934`. It is not listed as a Base
mainnet contract in [ADDRESSES.md](ADDRESSES.md), has no live Grid minting API,
and must not be represented as a production provenance or payment system.

The contract records generation parameters. Recording parameters does not by
itself prove that a worker used those parameters, that the referenced model or
recipe bytes were used, or that another implementation will reproduce the same
artifact.

## Actual Contract Surface

The current source provides:

- ERC-721 transfer/pause behavior, EIP-2981 royalties, and role-based access;
- public and private worker-only mint functions;
- per-token model ID, recipe ID, seed, steps, CFG, dimensions, tier, worker,
  timestamps, prompt/sampler strings, and IPFS metadata;
- local recipe approval and worker-role administration;
- uniqueness of `(modelId, recipeId, seed)` within this contract;
- immediate native-ETH fee splitting between the minting worker and immutable
  protocol treasury;
- optional ciphertext, preview hash, and plaintext commitment for a private
  mint, with an authorized reveal path;
- pause, pricing, recipe, worker, royalty, statistics, and read helpers.

The public mint entrypoint is `mintArtworkComplete`; the private entrypoint is
`mintArtworkPrivate`. Older examples using `mintWithParameters`,
`approveModel`, or `getGenerationParams` do not match this source.

## Trust Boundaries

Several names and fields are assertions, not verified facts:

- `modelRegistryContract` is stored but the mint path does not call it. Any
  numeric `modelId` can currently be recorded.
- `recipeVaultContract` is stored, but minting checks only the contract's local
  `approvedRecipeIds` mapping; it does not fetch or hash the RecipeVault entry.
- `addWorker` grants `WORKER_ROLE` administratively and does not verify a bond
  in WorkerRegistry, despite the source comment.
- `ArtTier.STRICT` and `isReproducible=true` do not execute or validate a model,
  workflow, artifact hash, pHash, or reference result.
- `setArtworkStrings` lets the worker, current token owner, or admin replace the
  prompt, sampler, scheduler, and IPFS hash after mint. These fields are not an
  immutable provenance commitment.
- A used seed is unique only for one model/recipe pair in this contract. Seed
  uniqueness is not evidence of generation uniqueness or fidelity.
- The full `msg.value` is split; the current source does not refund payment
  above the minimum fee.
- Private ciphertext on a public chain is durable public data even when an
  accessor restricts convenient reads. Privacy depends on external encryption,
  key handling, and metadata discipline.

## Reproducibility

No repository test proves universal pixel-identical output across ComfyUI, Grid
API, GPU types, software versions, or quantizations. A perceptual-hash match is
not the same thing as byte identity, and one successful fixture would not prove
all workflows deterministic.

A future certification policy must pin, at minimum:

- exact model/checkpoint, VAE, LoRA/control assets, and content hashes;
- canonical executable recipe/workflow bytes and version;
- sampler, scheduler, precision, seed, dimensions, and all effective inputs;
- runtime/implementation versions and allowed hardware variance;
- artifact content hash plus the approved exact/perceptual comparison rule.

Only a workflow certified under that policy should carry a reproducibility
claim. General image/video jobs must not inherit it.

## Pre-Mainnet Gates

Before mainnet deployment or product integration:

1. Decide whether provenance fields are immutable. Replace or tightly govern
   `setArtworkStrings` and commit canonical metadata/artifact hashes.
2. Validate model and recipe identifiers against the deployed Grid modules and
   bind the exact approved bytes, not only numeric IDs.
3. Bind mint authorization to a real completed Grid job/receipt and prevent
   replay or minting unrelated content.
4. Integrate WorkerRegistry/bond checks if worker collateral is part of the
   security model.
5. Define public/private metadata, encryption, key recovery, reveal, and data
   permanence policy.
6. Review native-ETH fee denomination, overpayment behavior, immediate external
   calls, treasury immutability, royalties, pause powers, and role custody.
7. Add Foundry tests for every role, mint/reveal path, metadata mutation,
   payment edge, replay, registry failure, and malicious receiver.
8. Complete an independent audit, deploy from a reviewed script, verify
   bytecode/configuration, and only then add the address to `ADDRESSES.md`.

See [NFT_SYSTEM_EXPLAINED.md](NFT_SYSTEM_EXPLAINED.md) for the product boundary:
GridNFT is optional media provenance and never ownership of a worker or its
earnings.
