# GridCatalogV2 read client

> The contract is not deployed. Supply an address from the verified deployment
> manifest only after `docs/ADDRESSES.md` lists it.

```js
const { JsonRpcProvider } = require("ethers");
const { GridCatalogV2Client } = require("./grid-catalog-v2");

const provider = new JsonRpcProvider(process.env.BASE_RPC_URL);
const catalog = new GridCatalogV2Client(process.env.GRID_CATALOG_V2_ADDRESS, provider);

const modelIds = await catalog.listModelIds();
const recipeIds = await catalog.listRecipeIds();
const recipe = await catalog.getRecipe(recipeIds[0]);
```

The SDK is intentionally read-only. Registration calldata is generated from
reviewed canonical files by `scripts/catalog/build-plan.py` and signed through a
hardware wallet or Safe. Application code should not hold a catalog registrar
key.

Fetching a manifest or recipe URI is not enough to trust it: parse the JSON,
apply RFC 8785 JCS from `docs/GRID_CATALOG_V2.md`, recompute SHA-256, and
compare it to the on-chain ID before use.
