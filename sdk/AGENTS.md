# sdk — JavaScript client SDKs (ethers v6)

## Purpose

Thin ethers v6 client wrappers for reading/writing the deployed contracts from JS. Read-only by
default; sign by supplying a private key. For application use, not part of the on-chain trust path.

## Ownership

- `grid-catalog-v2.js` — read-only ethers v6 client for the planned V2 catalog. It requires an
  explicit verified address because V2 is not deployed.
- `recipevault-sdk.js` — legacy Diamond RecipeVault helper. Its records and write model are not
  the current catalog path; do not use it for V2 registration.
- `modelregistry-sdk.js` — legacy/reference model registry helper.
- `aipg-nft-sdk.js` — GridNFT reads/mints (Sepolia reference contract).
- `sdk-example.js` — runnable usage example.
- `README.md`, `RECIPEVAULT_README.md` — SDK docs + mainnet addresses.

## Local Contracts

- ethers **v6** only (`ethers@6`); do not mix v5 APIs.
- Read addresses from `docs/ADDRESSES.md` / `deployments/base-mainnet.json` — keep the addresses
  embedded here in sync when deployments change; do not invent new ones.
- Never embed private keys. V2 writes use reviewed calldata plus a hardware wallet or Safe;
  application SDK code stays read-only.
- `modelregistry-sdk.js` / `aipg-nft-sdk.js` target standalone reference contracts, not the live
  Diamond facets — keep that distinction clear to callers.

## Work Guidance

—

## Verification

—

## Child DOX Index

- None — leaf.
