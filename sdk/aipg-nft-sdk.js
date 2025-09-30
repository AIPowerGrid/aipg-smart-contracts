const { ethers } = require('ethers');

/**
 * AIPG NFT SDK - Simplified interface for minting AI art NFTs
 * 
 * Features:
 * - Approve models and recipes
 * - Mint NFTs with full parameters
 * - Read NFT data from chain
 * - Verify minting success via events
 */
class AIPGNFTClient {
  constructor(config) {
    this.provider = new ethers.JsonRpcProvider(config.rpcUrl);
    this.wallet = new ethers.Wallet(config.privateKey, this.provider);
    this.contractAddress = config.contractAddress;
    
    this.contract = new ethers.Contract(
      this.contractAddress,
      [
        // Admin functions
        'function grantRole(bytes32,address) external',
        'function approveModel(uint256,bool) external',
        'function approveRecipe(uint256,bool) external',
        
        // View functions  
        'function hasRole(bytes32,address) view returns (bool)',
        'function approvedModelIds(uint256) view returns (bool)',
        'function approvedRecipeIds(uint256) view returns (bool)',
        'function baseMintFee() view returns (uint256)',
        
        // Minting
        'function mintArtworkComplete(address,uint256,uint256,uint256,uint16,uint16,uint16,uint16,uint8,string,string,string,string,string) payable returns (uint256)',
        
        // ERC721
        'function ownerOf(uint256) view returns (address)',
        'function artworks(uint256) view returns (tuple(uint256 modelId, uint256 recipeId, uint256 seed, uint16 steps, uint16 cfgTenths, uint16 width, uint16 height, uint8 tier, address worker, uint256 mintTimestamp, bool isReproducible))',
        'function artworkStrings(uint256) view returns (tuple(string prompt, string negativePrompt, string sampler, string scheduler, string ipfsHash))'
      ],
      this.wallet
    );
    
    this.WORKER_ROLE = ethers.keccak256(ethers.toUtf8Bytes('WORKER_ROLE'));
  }

  async getAddress() {
    return await this.wallet.getAddress();
  }

  async getBalance() {
    const balance = await this.provider.getBalance(this.wallet.address);
    return ethers.formatEther(balance);
  }

  /**
   * Grant WORKER role to an address
   */
  async grantWorkerRole(address = null) {
    const target = address || await this.getAddress();
    const tx = await this.contract.grantRole(this.WORKER_ROLE, target, {
      gasLimit: 150000
    });
    
    await tx.wait();
    return tx.hash;
  }

  /**
   * Approve a model for minting
   */
  async approveModel(modelId, approved = true) {
    const tx = await this.contract.approveModel(modelId, approved, {
      gasLimit: 150000
    });
    
    await tx.wait();
    return tx.hash;
  }

  /**
   * Approve a recipe for minting
   */
  async approveRecipe(recipeId, approved = true) {
    const tx = await this.contract.approveRecipe(recipeId, approved, {
      gasLimit: 150000
    });
    
    await tx.wait();
    return tx.hash;
  }

  /**
   * Check if address has required permissions
   */
  async checkPermissions(address = null) {
    const target = address || await this.getAddress();
    
    const hasWorker = await this.contract.hasRole(this.WORKER_ROLE, target);
    
    return {
      address: target,
      hasWorkerRole: hasWorker
    };
  }

  /**
   * Check if model and recipe are approved
   */
  async checkApprovals(modelId, recipeId) {
    const [modelApproved, recipeApproved] = await Promise.all([
      this.contract.approvedModelIds(modelId),
      this.contract.approvedRecipeIds(recipeId)
    ]);
    
    return {
      modelId,
      recipeId,
      modelApproved,
      recipeApproved,
      ready: modelApproved && recipeApproved
    };
  }

  /**
   * Get minting fee
   */
  async getMintFee() {
    const fee = await this.contract.baseMintFee();
    return {
      wei: fee.toString(),
      eth: ethers.formatEther(fee)
    };
  }

  /**
   * Setup prerequisites for minting (role + approvals)
   */
  async setupForMinting(modelId, recipeId) {
    // Check current state
    const permissions = await this.checkPermissions();
    const approvals = await this.checkApprovals(modelId, recipeId);
    
    const tasks = [];
    
    // Grant worker role if needed
    if (!permissions.hasWorkerRole) {
      tasks.push(() => this.grantWorkerRole());
    }
    
    // Approve model if needed
    if (!approvals.modelApproved) {
      tasks.push(() => this.approveModel(modelId));
    }
    
    // Approve recipe if needed
    if (!approvals.recipeApproved) {
      tasks.push(() => this.approveRecipe(recipeId));
    }
    
    // Execute tasks
    for (const task of tasks) {
      await task();
    }
    
    return true;
  }

