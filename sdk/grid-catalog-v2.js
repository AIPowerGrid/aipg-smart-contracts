const { Contract, ZeroAddress, isAddress } = require("ethers");

const ABI = [
  "function modelCount() view returns (uint256)",
  "function recipeCount() view returns (uint256)",
  "function listModelIds(uint256 offset,uint256 limit) view returns (bytes32[])",
  "function listRecipeIds(uint256 offset,uint256 limit) view returns (bytes32[])",
  "function getModel(bytes32 modelId) view returns (tuple(bytes32 manifestHash,bytes32 artifactRoot,bytes32 slug,bytes32 versionHash,uint32 modalityMask,uint32 minVramMiB,uint64 createdAt,address publisher,bool active,string manifestURI))",
  "function getRecipe(bytes32 recipeId) view returns (tuple(bytes32 contentHash,bytes32 slug,bytes32 versionHash,bytes32 requirementsHash,uint32 outputModality,uint64 createdAt,address publisher,bool active,bool canCreateNfts,string contentURI))",
  "function getRecipeRequirements(bytes32 recipeId) view returns (bytes32[])",
  "function getModelIdByRelease(bytes32 slug,bytes32 versionHash) view returns (bytes32)",
  "function getRecipeIdByRelease(bytes32 slug,bytes32 versionHash) view returns (bytes32)",
  "function isModelActive(bytes32 modelId) view returns (bool)",
  "function isRecipeExecutable(bytes32 recipeId) view returns (bool)",
  "function isRecipeNftEligible(bytes32 recipeId) view returns (bool)",
  "function paused() view returns (bool)",
];

class GridCatalogV2Client {
  constructor(address, provider) {
    if (!isAddress(address) || address === ZeroAddress) {
      throw new Error("Invalid GridCatalogV2 address");
    }
    if (!provider) throw new Error("A provider is required");
    this.address = address;
    this.contract = new Contract(address, ABI, provider);
  }

  async getModel(modelId) {
    return this.contract.getModel(modelId);
  }

  async getRecipe(recipeId) {
    const [record, requiredModelIds, executable, nftEligible] = await Promise.all([
      this.contract.getRecipe(recipeId),
      this.contract.getRecipeRequirements(recipeId),
      this.contract.isRecipeExecutable(recipeId),
      this.contract.isRecipeNftEligible(recipeId),
    ]);
    return { record, requiredModelIds, executable, nftEligible };
  }

  async listModelIds(pageSize = 100) {
    return this.#listAll("modelCount", "listModelIds", pageSize);
  }

  async listRecipeIds(pageSize = 100) {
    return this.#listAll("recipeCount", "listRecipeIds", pageSize);
  }

  async #listAll(countMethod, pageMethod, pageSize) {
    if (!Number.isInteger(pageSize) || pageSize < 1 || pageSize > 100) {
      throw new Error("pageSize must be an integer from 1 to 100");
    }
    const rawCount = await this.contract[countMethod]();
    if (rawCount > BigInt(Number.MAX_SAFE_INTEGER)) {
      throw new Error("Catalog count exceeds the JavaScript safe integer range");
    }
    const count = Number(rawCount);
    const result = [];
    for (let offset = 0; offset < count; offset += pageSize) {
      result.push(...(await this.contract[pageMethod](offset, pageSize)));
    }
    return result;
  }
}

module.exports = { ABI, GridCatalogV2Client };
