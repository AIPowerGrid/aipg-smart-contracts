const { ethers } = require('ethers');
require('dotenv').config();

async function main() {
  console.log('🎭 MINTING NFT WITH FORCED DETERMINISTIC PARAMETERS\n');

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

  console.log('🎯 FORCED PARAMETERS (consistent across all NFTs):');
  console.log('- Steps:', forcedParams.steps);
  console.log('- CFG:', forcedParams.cfg);
  console.log('- Sampler:', forcedParams.sampler);
  console.log('- Scheduler:', forcedParams.scheduler);
  console.log('- Model:', forcedParams.model);
  console.log('- Dimensions:', `${forcedParams.width}x${forcedParams.height}`);

  console.log('\n🎲 RANDOMIZED VARIABLES (unique to this NFT):');
  console.log('- Random seed:', randomSeed);
  console.log('- Fun prompt:', funPrompt.substring(0, 80) + '...');

  try {
    // Check worker status
    const workerRole = ethers.keccak256(ethers.toUtf8Bytes("WORKER_ROLE"));
    const isWorker = await gridNFT.hasRole(workerRole, await wallet.getAddress());
    
    if (!isWorker) {
      console.log('❌ Wallet is not a worker. Cannot mint.');
      return;
    }

    // Get current stats
    const stats = await gridNFT.getContractStats();
    const nextTokenId = Number(stats.totalSupply) + 1;
    const baseFee = stats.currentBaseFee;

    console.log('\n📊 MINTING INFO:');
    console.log('- Next token ID:', nextTokenId);
    console.log('- Base fee:', ethers.formatEther(baseFee), 'ETH');

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

    console.log('\n🔐 BLOCKCHAIN HASHES:');
    console.log('- Recipe root (workflow):', recipeRoot);
    console.log('- Render root (generation):', renderRoot);

    // Check and approve recipe if needed
    console.log('\n🍳 CHECKING RECIPE APPROVAL...');
    const isApproved = await gridNFT.isRecipeApproved(recipeRoot);
    
    if (!isApproved) {
      console.log('❌ Recipe not approved, approving now...');
      
      const approveTx = await gridNFT.approveRecipe(recipeRoot, true, {
        gasLimit: 100000,
        maxFeePerGas: ethers.parseUnits('0.1', 'gwei'),
        maxPriorityFeePerGas: ethers.parseUnits('0.01', 'gwei')
      });
      
      console.log('Approval transaction:', approveTx.hash);
      await approveTx.wait();
      console.log('✅ Recipe approved!');
      
      // Wait a moment to avoid nonce conflicts
      console.log('⏳ Waiting before minting...');
      await new Promise(resolve => setTimeout(resolve, 5000));
    } else {
      console.log('✅ Recipe already approved');
    }

    // Mint the NFT
    console.log('\n🚀 MINTING NFT...');
    
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

    console.log('Transaction submitted:', mintTx.hash);
    const receipt = await mintTx.wait();
    console.log('✅ NFT minted in block:', receipt.blockNumber);

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

      console.log('\n🎉 NFT MINTED SUCCESSFULLY!');
      console.log('- Token ID:', tokenId);
      console.log('- Contract:', gridNFTAddress);
      console.log('- Forced params preserved for reproducibility');

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
      
      console.log('\n📁 FILES CREATED:');
      console.log(`- nft-${tokenId}-forced-params.json (complete NFT data)`);
      
      console.log('\n🧪 READY FOR TESTING:');
      console.log('1. Use these exact parameters in ComfyUI');
      console.log('2. Use these exact parameters in Grid API');
      console.log('3. Both should generate reproducible results');
      console.log('4. Seed:', randomSeed, '(use this for both backends)');

      console.log('\n🔄 TEST COMMAND READY:');
      console.log(`node test-dual-backend-with-seed.js ${tokenId} ${randomSeed}`);
      
    } else {
      console.log('❌ Could not find mint event');
    }

  } catch (error) {
    console.error('❌ Minting failed:', error.message);
    if (error.data) {
      console.error('Error data:', error.data);
    }
  }
}

main().catch(console.error);
