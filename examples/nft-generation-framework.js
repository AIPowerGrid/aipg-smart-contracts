const { ethers } = require('ethers');
const axios = require('axios');
const fs = require('fs');

/**
 * NFT Generation Framework
 * Ensures deterministic, reproducible generation across ComfyUI and Grid API
 */
class NFTGenerationFramework {
  constructor(options = {}) {
    this.comfyUIEndpoint = options.comfyUIEndpoint || 'http://172.30.30.122:8188';
    this.gridAPIUrl = options.gridAPIUrl || 'https://api.aipowergrid.io/api';
    this.gridAPIKey = options.gridAPIKey;
    this.provider = options.provider;
    this.modelShopAddress = options.modelShopAddress;
    this.templatePath = options.templatePath || 'flux_krea_template.json';
  }

  /**
   * Fetch model constraints from blockchain
   */
  async fetchModelConstraints(modelId) {
    if (!this.provider || !this.modelShopAddress) {
      throw new Error('Provider and ModelShop address required for constraint fetching');
    }

    const modelShopABI = [
      'function getModelConstraints(string memory modelId) view returns (bool exists, uint16 stepsMin, uint16 stepsMax, uint16 cfgMinTenths, uint16 cfgMaxTenths, uint8 clipSkip, bytes32[] memory allowedSamplers, bytes32[] memory allowedSchedulers)'
    ];

    const modelShop = new ethers.Contract(this.modelShopAddress, modelShopABI, this.provider);
    const constraints = await modelShop.getModelConstraints(modelId);

    if (!constraints.exists) {
      throw new Error(`Model constraints not found for: ${modelId}`);
    }

    return {
      exists: constraints.exists,
      stepsMin: Number(constraints.stepsMin),
      stepsMax: Number(constraints.stepsMax),
      cfgMin: Number(constraints.cfgMinTenths) / 10,
      cfgMax: Number(constraints.cfgMaxTenths) / 10,
      clipSkip: Number(constraints.clipSkip),
      allowedSamplers: constraints.allowedSamplers,
      allowedSchedulers: constraints.allowedSchedulers
    };
  }

  /**
   * Create standardized generation parameters
   */
  createGenerationParams(nftData, constraints = null) {
    // Base parameters that should be identical across all backends
    const params = {
      // Core NFT data
      seed: nftData.seed,
      prompt: nftData.prompt,
      negativePrompt: nftData.negativePrompt || "",
      
      // Generation parameters  
      steps: nftData.steps,
      cfgScale: nftData.cfgScale,
      width: nftData.width || 1024,
      height: nftData.height || 1024,
      
      // Model and sampler
      model: nftData.model || "flux.1-krea-dev",
      sampler: nftData.sampler,
      scheduler: nftData.scheduler
    };

    // Validate against constraints if provided
    if (constraints) {
      this.validateParams(params, constraints);
    }

    return params;
  }

  /**
   * Validate parameters against model constraints
   */
  validateParams(params, constraints) {
    const errors = [];

    if (params.steps < constraints.stepsMin || params.steps > constraints.stepsMax) {
      errors.push(`Steps ${params.steps} outside range ${constraints.stepsMin}-${constraints.stepsMax}`);
    }

    if (params.cfgScale < constraints.cfgMin || params.cfgScale > constraints.cfgMax) {
      errors.push(`CFG ${params.cfgScale} outside range ${constraints.cfgMin}-${constraints.cfgMax}`);
    }

    if (errors.length > 0) {
      throw new Error(`Parameter validation failed: ${errors.join(', ')}`);
    }

    return true;
  }

  /**
   * Convert parameters for ComfyUI API format
   */
  paramsToComfyUI(params) {
    if (!fs.existsSync(this.templatePath)) {
      throw new Error(`Template not found: ${this.templatePath}`);
    }

    const template = JSON.parse(fs.readFileSync(this.templatePath, 'utf8'));
    const workflow = JSON.parse(JSON.stringify(template));

    // Replace placeholders with actual values
    if (workflow["45"]) { // CLIPTextEncode
      workflow["45"].inputs.text = params.prompt;
    }

    if (workflow["31"]) { // KSampler
      workflow["31"].inputs.seed = params.seed;
      workflow["31"].inputs.steps = params.steps;
      workflow["31"].inputs.cfg = params.cfgScale;
      workflow["31"].inputs.sampler_name = params.sampler;
      workflow["31"].inputs.scheduler = params.scheduler;
    }

    if (workflow["27"]) { // EmptySD3LatentImage
      workflow["27"].inputs.width = params.width;
      workflow["27"].inputs.height = params.height;
    }

    if (workflow["38"]) { // UNETLoader
      workflow["38"].inputs.unet_name = "flux1-krea-dev_fp8_scaled.safetensors";
    }

    return workflow;
  }

  /**
   * Convert parameters for Grid API format (AI Horde v2 async)
   */
  paramsToGridAPI(params) {
    return {
      prompt: params.prompt,
      params: {
        sampler_name: params.sampler === 'euler' ? 'k_euler' : params.sampler,
        cfg_scale: params.cfgScale,
        denoising_strength: 1.0,
        seed: params.seed.toString(),
        height: params.height,
        width: params.width,
        steps: params.steps
      },
      models: [params.model]
    };
  }