  /**
   * Mint an NFT with full parameters
   */
  async mintNFT(params) {
    const {
      recipient = null,
      modelId,
      recipeId,
      seed,
      steps,
      cfg,
      width = 1024,
      height = 1024,
      tier = 0,
      prompt,
      negativePrompt = '',
      sampler = 'euler',
      scheduler = 'simple',
      ipfsHash = 'QmPlaceholder'
    } = params;
    
    const to = recipient || await this.getAddress();
    const cfgTenths = Math.round(cfg * 10); // Convert 4.0 to 40
    
    // Get mint fee
    const fee = await this.getMintFee();
    
    // Execute mint
    const tx = await this.contract.mintArtworkComplete(
      to,
      modelId,
      recipeId,
      seed,
      steps,
      cfgTenths,
      width,
      height,
      tier,
      prompt,
      negativePrompt,
      sampler,
      scheduler,
      ipfsHash,
      {
        value: fee.wei,
        gasLimit: 1000000
      }
    );
    
    const receipt = await tx.wait();
    
    if (receipt.status === 0) {
      throw new Error('Mint transaction failed');
    }
    
    // Extract token ID from Transfer event
    const transferTopic = ethers.id('Transfer(address,address,uint256)');
    const transferLog = receipt.logs.find(log => 
      log.topics[0] === transferTopic && 
      log.address.toLowerCase() === this.contractAddress.toLowerCase()
    );
    
    if (!transferLog) {
      throw new Error('No Transfer event found');
    }
    
    const tokenId = ethers.getBigInt(transferLog.topics[3]);
    
    return {
      tokenId: tokenId.toString(),
      txHash: tx.hash,
      blockNumber: receipt.blockNumber,
      gasUsed: receipt.gasUsed.toString(),
      recipient: to
    };
  }

  /**
   * Verify NFT exists and get basic info
   */
  async verifyNFT(tokenId) {
    try {
      const owner = await this.contract.ownerOf(tokenId);
      
      return {
        tokenId,
        exists: true,
        owner,
        contract: this.contractAddress
      };
    } catch (error) {
      return {
        tokenId,
        exists: false,
        error: error.message
      };
    }
  }

  /**
   * Get total supply of NFTs
   */
  async getTotalSupply() {
    try {
      const supply = await this.contract.totalSupply();
      return supply.toString();
    } catch (error) {
      return 'unknown';
    }
  }

  /**
   * Get complete NFT data including artwork and strings
   */
  async getNFTData(tokenId) {
    try {
      const [artwork, strings, owner] = await Promise.all([
        this.contract.artworks(tokenId),
        this.contract.artworkStrings(tokenId),
        this.contract.ownerOf(tokenId)
      ]);

      return {
        tokenId,
        owner,
        artwork: {
          modelId: artwork.modelId.toString(),
          recipeId: artwork.recipeId.toString(),
          seed: artwork.seed.toString(),
          steps: artwork.steps,
          cfgTenths: artwork.cfgTenths,
          width: artwork.width,
          height: artwork.height,
          tier: artwork.tier,
          worker: artwork.worker,
          mintTimestamp: artwork.mintTimestamp.toString(),
          isReproducible: artwork.isReproducible
        },
        strings: {
          prompt: strings.prompt,
          negativePrompt: strings.negativePrompt,
          sampler: strings.sampler,
          scheduler: strings.scheduler,
          ipfsHash: strings.ipfsHash
        }
      };
    } catch (error) {
      throw new Error(`Failed to get NFT data: ${error.message}`);
    }
  }

  /**
   * Complete workflow: setup + mint
   */
  async mintWithSetup(params) {
    const { modelId, recipeId } = params;
    
    // Setup prerequisites
    await this.setupForMinting(modelId, recipeId);
    
    // Mint NFT
    const result = await this.mintNFT(params);
    
    // Verify
    const verification = await this.verifyNFT(result.tokenId);
    
    return {
      ...result,
      verified: verification.exists,
      owner: verification.owner
    };
  }
}

module.exports = { AIPGNFTClient };
