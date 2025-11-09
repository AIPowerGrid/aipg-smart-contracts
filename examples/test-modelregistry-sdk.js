const { ethers } = require('ethers');
const ModelRegistrySDK = require('../sdk/modelregistry-sdk.js');

async function testModelRegistrySDK() {
  
  try {
    const provider = new ethers.JsonRpcProvider('https://sepolia.base.org');
    const contractAddress = '0xe660455D4A83bbbbcfDCF4219ad82447a831c8A1'; // ModelRegistry address
    
    const sdk = new ModelRegistrySDK(contractAddress, provider);
    
    // Test basic functions
    const models = await sdk.getAvailableModels(false);
    
    if (models.length > 0) {
      models.forEach((model, index) => {
      });
    }
    
    // Test model hashes
    const hashes = await sdk.getAvailableModelHashes();
    
    
  } catch (error) {
  }
}

testModelRegistrySDK();
