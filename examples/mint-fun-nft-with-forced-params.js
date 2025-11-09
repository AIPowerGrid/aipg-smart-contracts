const { ethers } = require('ethers');
require('dotenv').config();

async function main() {

  const provider = new ethers.JsonRpcProvider(process.env.BASE_SEPOLIA_RPC_URL);
  const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);

  // Use existing GridNFT contract (old structure for now)
  const gridNFTAddress = '0x7d49b017E824aA47Ca36d74a9377A3c1EFb53ef9';
  
  const gridNFTABI = [
    'function mintArtwork(address to, bytes32 recipeRoot, bytes32 renderRoot, uint8 tier, string ipfsHash, string metadataURI) payable returns (uint256)',
    'function getContractStats() view returns (uint256 totalSupply, uint256 totalFees, uint256 workerPayouts, uint256 protocolFees, uint256 currentBaseFee)',
    'function hasRole(bytes32 role, address account) view returns (bool)',
    'function approveRecipe(bytes32 recipeRoot, bool approved) external',
    'function isRecipeApproved(bytes32 recipeRoot) view returns (bool)'
  ];
  
  const gridNFT = new ethers.Contract(gridNFTAddress, gridNFTABI, wallet);
  
  // FORCED PARAMETERS (from the ComfyUI workflow you provided)
  const forcedParams = {
    steps: 20,        // FORCED from workflow
    cfg: 1.0,         // FORCED from workflow  
    sampler: "euler", // FORCED from workflow
    scheduler: "simple", // FORCED from workflow
    width: 1024,      // FORCED from workflow
    height: 1024,     // FORCED from workflow
    model: "flux.1-krea-dev",
    modelFile: "flux1-krea-dev_fp8_scaled.safetensors"
  };

  // NEW VARIABLES (randomized for this mint)
  const randomSeed = Math.floor(Math.random() * 1000000000);
  const funPrompt = "A robot chef making sushi while riding a skateboard through a neon-lit cyberpunk kitchen. The robot has LED eyes that spell out 'DELICIOUS' and is wearing a backwards baseball cap. Cherry blossoms are falling from holographic trees. Epic anime style, highly detailed, absolutely ridiculous but somehow majestic";



  try {
    // Check worker status
    const workerRole = ethers.keccak256(ethers.toUtf8Bytes("WORKER_ROLE"));
    const isWorker = await gridNFT.hasRole(workerRole, await wallet.getAddress());
    
    if (!isWorker) {
      return;
    }

    // Get current stats
    const stats = await gridNFT.getContractStats();
    const nextTokenId = Number(stats.totalSupply) + 1;
    const baseFee = stats.currentBaseFee;


    // Create metadata object that represents the NEW NFT architecture
    const nftMetadata = {
      // Forced deterministic parameters
      steps: forcedParams.steps,
      cfg: forcedParams.cfg,
      sampler: forcedParams.sampler,
      scheduler: forcedParams.scheduler,
      width: forcedParams.width,
      height: forcedParams.height,
      model: forcedParams.model,
      modelFile: forcedParams.modelFile,
      
      // Variable parameters (unique to this NFT)
      seed: randomSeed,
      prompt: funPrompt,
      negativePrompt: "",
      
      // Metadata
      version: "deterministic-v1",
      mintedAt: new Date().toISOString(),
      blockchain: "Base Sepolia",
      framework: "NFT-Generation-Framework"
    };

    // Create recipe root (hash of the deterministic workflow structure)
    const workflowStructure = {
      steps: forcedParams.steps,
      cfg: forcedParams.cfg,
      sampler: forcedParams.sampler,
      scheduler: forcedParams.scheduler,
      model: forcedParams.model,
      workflow: "flux-krea-deterministic-v1"
    };
    const recipeRoot = ethers.keccak256(ethers.toUtf8Bytes(JSON.stringify(workflowStructure)));

    // Create render root (commitment to this specific generation)
    const renderCommitment = {
      seed: randomSeed,
      prompt: funPrompt,
      timestamp: nftMetadata.mintedAt
    };
    const renderRoot = ethers.keccak256(ethers.toUtf8Bytes(JSON.stringify(renderCommitment)));


    // Check and approve recipe if needed
    const isApproved = await gridNFT.isRecipeApproved(recipeRoot);
    
    if (!isApproved) {
      
      const approveTx = await gridNFT.approveRecipe(recipeRoot, true, {
        gasLimit: 100000,
        maxFeePerGas: ethers.parseUnits('0.1', 'gwei'),
        maxPriorityFeePerGas: ethers.parseUnits('0.01', 'gwei')
      });
      
      await approveTx.wait();
      
      // Wait a moment to avoid nonce conflicts
      await new Promise(resolve => setTimeout(resolve, 5000));
    } else {
    }

    // Mint the NFT
    
    const mintTx = await gridNFT.mintArtwork(
      await wallet.getAddress(), // to
      recipeRoot,                 // recipeRoot (deterministic workflow)
      renderRoot,                 // renderRoot (generation commitment)
      1,                          // tier (STRICT)
      "pending-generation",       // ipfsHash
      "",                         // metadataURI
      {
        value: baseFee,
        gasLimit: 500000,
        maxFeePerGas: ethers.parseUnits('0.2', 'gwei'), // Higher gas
        maxPriorityFeePerGas: ethers.parseUnits('0.02', 'gwei') // Higher priority
      }
    );

    const receipt = await mintTx.wait();

    // Find the tokenId from events
    const mintEvent = receipt.logs.find(log => {
      try {
        const parsed = gridNFT.interface.parseLog(log);
        return parsed.name === 'ArtworkMinted';
      } catch {
        return false;
      }
    });

    if (mintEvent) {
      const parsedEvent = gridNFT.interface.parseLog(mintEvent);
      const tokenId = Number(parsedEvent.args.tokenId);


      // Save complete NFT data for testing
      const completeNFTData = {
        tokenId,
        contractAddress: gridNFTAddress,
        recipeRoot,
        renderRoot,
        ...nftMetadata,
        txHash: mintTx.hash,
        blockNumber: receipt.blockNumber
      };

      const fs = require('fs');
      fs.writeFileSync(`nft-${tokenId}-forced-params.json`, JSON.stringify(completeNFTData, null, 2));
      
      

      
    } else {
    }

  } catch (error) {
    if (error.data) {
      console.error('Error data:', error.data);
    }
  }
}

main().catch(console.error);
