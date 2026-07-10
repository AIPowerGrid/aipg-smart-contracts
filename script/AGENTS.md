# Foundry Deployment Scripts

## Purpose

Solidity scripts executed by Foundry. This directory currently contains the
standalone `GridRewardDistributor` deployment path; shell/operator scripts live
in sibling `scripts/`.

## Ownership

- `DeployRewardDistributor.s.sol` - deploys the standalone USDC distributor and
  can optionally configure reporter/allocation when the broadcaster is admin.

## Local Contracts

- A fork simulation is not deployment approval. Mainnet broadcast requires a
  reviewed contract commit, independent audit disposition, verified addresses,
  explicit chain ID, multisig/admin plan, and a funded gas sender.
- Default admin and pauser ownership belongs to a reviewed Safe/multisig, not an
  unattended broadcaster key. Reporter privileges must be least-privilege and
  revocable.
- Never put mnemonics/private keys in Foundry commands, `.env`, docs, logs, or
  broadcast artifacts committed to git.
- `GridRewardDistributor` is separate from the deployed Grid Diamond reward
  facets and from the current custodial AIPG payout CLI. Do not conflate their
  addresses, tokens, accounting, or go-live status.

## Work Guidance

- Pin every production address and unit assumption in the reviewed runbook.
- Make configuration explicit; avoid silent mainnet defaults for new scripts.
- Update `docs/ADDRESSES.md` only after receipt and bytecode verification.

## Verification

- Run `forge test` and `forge fmt --check`.
- Run the script without `--broadcast` against a pinned Base fork.
- Verify deployed bytecode, constructor token/admin, roles, and initial
  allocation before any funding.

## Child DOX Index

No child guides are currently required; this file owns `script/`.
