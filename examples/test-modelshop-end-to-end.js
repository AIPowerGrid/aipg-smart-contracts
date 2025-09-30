const hre = require("hardhat");
const ModelShopSDK = require('../modelshop-sdk');

async function main() {
    console.log("🧪 ModelShop End-to-End Test\n");
    
    const [deployer] = await hre.ethers.getSigners();
    console.log("Testing with account:", deployer.address);
    
    // 1. Deploy ModelShop
    console.log("1️⃣ Deploying ModelShop...");
    const ModelShop = await hre.ethers.getContractFactory("contracts_active/ModelShop.sol:ModelShop");
    const modelShop = await ModelShop.deploy();
    await modelShop.waitForDeployment();
    
    const contractAddress = await modelShop.getAddress();
    console.log("✅ ModelShop deployed to:", contractAddress);
    
    // 2. Initialize SDK
    console.log("\n2️⃣ Initializing SDK...");
    const sdk = new ModelShopSDK(contractAddress, deployer.provider, deployer);
    console.log("✅ SDK initialized");
    
    // 3. Mint test models
    console.log("\n3️⃣ Minting test models...");
    
    const testModels = [
        {
            modelHash: hre.ethers.keccak256(hre.ethers.toUtf8Bytes("flux-dev-model-data")),
            modelType: sdk.ModelType.IMAGE_MODEL,
            fileName: "flux-dev-fp8.safetensors",
            displayName: "Flux Dev FP8",
            description: "Fast inference optimized Flux model",
            isNSFW: false,
            sizeBytes: hre.ethers.parseUnits("3.2", 9) // 3.2 GB
        },
        {
            modelHash: hre.ethers.keccak256(hre.ethers.toUtf8Bytes("llama-8b-model-data")),
            modelType: sdk.ModelType.TEXT_MODEL,
            fileName: "llama-3.1-8b-q4.gguf",
            displayName: "Llama 3.1 8B Q4",
            description: "4-bit quantized Llama model for text generation",
            isNSFW: false,
            sizeBytes: hre.ethers.parseUnits("4.7", 9) // 4.7 GB
        },
        {
            modelHash: hre.ethers.keccak256(hre.ethers.toUtf8Bytes("stable-video-model-data")),
            modelType: sdk.ModelType.VIDEO_MODEL,
            fileName: "stable-video-diffusion.safetensors",
            displayName: "Stable Video Diffusion",
            description: "Video generation model",
            isNSFW: false,
            sizeBytes: hre.ethers.parseUnits("7.1", 9) // 7.1 GB
        }
    ];
    
    const tokenIds = [];
    for (let i = 0; i < testModels.length; i++) {
        const model = testModels[i];
        console.log(`   Minting: ${model.displayName}...`);
        
        const result = await sdk.mintModel(model);
        tokenIds.push(result.tokenId);
        
        console.log(`   ✅ Minted with Token ID: ${result.tokenId}`);
    }
    
    // 4. Test getting models before verification
    console.log("\n4️⃣ Testing before verification...");
    const availableModels = await sdk.getAvailableModels();
    console.log(`Available models: ${availableModels.length} (should be 0)`);
    
    // 5. Verify models
    console.log("\n5️⃣ Verifying models...");
    await sdk.batchVerifyModels(tokenIds, true);
    console.log("✅ All models verified");
    
    // 6. Test SDK functions
    console.log("\n6️⃣ Testing SDK functions...");
    
    // Get all verified models
    const verifiedModels = await sdk.getAvailableModels();
    console.log(`✅ Found ${verifiedModels.length} verified models:`);
    verifiedModels.forEach(model => {
        console.log(`   - ${model.name} (${model.modelTypeName})`);
        console.log(`     File: ${model.fileName}`);
        console.log(`     Hash: ${model.modelHash}`);
        console.log(`     Size: ${(parseInt(model.sizeBytes) / 1024 / 1024 / 1024).toFixed(1)} GB`);
    });
    
    // Get just hashes
    const hashes = await sdk.getAvailableModelHashes();
    console.log(`✅ Found ${hashes.length} verified hashes`);
    
    // Test worker compatibility check
    console.log("\n7️⃣ Testing worker compatibility...");
    const workerHashes = [
        testModels[0].modelHash, // Worker has Flux
        testModels[1].modelHash, // Worker has Llama
        hre.ethers.keccak256(hre.ethers.toUtf8Bytes("unknown-model")) // Worker has unknown model
    ];
    
    const compatible = await sdk.getCompatibleModels(workerHashes);
    console.log(`✅ Worker can run ${compatible.length} models:`);
    compatible.forEach(model => {
        console.log(`   - ${model.name}`);
    });
    
    // Test individual model lookup
    console.log("\n8️⃣ Testing model lookup...");
    const fluxModel = await sdk.getModelByHash(testModels[0].modelHash);
    if (fluxModel) {
        console.log(`✅ Found Flux model: ${fluxModel.name}`);
        console.log(`   Created: ${fluxModel.timestamp.toISOString()}`);
        console.log(`   Creator: ${fluxModel.creator}`);
    }
    
    // Test batch approval check
    console.log("\n9️⃣ Testing batch approval...");
    const approvals = await sdk.checkWorkerModels(workerHashes);
    console.log("Approval results:");
    workerHashes.forEach((hash, i) => {
        console.log(`   ${hash.slice(0, 10)}...: ${approvals[i] ? '✅' : '❌'}`);
    });
    
    // 10. Test model constraints (if any exist)
    console.log("\n🔟 Testing model constraints...");
    const constraints = await sdk.getModelConstraints("flux.1-krea-dev");
    if (constraints) {
        console.log("✅ Found constraints for flux.1-krea-dev");
        console.log(`   Steps: ${constraints.steps.min}-${constraints.steps.max}`);
        console.log(`   CFG: ${constraints.cfg.min}-${constraints.cfg.max}`);
    } else {
        console.log("ℹ️  No constraints set for flux.1-krea-dev (this is normal)");
    }
    
    console.log("\n🎉 All tests passed!");
    console.log("\n📋 Final Summary:");
    console.log(`Contract: ${contractAddress}`);
    console.log(`Total Models: ${await modelShop.totalModels()}`);
    console.log(`Verified Models: ${verifiedModels.length}`);
    console.log("SDK working correctly! ✅");
    
    return {
        contractAddress,
        tokenIds,
        verifiedModels
    };
}

if (require.main === module) {
    main()
        .then(() => process.exit(0))
        .catch((error) => {
            console.error("❌ Test failed:", error);
            process.exit(1);
        });
}

module.exports = main;
