#!/usr/bin/env node
/**
 * TEST SCRIPT: Add Recipe to RecipeVault via Grid Diamond
 * 
 * This script demonstrates adding the flux_krea_template.json workflow
 * to the RecipeVault module through the Grid Diamond contract.
 * 
 * Usage:
 *   node scripts/add-recipe-test.js --dry-run              # Test without submitting tx
 *   PRIVATE_KEY=0x... node scripts/add-recipe-test.js      # Actually submit tx
 *   
 *   Or with .env file containing PRIVATE_KEY
 */

require('dotenv').config();
const { ethers } = require('ethers');
const pako = require('pako');
const fs = require('fs');
const path = require('path');

// ============ CONFIGURATION ============

const CONFIG = {
  // Base Mainnet
  RPC_URL: 'https://mainnet.base.org',
  CHAIN_ID: 8453,
  
  // Grid Diamond Contract (routes to RecipeVault module)
  GRID_DIAMOND: '0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609',
  
  // RecipeVault module address (for reference, calls go through diamond)
  RECIPE_VAULT_MODULE: '0xddEC9d082FB2B45815Ee104947bfd556d4BD0aa1',
};

// Compression enum matching Solidity
const Compression = {
  None: 0,
  Gzip: 1,
  Brotli: 2
};

// RecipeVault ABI (the diamond forwards calls to the module)
const RECIPE_VAULT_ABI = [
  // Write functions
  "function storeRecipe(bytes32 recipeRoot, bytes calldata workflowData, bool canCreateNFTs, bool isPublic, uint8 compression, string calldata name, string calldata description) external returns (uint256 recipeId)",
  "function updateRecipePermissions(uint256 recipeId, bool canCreateNFTs, bool isPublic) external",
  "function setMaxWorkflowBytes(uint256 _maxBytes) external",
  
  // Read functions
  "function getRecipe(uint256 recipeId) external view returns (tuple(uint256 recipeId, bytes32 recipeRoot, bytes workflowData, address creator, bool canCreateNFTs, bool isPublic, uint8 compression, uint256 createdAt, string name, string description))",
  "function getRecipeByRoot(bytes32 recipeRoot) external view returns (tuple(uint256 recipeId, bytes32 recipeRoot, bytes workflowData, address creator, bool canCreateNFTs, bool isPublic, uint8 compression, uint256 createdAt, string name, string description))",
  "function getCreatorRecipes(address creator) external view returns (uint256[])",
  "function getTotalRecipes() external view returns (uint256)",
  "function getMaxWorkflowBytes() external view returns (uint256)",
  "function isRecipePublic(uint256 recipeId) external view returns (bool)",
  "function canRecipeCreateNFTs(uint256 recipeId) external view returns (bool)",
  
  // Events
  "event RecipeStored(uint256 indexed recipeId, bytes32 indexed recipeRoot, address creator)",
  "event RecipePermissionsUpdated(uint256 indexed recipeId, bool canCreateNFTs, bool isPublic)"
];

// ============ HELPER FUNCTIONS ============

/**
 * Load and normalize workflow JSON (replace template variables)
 */
function loadWorkflowTemplate(templatePath, overrides = {}) {
  const raw = fs.readFileSync(templatePath, 'utf8');
  let workflow = JSON.parse(raw);
  
  // Default template values (can be overridden)
  const defaults = {
    '{{WIDTH}}': 1024,
    '{{HEIGHT}}': 1024,
    '{{SEED}}': 42,
    '{{STEPS}}': 25,
    '{{CFG}}': 3.5,
    '{{SAMPLER}}': 'euler',
    '{{SCHEDULER}}': 'simple',
    '{{PROMPT}}': 'A beautiful landscape photograph',
    '{{MODEL_FILE}}': 'flux_krea.safetensors'
  };
  
  const values = { ...defaults, ...overrides };
  
  // Replace template variables in the workflow JSON
  let workflowStr = JSON.stringify(workflow);
  for (const [key, value] of Object.entries(values)) {
    workflowStr = workflowStr.replace(new RegExp(key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'g'), value);
  }
  
  return JSON.parse(workflowStr);
}

/**
 * Compress workflow JSON using gzip
 */
