# docs - contract deployment and operator documentation

## Purpose

Human and agent documentation for deployed Base contracts, staking operations,
Grid modules, reward design, worker bonding, NFT plans, and deployment gates.

## Ownership

- `ADDRESSES.md` - canonical deployed-address and module-status inventory.
- `STAKING.md`, `DEPLOYMENT_CHECKLIST.md` - StakingVault contract operations;
  public product status may differ from contract capability.
- `DEN_MULTIPLIER.md`, `WORKER_BONDING.md` - Grid module design/deploy runbooks.
- `TOKENOMICS_AND_ECONOMICS.md` - protocol economics design.
- `GRIDNFT.md`, `NFT_SYSTEM_EXPLAINED.md` - NFT design; not mainnet production
  unless `ADDRESSES.md` says otherwise.

## Local Contracts

- `ADDRESSES.md` is authoritative only after a fresh read-only Base verification
  through the diamond loupe and code/role checks.
- Distinguish contract deployment from operational use, funding, UI support, and
  off-chain bot readiness. Never label a rail live solely because facets exist.
- Mainnet-mutating commands must exist, be reviewed, and have a dry-run/read-only
  verification step before documentation calls them deployable.
- Do not publish private keys, signer infrastructure, private RPC credentials,
  or security-sensitive validator challenges.

## Work Guidance

- Update deployment manifests, `ADDRESSES.md`, root README, scripts docs, ABIs,
  and dependent core docs together after any cut or deployment.
- Mark superseded/testnet contracts clearly and keep their addresses out of
  current quickstarts.

## Verification

- Read-only: `cast call <grid> 'moduleAddresses()(address[])' --rpc-url <rpc>`.
- Contract changes follow the root Foundry verification gate.
- Docs-only: `git diff --check` and link inspection.

## Child DOX Index

- None - leaf.
