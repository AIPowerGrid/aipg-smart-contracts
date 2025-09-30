/**
 * AIPGTokenV2 Interaction Script
 * 
 * Usage: node interact-aipg-token.js
 * 
 * This script demonstrates interaction with the deployed AIPGTokenV2 contract
 * on Base Mainnet. Useful for auditors to verify contract behavior.
 */

const { ethers } = require('ethers');

// Configuration
const CONFIG = {
  // Base Mainnet (Production)
  MAINNET: {
    RPC_URL: 'https://mainnet.base.org',
    CHAIN_ID: 8453,
    CONTRACT: '0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608'
  },
  // Base Sepolia (Testnet)
  TESTNET: {
    RPC_URL: 'https://sepolia.base.org',
    CHAIN_ID: 84532,
    CONTRACT: '0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608' // Same address
  }
};

// Minimal ABI for read-only operations
const AIPG_ABI = [
  'function name() view returns (string)',
  'function symbol() view returns (string)',
  'function decimals() view returns (uint8)',
  'function totalSupply() view returns (uint256)',
  'function cap() view returns (uint256)',
  'function balanceOf(address) view returns (uint256)',
  'function paused() view returns (bool)',
  'function hasRole(bytes32 role, address account) view returns (bool)',
  'function DEFAULT_ADMIN_ROLE() view returns (bytes32)',
  'function MINTER_ROLE() view returns (bytes32)',
  'function PAUSER_ROLE() view returns (bytes32)'
];

async function main() {
  console.log('=== AIPGTokenV2 Contract Interaction ===\n');
  
  // Use mainnet by default (read-only, no private key needed)
  const network = process.argv[2] === 'testnet' ? CONFIG.TESTNET : CONFIG.MAINNET;
  console.log(`Network: ${network === CONFIG.MAINNET ? 'Base Mainnet' : 'Base Sepolia'}`);
  console.log(`RPC: ${network.RPC_URL}`);
  console.log(`Contract: ${network.CONTRACT}\n`);
  
  const provider = new ethers.JsonRpcProvider(network.RPC_URL, undefined, {
    staticNetwork: true
  });
  const contract = new ethers.Contract(network.CONTRACT, AIPG_ABI, provider);
  
  try {
    // Basic token info
    console.log('📊 Token Information:');
    const name = await contract.name();
    console.log(`  Name: ${name}`);
    
    const symbol = await contract.symbol();
    console.log(`  Symbol: ${symbol}`);
    
    const decimals = await contract.decimals();
    console.log(`  Decimals: ${decimals}`);
    
    const totalSupply = await contract.totalSupply();
    console.log(`  Total Supply: ${ethers.formatEther(totalSupply)} ${symbol}`);
    
    const cap = await contract.cap();
    console.log(`  Cap (Max Supply): ${ethers.formatEther(cap)} ${symbol}`);
    
    try {
      const paused = await contract.paused();
      console.log(`  Paused: ${paused ? '🛑 YES' : '✅ NO'}`);
    } catch (e) {
      console.log(`  Paused: Unable to check (${e.shortMessage || 'error'})`);
    }
    
    // Role information
    console.log('\n🔑 Role Configuration:');
    const DEFAULT_ADMIN_ROLE = await contract.DEFAULT_ADMIN_ROLE();
    const MINTER_ROLE = await contract.MINTER_ROLE();
    const PAUSER_ROLE = await contract.PAUSER_ROLE();
    
    console.log(`  DEFAULT_ADMIN_ROLE: ${DEFAULT_ADMIN_ROLE}`);
    console.log(`  MINTER_ROLE: ${MINTER_ROLE}`);
    console.log(`  PAUSER_ROLE: ${PAUSER_ROLE}`);
    
    // Check balance and roles of a specific address if provided
    if (process.argv[3]) {
      const address = process.argv[3];
      console.log(`\n💰 Address Information:`);
      console.log(`  Address: ${address}`);
      
      const balance = await contract.balanceOf(address);
      console.log(`  Balance: ${ethers.formatEther(balance)} ${symbol}`);
      
      const isAdmin = await contract.hasRole(DEFAULT_ADMIN_ROLE, address);
      const isMinter = await contract.hasRole(MINTER_ROLE, address);
      const isPauser = await contract.hasRole(PAUSER_ROLE, address);
      
      console.log(`\n  Roles:`);
      console.log(`    DEFAULT_ADMIN_ROLE: ${isAdmin ? '✅ YES' : '❌ NO'}`);
      console.log(`    MINTER_ROLE: ${isMinter ? '✅ YES' : '❌ NO'}`);
      console.log(`    PAUSER_ROLE: ${isPauser ? '✅ YES' : '❌ NO'}`);
    }
    
    console.log('\n✅ Success! Contract is accessible and responding.');
    
  } catch (error) {
    console.error('\n❌ Error:', error.message);
    process.exit(1);
  }
}

// Usage examples in comments
console.log(`
Usage Examples:

1. Check mainnet contract (read-only):
   node interact-aipg-token.js

2. Check testnet contract:
   node interact-aipg-token.js testnet

3. Check specific address balance on mainnet:
   node interact-aipg-token.js mainnet 0xYourAddressHere

4. Check specific address balance on testnet:
   node interact-aipg-token.js testnet 0xYourAddressHere

Note: This script performs read-only operations and does not require a private key.
`);

if (require.main === module) {
  main().catch(console.error);
}
