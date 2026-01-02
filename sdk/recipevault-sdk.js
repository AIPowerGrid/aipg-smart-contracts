/**
 * AIPG RecipeVault SDK
 * 
 * Simple SDK for developers to add and retrieve recipes from the
 * Grid Diamond's RecipeVault module on Base Mainnet.
 * 
 * Usage:
 *   const { RecipeSDK } = require('./RecipeSDK');
 *   const sdk = new RecipeSDK(signer);
 *   await sdk.addRecipe({ name: 'My Recipe', ... }, workflowJson);
 */

const { ethers } = require('ethers');
const pako = require('pako');

// ============ CONFIGURATION ============

const DEFAULTS = {
  GRID_DIAMOND: '0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609',
  RPC_URL: 'https://mainnet.base.org',
  CHAIN_ID: 8453,
};

const Compression = {
  None: 0,
  Gzip: 1,
  Brotli: 2
};

// ABI for RecipeVault functions exposed through the Grid Diamond
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
  "function isRecipePublic(uint256 recipeId) external view returns (bool)",
  "function canRecipeCreateNFTs(uint256 recipeId) external view returns (bool)",
  
  // Events
  "event RecipeStored(uint256 indexed recipeId, bytes32 indexed recipeRoot, address creator)",
];

// ============ SDK CLASS ============

class RecipeSDK {
  /**
   * Create a new RecipeSDK instance
   * @param {ethers.Signer|ethers.Provider} signerOrProvider - Signer for writes, Provider for reads
   * @param {Object} options - Optional config overrides
   * @param {string} options.gridDiamond - Grid Diamond contract address
   * @param {string} options.rpcUrl - RPC URL for provider
   */
  constructor(signerOrProvider, options = {}) {
    this.gridDiamond = options.gridDiamond || DEFAULTS.GRID_DIAMOND;
    
    if (signerOrProvider.provider) {
      // It's a signer
      this.signer = signerOrProvider;
      this.provider = signerOrProvider.provider;
    } else {
      // It's a provider
      this.signer = null;
      this.provider = signerOrProvider;
    }
    
    this.contract = new ethers.Contract(
      this.gridDiamond,
      RECIPE_VAULT_ABI,
      this.signer || this.provider
    );
  }

  /**
   * Create SDK with just a private key
   * @param {string} privateKey - Hex private key
   * @param {Object} options - Optional config
   * @returns {RecipeSDK}
   */
  static fromPrivateKey(privateKey, options = {}) {
    const rpcUrl = options.rpcUrl || DEFAULTS.RPC_URL;
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const signer = new ethers.Wallet(privateKey, provider);
    return new RecipeSDK(signer, options);
  }

  /**
   * Create read-only SDK (no signer needed)
   * @param {Object} options - Optional config
   * @returns {RecipeSDK}
   */
  static readOnly(options = {}) {
    const rpcUrl = options.rpcUrl || DEFAULTS.RPC_URL;
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    return new RecipeSDK(provider, options);
  }

  // ============ WRITE FUNCTIONS ============

  /**
   * Add a new recipe to the vault
   * @param {Object} metadata - Recipe metadata
   * @param {string} metadata.name - Recipe name (required)
   * @param {string} metadata.description - Recipe description
   * @param {boolean} metadata.canCreateNFTs - Allow NFT creation (default: true)
   * @param {boolean} metadata.isPublic - Make public (default: true)
   * @param {Object} workflowJson - ComfyUI workflow JSON
   * @returns {Object} { tx, receipt, recipeId, recipeRoot }
   */
  async addRecipe(metadata, workflowJson) {
    if (!this.signer) {
      throw new Error('Signer required to add recipes. Use RecipeSDK.fromPrivateKey()');
    }
    
    if (!metadata.name) {
      throw new Error('Recipe name is required');
    }
    
    // Compress workflow
    const { bytes, recipeRoot } = this.compressWorkflow(workflowJson);
    
    // Check if already exists
    const exists = await this.recipeExists(recipeRoot);
    if (exists) {
      throw new Error(`Recipe already exists with root: ${recipeRoot}`);
    }
    
    // Check size limit
    const maxBytes = await this.getMaxWorkflowBytes();
    const compressedSize = ethers.getBytes(bytes).length;
    if (maxBytes > 0n && BigInt(compressedSize) > maxBytes) {
      throw new Error(`Workflow too large: ${compressedSize} bytes (max: ${maxBytes})`);
    }
    
    // Submit transaction
    const tx = await this.contract.storeRecipe(
      recipeRoot,
      bytes,
      metadata.canCreateNFTs ?? true,
      metadata.isPublic ?? true,
      Compression.Gzip,
      metadata.name,
      metadata.description || ''
    );
    
    const receipt = await tx.wait();
    
    // Extract recipe ID from event
    let recipeId = null;
    const event = receipt.logs.find(log => {
      try {
        const parsed = this.contract.interface.parseLog(log);
        return parsed?.name === 'RecipeStored';
      } catch { return false; }
    });
    
    if (event) {
      const parsed = this.contract.interface.parseLog(event);
      recipeId = Number(parsed.args[0]);
    }
    
    return { tx, receipt, recipeId, recipeRoot };
  }

