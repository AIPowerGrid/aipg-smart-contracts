const { ethers } = require('ethers');
const ModelRegistrySDK = require('../sdk/modelregistry-sdk.js');

async function testModelRegistrySDK() {
  console.log('🧪 Testing ModelRegistry SDK...\n');
  
  try {
    const provider = new ethers.JsonRpcProvider('https://sepolia.base.org');
    const contractAddress = '0xe660455D4A83bbbbcfDCF4219ad82447a831c8A1'; // ModelRegistry address
    
    const sdk = new ModelRegistrySDK(contractAddress, provider);
    console.log('✅ ModelRegistry SDK initialized');
    
    // Test basic functions
    const models = await sdk.getAvailableModels(false);
    console.log(`📊 Available models: ${models.length}`);
    
    if (models.length > 0) {
      console.log(`🔍 Found ${models.length} models:`);
      models.forEach((model, index) => {
        console.log(`  ${index + 1}. ${model.displayName} (${model.fileName})`);
      });
    }
    
    // Test model hashes
    const hashes = await sdk.getAvailableModelHashes();
    console.log(`🔗 Model hashes: ${hashes.length}`);
    
    console.log('\n🎉 ModelRegistry SDK tests passed!');
    
  } catch (error) {
    console.error('❌ ModelRegistry SDK test failed:', error.message);
  }
}

testModelRegistrySDK();
