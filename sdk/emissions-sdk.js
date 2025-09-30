const { ethers } = require("ethers");

class EmissionsSDK {
  constructor({ rpcUrl, controller, chainId }) {
    this.rpcUrl = rpcUrl;
    this.controller = controller;
    this.chainId = chainId;
    this.provider = new ethers.JsonRpcProvider(rpcUrl, chainId);
    this.ctrl = new ethers.Contract(controller, [
      "function batchMintWorkers(address[] workers, uint256[] amounts, uint256 epochId, string uri) external",
      "function workerBps() view returns (uint16)",
      "function stakerBps() view returns (uint16)",
      "function treasuryBps() view returns (uint16)",
      "function treasury() view returns (address)",
      "function stakingVault() view returns (address)",
      "function emissionsPaused() view returns (bool)"
    ], this.provider);
  }

  static fromDeployment({ deployment, rpcUrl }) {
    return new EmissionsSDK({
      rpcUrl,
      controller: deployment.EmissionsControllerV2,
      chainId: deployment.ChainId,
    });
  }

  withSigner(privateKey) {
    const wallet = new ethers.Wallet(privateKey, this.provider);
    this.signer = wallet;
    this.ctrlSigner = this.ctrl.connect(wallet);
    return this;
  }

  async getConfig() {
    const [worker, staker, treasuryBps, treasury, vault, paused] = await Promise.all([
      this.ctrl.workerBps(),
      this.ctrl.stakerBps(),
      this.ctrl.treasuryBps(),
      this.ctrl.treasury(),
      this.ctrl.stakingVault(),
      this.ctrl.emissionsPaused(),
    ]);
    return { workerBps: Number(worker), stakerBps: Number(staker), treasuryBps: Number(treasuryBps), treasury, vault, paused };
  }

  async batchMint({ workers, amounts, epochId, uri, gasPriceGwei }) {
    if (!this.ctrlSigner) throw new Error("call with .withSigner(privateKey)");
    const gasPrice = gasPriceGwei ? ethers.parseUnits(String(gasPriceGwei), "gwei") : undefined;
    const gas = await this.ctrlSigner.batchMintWorkers.estimateGas(workers, amounts, epochId, uri);
    const tx = await this.ctrlSigner.batchMintWorkers(workers, amounts, epochId, uri, {
      gasLimit: gas + 50_000n,
      ...(gasPrice ? { gasPrice } : {}),
    });
    const rec = await tx.wait();
    return rec;
  }
}

module.exports = { EmissionsSDK };

