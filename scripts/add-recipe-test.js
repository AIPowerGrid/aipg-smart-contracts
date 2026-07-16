#!/usr/bin/env node
/**
 * Add Recipe to RecipeVault via Grid Diamond
 * 
 * Legacy read-only smoke tool for the FLUX example. It never broadcasts.
 * Production recipe writes use deployment/register-ace-step-recipe.sh (or a
 * reviewed equivalent) with a hardware wallet.
 */

require('dotenv').config();
const { ethers } = require('ethers');
const pako = require('pako');
const fs = require('fs');
const path = require('path');

// ============ CONFIGURATION ============

const CONFIG = {
  RPC_URL: 'https://mainnet.base.org',
  CHAIN_ID: 8453,
  
  // Grid Diamond Contract (all calls go through here)
  GRID_DIAMOND: '0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609',
  
  // RecipeVault module (upgraded 2026-01-04)
  RECIPE_VAULT_MODULE: '0x58Dc9939FA30C6DE76776eCF24517721D53A9eA0',
};

// Role required to add recipes
const RECIPE_VAULT_ABI = [
  // Write
  "function storeRecipe(bytes32 recipeRoot, bytes calldata workflowData, bool canCreateNFTs, bool isPublic, uint8 compression, string calldata name, string calldata description) external returns (uint256 recipeId)",
  "function updateRecipePermissions(uint256 recipeId, bool canCreateNFTs, bool isPublic) external",
  
  // Read
  "function getRecipe(uint256 recipeId) external view returns (tuple(uint256 recipeId, bytes32 recipeRoot, bytes workflowData, address creator, bool canCreateNFTs, bool isPublic, uint8 compression, uint256 createdAt, string name, string description))",
  "function getRecipeByRoot(bytes32 recipeRoot) external view returns (tuple(uint256 recipeId, bytes32 recipeRoot, bytes workflowData, address creator, bool canCreateNFTs, bool isPublic, uint8 compression, uint256 createdAt, string name, string description))",
  "function getCreatorRecipes(address creator) external view returns (uint256[])",
  "function getTotalRecipes() external view returns (uint256)",
  "function getMaxWorkflowBytes() external view returns (uint256)",
  "function hasRole(bytes32 role, address account) external view returns (bool)",
  
  // Events
  "event RecipeStored(uint256 indexed recipeId, bytes32 indexed recipeRoot, address creator)",
];

// ============ HELPERS ============

function loadWorkflowTemplate(templatePath, overrides = {}) {
  const raw = fs.readFileSync(templatePath, 'utf8');
  const defaults = {
    '{{WIDTH}}': 1024, '{{HEIGHT}}': 1024, '{{SEED}}': 42,
    '{{STEPS}}': 25, '{{CFG}}': 3.5, '{{SAMPLER}}': 'euler',
    '{{SCHEDULER}}': 'simple', '{{PROMPT}}': 'A stunning photorealistic landscape',
    '{{MODEL_FILE}}': 'flux_krea.safetensors'
  };
  const values = { ...defaults, ...overrides };
  let workflowStr = JSON.stringify(JSON.parse(raw));
  for (const [key, value] of Object.entries(values)) {
    workflowStr = workflowStr.replace(new RegExp(key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'g'), value);
  }
  return JSON.parse(workflowStr);
}

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

function calculateRecipeRoot(workflowJson) {
  return ethers.keccak256(ethers.toUtf8Bytes(JSON.stringify(workflowJson)));
}

function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(2)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

// ============ MAIN ============

async function main() {
  console.log('\n╔════════════════════════════════════════════════════════════╗');
  console.log('║       AIPG RecipeVault - Add Recipe                        ║');
  console.log('║                    🧪 READ-ONLY MODE                        ║');
  console.log('╚════════════════════════════════════════════════════════════╝\n');

  // Connect
  console.log('📡 Connecting to Base Mainnet...');
  const provider = new ethers.JsonRpcProvider(CONFIG.RPC_URL);
  const network = await provider.getNetwork();
  console.log(`   Chain ID: ${network.chainId}`);
  
  const contract = new ethers.Contract(CONFIG.GRID_DIAMOND, RECIPE_VAULT_ABI, provider);

  // Check state
  console.log('\n📊 RecipeVault State:');
  const totalRecipes = await contract.getTotalRecipes();
  const maxBytes = await contract.getMaxWorkflowBytes();
  console.log(`   Total Recipes: ${totalRecipes}`);
  console.log(`   Max Size: ${formatBytes(Number(maxBytes))}`);

  // Load template
  console.log('\n📂 Loading Workflow Template...');
  const templatePath = path.join(__dirname, '..', 'examples', 'flux_krea_template.json');
  
  if (!fs.existsSync(templatePath)) {
    // Try alternate path
    const altPath = path.join(__dirname, '..', '..', 'production', 'flux_krea_template.json');
    if (!fs.existsSync(altPath)) {
      console.error('❌ Template not found');
      console.log('   Expected: examples/flux_krea_template.json');
      process.exit(1);
    }
  }
  
  const workflow = loadWorkflowTemplate(fs.existsSync(templatePath) ? templatePath : path.join(__dirname, '..', '..', 'production', 'flux_krea_template.json'));
  console.log(`   ✓ Loaded (${Object.keys(workflow).length} nodes)`);

  // Compress
  console.log('\n🗜️  Compressing...');
  const compressed = compressWorkflow(workflow);
  console.log(`   ${formatBytes(compressed.originalSize)} → ${formatBytes(compressed.compressedSize)} (${compressed.ratio}% reduction)`);

  if (maxBytes > 0n && BigInt(compressed.compressedSize) > maxBytes) {
    console.error(`❌ Workflow too large! Max: ${formatBytes(Number(maxBytes))}`);
    process.exit(1);
  }

  // Recipe root
  const recipeRoot = calculateRecipeRoot(workflow);
  console.log(`\n🔑 Recipe Root: ${recipeRoot.slice(0, 22)}...`);

  // Check exists
  console.log('\n🔍 Checking if exists...');
  try {
    const existing = await contract.getRecipeByRoot(recipeRoot);
    if (existing.recipeId > 0n) {
      console.log(`   ⚠️  Already exists: Recipe #${existing.recipeId}`);
      console.log(`   Name: ${existing.name}`);
      console.log(`   Creator: ${existing.creator}`);
      return;
    }
  } catch (e) {}
  console.log('   ✓ Recipe is new');

  // Recipe details
  const recipeName = 'Flux KREA v1';
  const recipeDescription = 'High-quality FLUX image generation workflow using KREA AI model.';

  console.log('\n📝 Recipe:');
  console.log(`   Name: ${recipeName}`);
  console.log(`   Can Create NFTs: true`);
  console.log(`   Is Public: true`);

  console.log('\n════════════════════════════════════════════════════════════════');
  console.log('   READ-ONLY CHECK COMPLETE');
  console.log('   Use scripts/deployment/register-ace-step-recipe.sh for reviewed');
  console.log('   hardware-wallet registration of the governed ACE-Step recipe.');
  console.log('════════════════════════════════════════════════════════════════\n');
}

main().catch(console.error);
