# RecipeVault governance upgrade

> **Status: implemented and tested, not deployed.** The live Base facet remains
> permissionless legacy code until an explicitly approved Diamond cut is mined
> and verified. Core RecipeVault synchronization must remain disabled.

## Why this upgrade exists

The live Diamond RecipeVault contains three historical ComfyUI workflows. It
accepts arbitrary roots and arbitrary compressed bytes from any caller. None of
the three stored roots commits to the Core-canonical decompressed recipe JSON,
so these entries are useful provenance but cannot authorize execution.

The governed facet closes the publication boundary without deleting history:

- only `REGISTRAR_ROLE` or `ADMIN_ROLE` can publish a recipe;
- new workflow bytes must be non-empty, uncompressed, and within the existing
  `maxWorkflowBytes` cap;
- `recipeRoot` must equal SHA-256 of the exact stored bytes;
- only a registrar that created the record, or an admin, can change its public
  and NFT flags;
- compressed and mismatched-root legacy records stay readable but do not become
  authoritative merely because the facet was replaced.

The contract proves content addressing, not that a workflow is safe, supported,
deterministic, economically priced, or currently executable by a worker.

## Core trust boundary

The on-chain flag is one input to Core policy, never executable authority by
itself. Before a recipe can enter an observed or dispatchable cache, Core must:

1. read only from the configured Base chain and pinned Grid Diamond;
2. impose record-count and byte/decompression limits before parsing;
3. require the record to be public and structurally valid;
4. canonicalize JSON and independently recompute the exact SHA-256 root;
5. validate `_grid` metadata, model dependencies, modalities, and local policy;
6. stage the full snapshot before atomically replacing the on-chain cache;
7. evict records that become private or invalid while preserving reviewed local
   fallback recipes;
8. keep Base RPC calls out of the inference request path.

Observe/shadow modes must precede any enforcement. Validator routing, rewards,
staking, strikes, and slashing remain independent gates.

## Upgrade proof

`test/RecipeVaultUpgrade.t.sol` reproduces the exact ten-selector live surface,
stores a compressed legacy record with an arbitrary root, replaces every route,
and proves storage and counters survive. It then proves an unrelated caller
cannot publish, a registrar can publish canonical bytes, and an admin can make a
legacy record non-public.

`scripts/deployment/deploy-recipe-governance-facet.sh` defaults to `--prepare`.
It compiles and tests, validates the exact ten selectors, checks that every live
legacy selector is covered, and creates a SHA-256 commitment over the raw ABI
encoding of every existing recipe at one Base block. The send path additionally
requires a clean reviewed commit, exact runtime hash, owner, old facet, recipe
count, workflow cap, and state commitment. Contract ownership produces Safe
calldata; no role grant is bundled into the cut.

## Deployment gates

1. Merge the facet, tests, script, and Core verifier through green CI.
2. Repeat `--prepare` from clean merged source and independently review every
   printed anchor.
3. Decide the registrar and admin role topology. Do not grant `SLASHER_ROLE`.
4. Obtain explicit transaction approval with the hardware wallet connected.
5. Deploy the facet and execute the exact reviewed ten-selector replacement.
6. Run `--verify` against the merged source and pre-cut recipe-state commitment.
7. Confirm all three legacy records remain readable and no unexpected role was
   granted.
8. Dark-deploy Core verification with sync disabled, then progress through
   observe and shadow canaries before considering enforcement.

No facet deployment, role grant, Core flag, or economic authority is implied by
the presence of this code.