  /**
   * Update recipe permissions (creator only)
   * @param {number} recipeId - Recipe ID
   * @param {boolean} canCreateNFTs - Allow NFT creation
   * @param {boolean} isPublic - Make public
   * @returns {Object} { tx, receipt }
   */
  async updatePermissions(recipeId, canCreateNFTs, isPublic) {
    if (!this.signer) {
      throw new Error('Signer required');
    }
    
    const tx = await this.contract.updateRecipePermissions(recipeId, canCreateNFTs, isPublic);
    const receipt = await tx.wait();
    return { tx, receipt };
  }

  // ============ READ FUNCTIONS ============

  /**
   * Get a recipe by ID
   * @param {number} recipeId - Recipe ID
   * @returns {Object} Parsed recipe with decompressed workflow
   */
  async getRecipe(recipeId) {
    const raw = await this.contract.getRecipe(recipeId);
    return this.parseRecipe(raw);
  }

  /**
   * Get a recipe by its root hash
   * @param {string} recipeRoot - bytes32 hash
   * @returns {Object} Parsed recipe
   */
  async getRecipeByRoot(recipeRoot) {
    const raw = await this.contract.getRecipeByRoot(recipeRoot);
    return this.parseRecipe(raw);
  }

  /**
   * Get all recipe IDs by a creator
   * @param {string} address - Creator address
   * @returns {number[]} Array of recipe IDs
   */
  async getCreatorRecipes(address) {
    const ids = await this.contract.getCreatorRecipes(address);
    return ids.map(id => Number(id));
  }

  /**
   * Get total recipe count
   * @returns {number}
   */
  async getTotalRecipes() {
    const total = await this.contract.getTotalRecipes();
    return Number(total);
  }

  /**
   * Get max workflow size in bytes
   * @returns {bigint}
   */
  async getMaxWorkflowBytes() {
    return await this.contract.getMaxWorkflowBytes();
  }

  /**
   * Check if a recipe exists by root hash
   * @param {string} recipeRoot - bytes32 hash
   * @returns {boolean}
   */
  async recipeExists(recipeRoot) {
    try {
      const recipe = await this.contract.getRecipeByRoot(recipeRoot);
      return recipe.recipeId > 0n;
    } catch {
      return false;
    }
  }

  // ============ UTILITY FUNCTIONS ============

  /**
   * Compress a workflow JSON to bytes
   * @param {Object} workflowJson - ComfyUI workflow
   * @returns {Object} { bytes, recipeRoot, originalSize, compressedSize }
   */
  compressWorkflow(workflowJson) {
    const jsonString = JSON.stringify(workflowJson);
    const compressed = pako.gzip(jsonString);
    const bytes = ethers.hexlify(compressed);
    const recipeRoot = ethers.keccak256(ethers.toUtf8Bytes(jsonString));
    
    return {
      bytes,
      recipeRoot,
      originalSize: jsonString.length,
      compressedSize: compressed.length,
    };
  }

  /**
   * Calculate recipe root from workflow JSON
   * @param {Object} workflowJson - ComfyUI workflow
   * @returns {string} bytes32 hash
   */
  static calculateRecipeRoot(workflowJson) {
    return ethers.keccak256(ethers.toUtf8Bytes(JSON.stringify(workflowJson)));
  }

  /**
   * Parse raw recipe tuple from contract
   * @param {Array} raw - Raw tuple from contract
   * @returns {Object} Parsed recipe with decompressed workflow
   */
  parseRecipe(raw) {
    const recipe = {
      recipeId: Number(raw.recipeId),
      recipeRoot: raw.recipeRoot,
      creator: raw.creator,
      canCreateNFTs: raw.canCreateNFTs,
      isPublic: raw.isPublic,
      compression: Number(raw.compression),
      createdAt: new Date(Number(raw.createdAt) * 1000),
      name: raw.name,
      description: raw.description,
      workflow: null,
    };

    // Decompress workflow
    try {
      const workflowBytes = ethers.getBytes(raw.workflowData);
      let workflowString;
      
      if (recipe.compression === Compression.Gzip) {
        workflowString = pako.ungzip(workflowBytes, { to: 'string' });
      } else {
        workflowString = new TextDecoder().decode(workflowBytes);
      }
      
      recipe.workflow = JSON.parse(workflowString);
    } catch (e) {
      recipe.workflow = null;
      recipe.workflowError = e.message;
    }

    return recipe;
  }
}

// ============ EXPORTS ============

// Export with both names for compatibility
module.exports = { RecipeSDK, RecipeVaultSDK: RecipeSDK, Compression, DEFAULTS };


