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
  
  // Use mainnet by default (read-only, no private key needed)
  const network = process.argv[2] === 'testnet' ? CONFIG.TESTNET : CONFIG.MAINNET;
  
  const provider = new ethers.JsonRpcProvider(network.RPC_URL, undefined, {
    staticNetwork: true
  });
  const contract = new ethers.Contract(network.CONTRACT, AIPG_ABI, provider);
  
  try {
    // Basic token info
    const name = await contract.name();
    
    const symbol = await contract.symbol();
    
    const decimals = await contract.decimals();
    
    const totalSupply = await contract.totalSupply();
    
    const cap = await contract.cap();
    
    try {
      const paused = await contract.paused();
    } catch (e) {
    }
    
    // Role information
    const DEFAULT_ADMIN_ROLE = await contract.DEFAULT_ADMIN_ROLE();
    const MINTER_ROLE = await contract.MINTER_ROLE();
    const PAUSER_ROLE = await contract.PAUSER_ROLE();
    
    
    // Check balance and roles of a specific address if provided
    if (process.argv[3]) {
      const address = process.argv[3];
      
      const balance = await contract.balanceOf(address);
      
      const isAdmin = await contract.hasRole(DEFAULT_ADMIN_ROLE, address);
      const isMinter = await contract.hasRole(MINTER_ROLE, address);
      const isPauser = await contract.hasRole(PAUSER_ROLE, address);
      
    }
    
    
  } catch (error) {
    console.error('\n❌ Error:', error.message);
    process.exit(1);
  }
}

// Usage examples in comments
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
