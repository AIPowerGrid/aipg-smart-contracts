# AIPG RecipeVault SDK

Simple SDK for adding and retrieving ComfyUI workflows from the Grid Diamond's RecipeVault module on Base Mainnet.

## Quick Start

```javascript
const { RecipeSDK } = require('./RecipeSDK');

// Read-only (no signer needed)
const sdk = RecipeSDK.readOnly();
const total = await sdk.getTotalRecipes();

// With private key (for adding recipes)
const sdk = RecipeSDK.fromPrivateKey(process.env.PRIVATE_KEY);
const result = await sdk.addRecipe(
  { name: 'My Workflow', description: 'A cool workflow' },
  workflowJson
);
console.log('Recipe ID:', result.recipeId);
```

## Installation

The SDK requires `ethers` v6 and `pako`:

```bash
npm install ethers@6 pako
```

## Contract Addresses

| Contract | Address |
|----------|---------|
| Grid Diamond | `0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609` |
| RecipeVault Module | `0xddEC9d082FB2B45815Ee104947bfd556d4BD0aa1` |

> **Note:** All calls go through the Grid Diamond, which routes to the RecipeVault module.

## API Reference

### Constructor

```javascript
// With signer (for read + write)
const sdk = new RecipeSDK(signer);

// With provider (read-only)
const sdk = new RecipeSDK(provider);

// Static helpers
const sdk = RecipeSDK.fromPrivateKey('0x...');
const sdk = RecipeSDK.readOnly();
```

### Write Functions

#### `addRecipe(metadata, workflowJson)`

Add a new recipe to the vault.

```javascript
const result = await sdk.addRecipe(
  {
    name: 'Flux KREA v1',              // required
    description: 'High-quality FLUX',   // optional
    canCreateNFTs: true,                // default: true
    isPublic: true                      // default: true
  },
  workflowJson  // ComfyUI workflow object
);

console.log(result.recipeId);    // Recipe ID
console.log(result.recipeRoot);  // bytes32 hash
console.log(result.tx.hash);     // Transaction hash
```

#### `updatePermissions(recipeId, canCreateNFTs, isPublic)`

Update recipe permissions (creator only).

```javascript
await sdk.updatePermissions(1, false, false);  // Make private, no NFTs
```

### Read Functions

#### `getRecipe(recipeId)`

Get a recipe by ID with decompressed workflow.

```javascript
const recipe = await sdk.getRecipe(1);
console.log(recipe.name);
console.log(recipe.workflow);  // Decompressed JSON
```

#### `getRecipeByRoot(recipeRoot)`

Get recipe by its content hash.

```javascript
const recipe = await sdk.getRecipeByRoot('0x...');
```

#### `getCreatorRecipes(address)`

Get all recipe IDs created by an address.

```javascript
const ids = await sdk.getCreatorRecipes('0xabc...');
// [1, 3, 7]
```

#### `getTotalRecipes()`

Get total recipe count.

```javascript
const count = await sdk.getTotalRecipes();
```

#### `recipeExists(recipeRoot)`

Check if a recipe already exists.

```javascript
const exists = await sdk.recipeExists('0x...');
```

### Utility Functions

#### `compressWorkflow(workflowJson)`

Compress workflow for storage.

```javascript
const { bytes, recipeRoot, originalSize, compressedSize } = sdk.compressWorkflow(workflow);
```

#### `RecipeSDK.calculateRecipeRoot(workflowJson)`

Calculate content hash of a workflow.

```javascript
const root = RecipeSDK.calculateRecipeRoot(myWorkflow);
```

## Example: Add a Recipe

```javascript
require('dotenv').config();
const { RecipeSDK } = require('./RecipeSDK');
const fs = require('fs');

async function main() {
  // Load workflow
  const workflow = JSON.parse(fs.readFileSync('my-workflow.json'));
  
  // Create SDK with signer
  const sdk = RecipeSDK.fromPrivateKey(process.env.PRIVATE_KEY);
  
  // Check if already exists
  const root = RecipeSDK.calculateRecipeRoot(workflow);
  if (await sdk.recipeExists(root)) {
    console.log('Recipe already exists!');
    return;
  }
  
  // Add recipe
  const result = await sdk.addRecipe(
    {
      name: 'My Amazing Workflow',
      description: 'Generates stunning images',
      canCreateNFTs: true,
      isPublic: true
    },
    workflow
  );
  
  console.log('✅ Recipe added!');
  console.log('   ID:', result.recipeId);
  console.log('   Root:', result.recipeRoot);
  console.log('   Tx:', result.tx.hash);
}

main();
```

## Example: Read Recipes

```javascript
const { RecipeSDK } = require('./RecipeSDK');

async function main() {
  const sdk = RecipeSDK.readOnly();
  
  // Get total
  const total = await sdk.getTotalRecipes();
  console.log(`Total recipes: ${total}`);
  
  // Get recipe 1
  if (total > 0) {
    const recipe = await sdk.getRecipe(1);
    console.log('Recipe 1:', recipe.name);
    console.log('Workflow nodes:', Object.keys(recipe.workflow).length);
  }
  
  // Get all by creator
  const myRecipes = await sdk.getCreatorRecipes('0x...');
  console.log('My recipes:', myRecipes);
}

main();
```

## Workflow Template Variables

If your workflow uses template variables like `{{PROMPT}}`, replace them before adding:

```javascript
let workflowStr = JSON.stringify(workflow);
workflowStr = workflowStr.replace(/\{\{PROMPT\}\}/g, 'Default prompt');
workflowStr = workflowStr.replace(/\{\{SEED\}\}/g, '42');
const finalWorkflow = JSON.parse(workflowStr);

await sdk.addRecipe({ name: 'My Recipe' }, finalWorkflow);
```

## Error Handling

```javascript
try {
  await sdk.addRecipe({ name: 'Test' }, workflow);
} catch (error) {
  if (error.message.includes('already exists')) {
    console.log('Recipe already on-chain');
  } else if (error.message.includes('too large')) {
    console.log('Workflow exceeds max size');
  } else if (error.message.includes('insufficient funds')) {
    console.log('Need more ETH for gas');
  }
}
```

## Testing

Run the test script to verify everything works:

```bash
# Dry run (no transaction)
node scripts/add-recipe-test.js --dry-run

# Actually add the flux_krea_template.json
PRIVATE_KEY=0x... node scripts/add-recipe-test.js
```


