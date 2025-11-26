/**
 * AIPGTokenV2 Interaction Script
 * 
 * Verify the deployed AIPGTokenV2 contract on Base Mainnet.
 * Read-only operations - no private key needed.
 * 
 * Usage:
 *   node interact-aipg-token.js                    - Check mainnet
 *   node interact-aipg-token.js testnet            - Check testnet
 *   node interact-aipg-token.js mainnet 0xAddress  - Check address balance
 */

const { ethers } = require('ethers');

const CONFIG = {
  MAINNET: {
    RPC_URL: 'https://base.llamarpc.com',
    CHAIN_ID: 8453,
    CONTRACT: '0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608'
  },
  TESTNET: {
    RPC_URL: 'https://sepolia.base.org',
    CHAIN_ID: 84532,
    CONTRACT: '0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608'
  }
};

// Known role hashes (keccak256)
const ROLES = {
  DEFAULT_ADMIN_ROLE: '0x0000000000000000000000000000000000000000000000000000000000000000',
  MINTER_ROLE: ethers.keccak256(ethers.toUtf8Bytes('MINTER_ROLE')),
  PAUSER_ROLE: ethers.keccak256(ethers.toUtf8Bytes('PAUSER_ROLE'))
};

const AIPG_ABI = [
  'function name() view returns (string)',
  'function symbol() view returns (string)',
  'function decimals() view returns (uint8)',
  'function totalSupply() view returns (uint256)',
  'function cap() view returns (uint256)',
  'function balanceOf(address) view returns (uint256)',
  'function paused() view returns (bool)',
  'function hasRole(bytes32 role, address account) view returns (bool)'
];

async function main() {
  console.log('=== AIPGTokenV2 Contract Verification ===\n');
  
  // Determine network
  const networkArg = process.argv[2]?.toLowerCase();
  const isTestnet = networkArg === 'testnet' || networkArg === 'sepolia';
  const network = isTestnet ? CONFIG.TESTNET : CONFIG.MAINNET;
  
  console.log('Network:', isTestnet ? 'Base Sepolia (Testnet)' : 'Base Mainnet');
  console.log('RPC:', network.RPC_URL);
  console.log('Contract:', network.CONTRACT);
  console.log('');
  
  const provider = new ethers.JsonRpcProvider(network.RPC_URL);
  const contract = new ethers.Contract(network.CONTRACT, AIPG_ABI, provider);
  
  try {
    // Token info
    const [name, symbol, decimals, totalSupply, cap] = await Promise.all([
      contract.name(),
      contract.symbol(),
      contract.decimals(),
      contract.totalSupply(),
      contract.cap()
    ]);
    
    console.log('📊 Token Information:');
    console.log('  Name:', name);
    console.log('  Symbol:', symbol);
    console.log('  Decimals:', Number(decimals));
    console.log('  Total Supply:', ethers.formatEther(totalSupply), symbol);
    console.log('  Max Supply (Cap):', ethers.formatEther(cap), symbol);
    console.log('  Minting Remaining:', ethers.formatEther(cap - totalSupply), symbol);
    
    // Check if paused
    try {
      const paused = await contract.paused();
      console.log('  Status:', paused ? '⏸️  PAUSED' : '✅ ACTIVE');
    } catch (e) {
      console.log('  Status: ✅ ACTIVE (no pause function)');
    }
    
    console.log('');
    
    // Check specific address if provided
    const addressArg = process.argv[3] || (networkArg && networkArg !== 'testnet' && networkArg !== 'mainnet' ? networkArg : null);
    
    if (addressArg && ethers.isAddress(addressArg)) {
      const address = addressArg;
      
      console.log('💰 Address:', address);
      
      const balance = await contract.balanceOf(address);
      console.log('  Balance:', ethers.formatEther(balance), symbol);
      
      // Check roles
      console.log('  Roles:');
      try {
        const isAdmin = await contract.hasRole(ROLES.DEFAULT_ADMIN_ROLE, address);
        const isMinter = await contract.hasRole(ROLES.MINTER_ROLE, address);
        const isPauser = await contract.hasRole(ROLES.PAUSER_ROLE, address);
        
        console.log('    DEFAULT_ADMIN:', isAdmin ? '✅ YES' : '❌ NO');
        console.log('    MINTER:', isMinter ? '✅ YES' : '❌ NO');
        console.log('    PAUSER:', isPauser ? '✅ YES' : '❌ NO');
      } catch (e) {
        console.log('    Unable to check roles');
      }
      
      console.log('');
    }
    
    console.log('✅ Contract verified successfully!');
    console.log('');
    console.log('🔗 View on BaseScan:');
    console.log('   https://basescan.org/address/' + network.CONTRACT);
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    process.exit(1);
  }
}

main().catch(console.error);