function compressWorkflow(workflowJson) {
  const jsonString = JSON.stringify(workflowJson);
  const compressed = pako.gzip(jsonString);
  return {
    bytes: ethers.hexlify(compressed),
    originalSize: jsonString.length,
    compressedSize: compressed.length,
    ratio: ((1 - compressed.length / jsonString.length) * 100).toFixed(1)
  };
}

/**
 * Calculate recipe root (keccak256 of normalized JSON)
 */
function calculateRecipeRoot(workflowJson) {
  const jsonString = JSON.stringify(workflowJson);
  return ethers.keccak256(ethers.toUtf8Bytes(jsonString));
}

/**
 * Format bytes for display
 */
function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(2)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

// ============ MAIN SCRIPT ============

async function main() {
  const DRY_RUN = process.argv.includes('--dry-run');
  
  console.log('\n╔════════════════════════════════════════════════════════════╗');
  console.log('║       AIPG RecipeVault - Add Recipe Test Script            ║');
  if (DRY_RUN) {
    console.log('║                    🧪 DRY RUN MODE                          ║');
  }
  console.log('╚════════════════════════════════════════════════════════════╝\n');

  // Check for private key (not needed for dry run)
  const privateKey = process.env.PRIVATE_KEY;
  if (!privateKey && !DRY_RUN) {
    console.error('❌ PRIVATE_KEY environment variable required');
    console.log('\nUsage:');
    console.log('  node scripts/add-recipe-test.js --dry-run              # Test without tx');
    console.log('  PRIVATE_KEY=0x... node scripts/add-recipe-test.js      # Submit tx');
    console.log('\nOr create a .env file with:');
    console.log('  PRIVATE_KEY=0x...');
    process.exit(1);
  }

  // Setup provider and signer
  console.log('📡 Connecting to Base Mainnet...');
  const provider = new ethers.JsonRpcProvider(CONFIG.RPC_URL);
  
  let signer = null;
  if (!DRY_RUN && privateKey) {
    signer = new ethers.Wallet(privateKey, provider);
    console.log(`   Signer: ${signer.address}`);
    const balance = await provider.getBalance(signer.address);
    console.log(`   Balance: ${ethers.formatEther(balance)} ETH`);
    
    if (balance === 0n) {
      console.error('❌ Wallet has no ETH for gas');
      process.exit(1);
    }
  }
  
  const network = await provider.getNetwork();
  console.log(`   Chain ID: ${network.chainId}`);

  // Connect to Grid Diamond (RecipeVault functions)
  const recipeVault = new ethers.Contract(CONFIG.GRID_DIAMOND, RECIPE_VAULT_ABI, signer || provider);
  
  // Check current state
  console.log('\n📊 Current RecipeVault State:');
  const totalRecipes = await recipeVault.getTotalRecipes();
  const maxBytes = await recipeVault.getMaxWorkflowBytes();
  console.log(`   Total Recipes: ${totalRecipes}`);
  console.log(`   Max Workflow Size: ${formatBytes(Number(maxBytes))}`);

  // Load the flux_krea_template.json
  console.log('\n📂 Loading Flux KREA Template...');
  const templatePath = path.join(__dirname, '..', 'flux_krea_template.json');
  
  if (!fs.existsSync(templatePath)) {
    console.error(`❌ Template not found: ${templatePath}`);
    process.exit(1);
  }
  
  // Load with default values filled in
  const workflow = loadWorkflowTemplate(templatePath, {
    '{{WIDTH}}': 1024,
    '{{HEIGHT}}': 1024,
    '{{SEED}}': 42,
    '{{STEPS}}': 25,
    '{{CFG}}': 3.5,
    '{{SAMPLER}}': 'euler',
    '{{SCHEDULER}}': 'simple',
    '{{PROMPT}}': 'A stunning photorealistic landscape',
    '{{MODEL_FILE}}': 'flux_krea.safetensors'
  });
  
  console.log('   ✓ Loaded workflow template');
  console.log(`   Nodes: ${Object.keys(workflow).length}`);

  // Compress the workflow
  console.log('\n🗜️  Compressing Workflow...');
  const compressed = compressWorkflow(workflow);
  console.log(`   Original: ${formatBytes(compressed.originalSize)}`);
  console.log(`   Compressed: ${formatBytes(compressed.compressedSize)}`);
  console.log(`   Ratio: ${compressed.ratio}% reduction`);
  
  if (maxBytes > 0n && BigInt(compressed.compressedSize) > maxBytes) {
    console.error(`❌ Workflow too large! Max: ${formatBytes(Number(maxBytes))}`);
    process.exit(1);
  }

  // Calculate recipe root
  const recipeRoot = calculateRecipeRoot(workflow);
  console.log(`\n🔑 Recipe Root: ${recipeRoot}`);

  // Check if recipe already exists
  console.log('\n🔍 Checking if recipe exists...');
  try {
    const existing = await recipeVault.getRecipeByRoot(recipeRoot);
    if (existing.recipeId > 0n) {
      console.log(`   ⚠️  Recipe already exists with ID: ${existing.recipeId}`);
      console.log(`   Name: ${existing.name}`);
      console.log(`   Creator: ${existing.creator}`);
      console.log('\n   Skipping add. Use updateRecipePermissions to modify.');
      return;
    }
  } catch (e) {
    // Recipe doesn't exist, continue
  }
  console.log('   ✓ Recipe is new');

  // Prepare recipe metadata
  const recipeName = 'Flux KREA v1';
  const recipeDescription = 'High-quality FLUX image generation workflow using KREA AI fine-tuned model. Supports 1024x1024 output with euler sampler.';

  // Store the recipe
  console.log('\n📝 Recipe Details:');
  console.log(`   Name: ${recipeName}`);
  console.log(`   Description: ${recipeDescription.substring(0, 50)}...`);
  console.log(`   Can Create NFTs: true`);
  console.log(`   Is Public: true`);
  console.log(`   Compression: Gzip`);

  if (DRY_RUN) {
    console.log('\n════════════════════════════════════════════════════════════════');
    console.log('   🧪 DRY RUN COMPLETE - Transaction not submitted');
    console.log('   ');
    console.log('   To actually add this recipe, run:');
    console.log('   PRIVATE_KEY=0x... node scripts/add-recipe-test.js');
    console.log('════════════════════════════════════════════════════════════════\n');
    return;
  }

  console.log('\n📤 Submitting Transaction...');
  try {
    const tx = await recipeVault.storeRecipe(
      recipeRoot,
      compressed.bytes,
      true,  // canCreateNFTs
      true,  // isPublic
      Compression.Gzip,
      recipeName,
      recipeDescription
    );
    
    console.log(`   Transaction hash: ${tx.hash}`);
    console.log('   ⏳ Waiting for confirmation...');
    
    const receipt = await tx.wait();
    console.log(`   ✅ Confirmed in block ${receipt.blockNumber}`);
    console.log(`   Gas used: ${receipt.gasUsed.toString()}`);

    // Parse RecipeStored event
    const event = receipt.logs.find(log => {
      try {
        const parsed = recipeVault.interface.parseLog(log);
        return parsed?.name === 'RecipeStored';
      } catch { return false; }
    });

    if (event) {
      const parsed = recipeVault.interface.parseLog(event);
      const recipeId = parsed.args[0];
      console.log(`\n🎉 Recipe Stored Successfully!`);
      console.log(`   Recipe ID: ${recipeId}`);
      console.log(`   Recipe Root: ${parsed.args[1]}`);
      console.log(`   Creator: ${parsed.args[2]}`);
      
      // Verify by reading back
      console.log('\n🔎 Verifying stored recipe...');
      const stored = await recipeVault.getRecipe(recipeId);
      console.log(`   ✓ Name: ${stored.name}`);
      console.log(`   ✓ Is Public: ${stored.isPublic}`);
      console.log(`   ✓ Can Create NFTs: ${stored.canCreateNFTs}`);
      console.log(`   ✓ Created At: ${new Date(Number(stored.createdAt) * 1000).toISOString()}`);
    }
    
  } catch (error) {
    console.error('\n❌ Transaction failed:', error.message);
    if (error.data) {
      console.error('   Revert reason:', error.data);
    }
    process.exit(1);
  }

  console.log('\n════════════════════════════════════════════════════════════════');
  console.log('   Recipe added successfully! Other devs can now use the SDK');
  console.log('   to add their own recipes using RecipeSDK.js');
  console.log('════════════════════════════════════════════════════════════════\n');
}

// Run
main().catch(console.error);

