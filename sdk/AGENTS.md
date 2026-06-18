# sdk — JavaScript client SDKs (ethers v6)

## Purpose

Thin ethers v6 client wrappers for reading/writing the deployed contracts from JS. Read-only by
default; sign by supplying a private key. For application use, not part of the on-chain trust path.

## Ownership

- `recipevault-sdk.js` — store/retrieve ComfyUI workflows via the **Grid Diamond** RecipeVault
  facet. See `RECIPEVAULT_README.md`. The current/live SDK.
- `modelregistry-sdk.js` — query AI models + constraints.
- `aipg-nft-sdk.js` — GridNFT reads/mints (Sepolia reference contract).
- `sdk-example.js` — runnable usage example.
- `README.md`, `RECIPEVAULT_README.md` — SDK docs + mainnet addresses.

## Local Contracts

- ethers **v6** only (`ethers@6`); do not mix v5 APIs.
- Read addresses from `docs/ADDRESSES.md` / `deployments/base-mainnet.json` — keep the addresses
  embedded here in sync when deployments change; do not invent new ones.
- Never embed private keys; signing keys come from env (`PRIVATE_KEY`) only.
- `modelregistry-sdk.js` / `aipg-nft-sdk.js` target standalone reference contracts, not the live
  Diamond facets — keep that distinction clear to callers.

## Work Guidance

—

## Verification

—

## Child DOX Index

- None — leaf.
