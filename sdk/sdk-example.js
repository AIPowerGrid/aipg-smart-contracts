// AIPG NFT SDK Usage Example
// Run with: node sdk-example.js

require('dotenv').config({ path: '../.env' });
const { AIPGNFTClient } = require('./aipg-nft-sdk');

async function main() {
  console.log('🚀 AIPG NFT SDK Example');
  console.log('');

  // Initialize SDK client
  const client = new AIPGNFTClient({
    rpcUrl: 'https://sepolia.base.org',
    privateKey: process.env.PRIVATE_KEY,
    contractAddress: '0xa87Eb64534086e914A4437ac75a1b554A10C9934'
  });

  try {
    // Get basic info
    console.log('📋 Client Info:');
    console.log('Address:', await client.getAddress());
    console.log('Balance:', await client.getBalance(), 'ETH');
    console.log('');

    // Check current state
    console.log('🔍 Checking current state...');
    const permissions = await client.checkPermissions();
    const approvals = await client.checkApprovals(1, 1000);
    const mintFee = await client.getMintFee();

    console.log('Permissions:', permissions);
    console.log('Approvals:', approvals);
    console.log('Mint fee:', mintFee.eth, 'ETH');
    console.log('');

    // Example 1: Quick mint with setup
    console.log('🎯 Example 1: Quick mint with automatic setup');
    const result1 = await client.mintWithSetup({
      modelId: 1,
      recipeId: 1000,
      seed: Math.floor(Math.random() * 1000000000),
      steps: 25,
      cfg: 3.5,
      prompt: 'A serene mountain landscape at sunset, digital art masterpiece',
      negativePrompt: 'blurry, low quality, watermark',
      sampler: 'euler',
      scheduler: 'simple'
    });

    console.log('✅ Minted NFT:', result1);
    console.log('');

    // Example 2: Verify the NFT
    console.log('🔍 Example 2: Verify minted NFT');
    const verification = await client.verifyNFT(result1.tokenId);
    console.log('Verification:', verification);
    console.log('');

    // Example 3: Mint another with different parameters
    console.log('🎯 Example 3: Mint with different parameters');
    const result2 = await client.mintNFT({
      modelId: 1,
      recipeId: 1000,
      seed: 555666777,
      steps: 30,
      cfg: 4.5,
      width: 1024,
      height: 1024,
      prompt: 'Cyberpunk cityscape with neon lights reflecting on wet streets',
      negativePrompt: 'blurry, distorted, low res',
      sampler: 'euler',
      scheduler: 'simple'
    });

    console.log('✅ Second NFT minted:', result2);
    console.log('');

    console.log('🎉 All examples completed successfully!');
    console.log('');
    console.log('📝 Summary:');
    console.log(`- Minted NFT #${result1.tokenId}: Mountain landscape`);
    console.log(`- Minted NFT #${result2.tokenId}: Cyberpunk cityscape`);
    console.log(`- Contract: ${client.contractAddress}`);
    console.log(`- Both NFTs owned by: ${await client.getAddress()}`);

  } catch (error) {
    console.error('❌ Error:', error.message);
    
    // Common troubleshooting
    if (error.message.includes('insufficient funds')) {
      console.log('💡 Tip: Add more ETH to your wallet for gas fees');
    } else if (error.message.includes('not approved')) {
      console.log('💡 Tip: Run setupForMinting() first to approve models/recipes');
    } else if (error.message.includes('not a worker')) {
      console.log('💡 Tip: Grant WORKER role with grantWorkerRole()');
    }
  }
}

// Example of manual setup (commented out)
async function manualSetupExample() {
  const client = new AIPGNFTClient({
    rpcUrl: 'https://sepolia.base.org',
    privateKey: process.env.PRIVATE_KEY,
    contractAddress: '0xa87Eb64534086e914A4437ac75a1b554A10C9934'
  });

  // Manual step-by-step setup
  console.log('🔧 Manual setup example:');
  
  // 1. Grant worker role
  await client.grantWorkerRole();
  
  // 2. Approve models
  await client.approveModel(1);
  await client.approveModel(2);
  
  // 3. Approve recipes
  await client.approveRecipe(1000);
  await client.approveRecipe(2000);
  
  console.log('✅ Manual setup complete');
}

// Run the example
if (require.main === module) {
  main().catch(console.error);
}

module.exports = { main, manualSetupExample };