  /**
   * Generate via ComfyUI
   */
  async generateComfyUI(params, label = 'ComfyUI') {
    const workflow = this.paramsToComfyUI(params);
    

    try {
      const response = await axios.post(`${this.comfyUIEndpoint}/prompt`, {
        prompt: workflow
      });

      const promptId = response.data.prompt_id;

      const result = await this.pollComfyUI(promptId, label);
      
      if (result && result.length > 0) {
        return {
          success: true,
          backend: 'comfyui',
          promptId,
          images: result,
          filename: result[0].filename,
          params: params
        };
      }

      return { success: false, backend: 'comfyui', error: 'No images generated' };

    } catch (error) {
      return { success: false, backend: 'comfyui', error: error.message };
    }
  }

  /**
   * Generate via Grid API (AI Horde v2 async)
   */
  async generateGridAPI(params, label = 'Grid API', targetWorker = null) {
    if (!this.gridAPIKey) {
      throw new Error('Grid API key required');
    }

    const gridParams = this.paramsToGridAPI(params);
    
    // Add worker targeting if specified
    if (targetWorker) {
      gridParams.workers = [targetWorker];
    }
    
    if (targetWorker) {
    }

    try {
      // Submit async generation request
      const response = await axios.post(`${this.gridAPIUrl}/v2/generate/async`, gridParams, {
        headers: {
          'apikey': this.gridAPIKey,
          'Content-Type': 'application/json',
          'Client-Agent': 'NFT-Framework:1.0:blockchain-deterministic'
        }
      });

      const jobId = response.data.id;

      if (!jobId) {
        return { success: false, backend: 'grid', error: 'No job ID returned', response: response.data };
      }

      const result = await this.pollGridAPI(jobId, label);

      if (result && result.generations && result.generations.length > 0) {
        const imageUrl = result.generations[0].img;
        return {
          success: true,
          backend: 'grid',
          jobId,
          generations: result.generations,
          imageUrl,
          params: params
        };
      }

      return { success: false, backend: 'grid', error: 'No images generated', result };

    } catch (error) {
      return { 
        success: false, 
        backend: 'grid', 
        error: error.message,
        response: error.response?.data 
      };
    }
  }

  /**
   * Generate via both backends for comparison
   */
  async generateBoth(params) {

    const results = await Promise.allSettled([
      this.generateComfyUI(params, 'ComfyUI'),
      this.generateGridAPI(params, 'Grid API')
    ]);

    const comfyResult = results[0].value || { success: false, error: results[0].reason };
    const gridResult = results[1].value || { success: false, error: results[1].reason };

    return {
      seed: params.seed,
      comfyui: comfyResult,
      grid: gridResult,
      bothSucceeded: comfyResult.success && gridResult.success
    };
  }

  /**
   * Save generation results for comparison
   */
  saveComparisonResults(results, filename = null) {
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const outputFile = filename || `generation-comparison-${timestamp}.json`;
    
    const output = {
      timestamp: new Date().toISOString(),
      seed: results.seed,
      results: {
        comfyui: results.comfyui,
        grid: results.grid
      },
      summary: {
        bothSucceeded: results.bothSucceeded,
        comfyuiSuccess: results.comfyui.success,
        gridSuccess: results.grid.success
      }
    };

    fs.writeFileSync(outputFile, JSON.stringify(output, null, 2));
    return outputFile;
  }

  // Polling functions
  async pollComfyUI(promptId, label) {
    const maxAttempts = 30;
    const delay = 2000;

    for (let i = 0; i < maxAttempts; i++) {
      try {
        const response = await axios.get(`${this.comfyUIEndpoint}/history/${promptId}`);
        const historyData = response.data;

        if (historyData[promptId]) {
          const status = historyData[promptId].status;

          if (status.status_str === 'success') {
            const outputs = historyData[promptId].outputs;
            for (const nodeId in outputs) {
              if (outputs[nodeId].images) {
                return outputs[nodeId].images;
              }
            }
            return [];
          } else if (status.status_str === 'error') {
            return null;
          }
        }

        if (i % 5 === 0) {
        }

        await new Promise(resolve => setTimeout(resolve, delay));

      } catch (error) {
        await new Promise(resolve => setTimeout(resolve, delay));
      }
    }

    return null;
  }

  async pollGridAPI(jobId, label) {
    const maxAttempts = 60;
    const delay = 3000;

    for (let i = 0; i < maxAttempts; i++) {
      try {
        const response = await axios.get(`${this.gridAPIUrl}/v2/generate/status/${jobId}`, {
          headers: {
            'Client-Agent': 'NFT-Framework:1.0:blockchain-deterministic'
          }
        });

        const data = response.data;

        if (data.done === true && data.generations && data.generations.length > 0) {
          return data;
        } else if (data.faulted === true) {
          return null;
        }

        if (i % 5 === 0) {
          const status = data.done ? 'done' : (data.processing > 0 ? 'processing' : 'waiting');
        }

        await new Promise(resolve => setTimeout(resolve, delay));

      } catch (error) {
        await new Promise(resolve => setTimeout(resolve, delay));
      }
    }

    return null;
  }
}

module.exports = { NFTGenerationFramework };
