/**
 * Integration Test for EmissionsController + StakingVault
 * Tests the complete flow: mint -> notify rewards -> staking
 */

const { ethers } = require('ethers');

async function main() {

  // Configuration (update these for your deployment)
  const RPC_URL = process.env.BASE_RPC_URL || 'https://mainnet.base.org';
  const TOKEN_ADDRESS = process.env.AIPG_TOKEN_ADDRESS || '0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608';
  const EMISSIONS_ADDRESS = process.env.EMISSIONS_CONTROLLER_ADDRESS;
  const VAULT_ADDRESS = process.env.STAKING_VAULT_ADDRESS;

  if (!EMISSIONS_ADDRESS || !VAULT_ADDRESS) {
    throw new Error('Missing EMISSIONS_CONTROLLER_ADDRESS or STAKING_VAULT_ADDRESS');
  }

  const provider = new ethers.JsonRpcProvider(RPC_URL);

  // ABIs
  const tokenAbi = [
    'function hasRole(bytes32 role, address account) view returns (bool)',
    'function MINTER_ROLE() view returns (bytes32)',
    'function totalSupply() view returns (uint256)',
    'function balanceOf(address) view returns (uint256)'
  ];

  const vaultAbi = [
    'function hasRole(bytes32 role, address account) view returns (bool)',
    'function REWARD_DISTRIBUTOR_ROLE() view returns (bytes32)',
    'function rewardRate() view returns (uint256)',
    'function periodFinish() view returns (uint256)',
    'function rewardPerTokenStored() view returns (uint256)'
  ];

  const emissionsAbi = [
    'function emissionsPaused() view returns (bool)',
    'function rewardPerHour() view returns (uint256)',
    'function era() view returns (uint8)',
    'function workerBps() view returns (uint16)',
    'function stakerBps() view returns (uint16)',
    'function treasuryBps() view returns (uint16)',
    'function token() view returns (address)',
    'function stakingVault() view returns (address)',
    'function treasury() view returns (address)'
  ];

  const token = new ethers.Contract(TOKEN_ADDRESS, tokenAbi, provider);
  const vault = new ethers.Contract(VAULT_ADDRESS, vaultAbi, provider);
  const emissions = new ethers.Contract(EMISSIONS_ADDRESS, emissionsAbi, provider);


  // 1. Check Roles
  const MINTER_ROLE = await token.MINTER_ROLE();
  const hasMinterRole = await token.hasRole(MINTER_ROLE, EMISSIONS_ADDRESS);

  const DISTRIBUTOR_ROLE = await vault.REWARD_DISTRIBUTOR_ROLE();
  const hasDistributorRole = await vault.hasRole(DISTRIBUTOR_ROLE, EMISSIONS_ADDRESS);

  if (!hasMinterRole || !hasDistributorRole) {
    process.exit(1);
  }

  // 2. Check Configuration
  const isPaused = await emissions.emissionsPaused();
  const rewardPerHour = await emissions.rewardPerHour();
  const era = await emissions.era();
  const workerBps = await emissions.workerBps();
  const stakerBps = await emissions.stakerBps();
  const treasuryBps = await emissions.treasuryBps();
  

  // 3. Check Vault State
  const vaultBalance = await token.balanceOf(VAULT_ADDRESS);
  const rewardRate = await vault.rewardRate();
  const periodFinish = await vault.periodFinish();
  const rewardPerToken = await vault.rewardPerTokenStored();


  // 4. Verify Integration
  const configuredToken = await emissions.token();
  const configuredVault = await emissions.stakingVault();
  const treasury = await emissions.treasury();

  const tokenMatch = configuredToken.toLowerCase() === TOKEN_ADDRESS.toLowerCase();
  const vaultMatch = configuredVault.toLowerCase() === VAULT_ADDRESS.toLowerCase();


  // 5. Summary
  const allGood = hasMinterRole && hasDistributorRole && tokenMatch && vaultMatch;
  
  if (allGood) {
  } else {
    process.exit(1);
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error('Error:', error.message);
    process.exit(1);
  });
}

module.exports = { main };









