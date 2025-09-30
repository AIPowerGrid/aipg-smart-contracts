const { ethers } = require('ethers');

class RecipeVaultClient {
  constructor(config) {
    this.provider = new ethers.JsonRpcProvider(config.rpcUrl);
    this.wallet = new ethers.Wallet(config.privateKey, this.provider);
    this.address = config.address; // RecipeVault address
    this.contract = new ethers.Contract(
      this.address,
      [
        // Writes
        'function storePublicRecipe(address nft,uint256 tokenId,bytes32 recipeRoot,bytes data,uint8 compression) external',
        'function storePrivateRecipe(address nft,uint256 tokenId,bytes32 recipeRoot,bytes data,uint8 compression) external',
        'function makePublic(address nft,uint256 tokenId,bytes data,uint8 compression) external',
        'function deleteRecipe(address nft,uint256 tokenId) external',
        // Reads
        'function getRecipeMeta(address nft,uint256 tokenId) view returns (tuple(bytes32 recipeRoot,bytes32 dataHash,bool isPublic,uint8 compression,uint64 version,uint256 updatedAt))',
        'function getPublicRecipe(address nft,uint256 tokenId) view returns (bytes)'
      ],
      this.wallet
    );
  }

  async storePublic({ nft, tokenId, recipeRoot, dataBytes, compression = 0 }) {
    const tx = await this.contract.storePublicRecipe(nft, tokenId, recipeRoot, dataBytes, compression);
    await tx.wait();
    return tx.hash;
  }

  async storePrivate({ nft, tokenId, recipeRoot, dataBytes, compression = 0 }) {
    const tx = await this.contract.storePrivateRecipe(nft, tokenId, recipeRoot, dataBytes, compression);
    await tx.wait();
    return tx.hash;
  }

  async makePublic({ nft, tokenId, dataBytes, compression = 0 }) {
    const tx = await this.contract.makePublic(nft, tokenId, dataBytes, compression);
    await tx.wait();
    return tx.hash;
  }

  async getMeta(nft, tokenId) {
    const rec = await this.contract.getRecipeMeta(nft, tokenId);
    return {
      recipeRoot: rec.recipeRoot,
      dataHash: rec.dataHash,
      isPublic: rec.isPublic,
      compression: Number(rec.compression),
      version: Number(rec.version),
      updatedAt: rec.updatedAt.toString()
    };
  }

  async getPublic(nft, tokenId) {
    const bytes = await this.contract.getPublicRecipe(nft, tokenId);
    return bytes;
  }
}

module.exports = { RecipeVaultClient };



