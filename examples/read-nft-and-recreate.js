const hre = require("hardhat");
const crypto = require('crypto');
const fs = require('fs');

async function main() {
  // Force Base Sepolia
  const provider = new hre.ethers.JsonRpcProvider(process.env.BASE_SEPOLIA_RPC_URL);
  const wallet = new hre.ethers.Wallet(process.env.PRIVATE_KEY, provider);
  
  
  const gridNFT = await hre.ethers.getContractAt(
    "GridNFT",
    "0x2cE108c0EE26f3dF27F26E0544037B79b1c395f7",
    wallet
  );

  const recipeVault = await hre.ethers.getContractAt(
    "RecipeVault",
    "0xEc9833F2681BdF4D4A635e74626a630048119372",
    wallet
  );

  // Step 1: Read NFT from blockchain
  
  try {
    const tokenId = 1;
    const artwork = await gridNFT.getArtwork(tokenId);
    

    // Step 2: Fetch recipe template from RecipeVault
    
    const templateNftAddress = "0x5c5d61d53C426b876a475E273657E438c551EefD";
    const templateTokenId = 1;
    
    const storedHexBytes = await recipeVault.getPublicRecipe(templateNftAddress, templateTokenId);
    const storedBytes = Buffer.from(storedHexBytes.slice(2), 'hex');
    const fullRecipe = JSON.parse(storedBytes.toString('utf8'));
    const pureTemplate = fullRecipe.template;
    

    // Step 3: Recreate the exact workflow
    
    // We need to reverse-engineer the generation parameters from the renderRoot
    // For this demo, we'll use the parameters we know from the worker's mint
    const recreatedWorkflow = JSON.parse(JSON.stringify(pureTemplate));
    
    // Add the generation parameters (in real scenario, these would be extracted from renderRoot)
    const generationParams = {
      seed: 123456789,
      steps: 20,
      cfg: 1.0,
      sampler_name: "euler",
      scheduler: "simple",
      denoise: 1.0,
      width: 1024,
      height: 1024,
      prompt: "A futuristic cyberpunk street scene with neon signs, rain-slicked pavement, and towering skyscrapers. Digital art style with vibrant colors and atmospheric lighting."
    };
    
    // Fill in the parameters
    Object.keys(recreatedWorkflow).forEach(nodeId => {
      const node = recreatedWorkflow[nodeId];
      
      if (node.class_type === "KSampler") {
        node.inputs.seed = generationParams.seed;
        node.inputs.steps = generationParams.steps;
        node.inputs.cfg = generationParams.cfg;
        node.inputs.sampler_name = generationParams.sampler_name;
        node.inputs.scheduler = generationParams.scheduler;
        node.inputs.denoise = generationParams.denoise;
      }
      
      if (node.class_type === "EmptySD3LatentImage") {
        node.inputs.width = generationParams.width;
        node.inputs.height = generationParams.height;
        node.inputs.batch_size = 1;
      }
      
      if (node.class_type === "CLIPTextEncode") {
        node.inputs.text = generationParams.prompt;
      }
      
      if (node.class_type === "SaveImage") {
        node.inputs.filename_prefix = "recreated_cyberpunk_art";
      }
    });


    // Step 4: Send to ComfyUI for recreation
    
    const workflowJson = JSON.stringify(recreatedWorkflow);
    fs.writeFileSync('recreated_workflow.json', workflowJson);
    
    // For this demo, we'll just show what would be sent

    // Step 5: Verify renderRoot would match
    
    const renderData = {
      recipeRoot: artwork.recipeRoot,
      prompt: generationParams.prompt,
      seed: generationParams.seed,
      steps: generationParams.steps,
      cfg: generationParams.cfg,
      sampler_name: generationParams.sampler_name,
      scheduler: generationParams.scheduler,
      denoise: generationParams.denoise,
      width: generationParams.width,
      height: generationParams.height,
      tier: "Strict"
    };

    const renderJson = JSON.stringify(renderData, Object.keys(renderData).sort());
    const calculatedRenderRoot = "0x" + crypto.createHash('sha256').update(renderJson).digest('hex');
    

    // Summary
    

  } catch (error) {
    console.error("❌ Error during recreation:", error.message);
  }
}

main().catch((e) => {
  process.exit(1);
});

