/**
 * UPGRADE MODELVAULT FACET
 * 
 * Deploys new ModelVault with updateBaseModel() function
 * and calls diamondCut to add the new function selector
 */

const { ethers } = require('ethers');

// This script outputs the steps - actual deployment needs hardhat

const GRID_DIAMOND = '0x79F39f2a0eA476f53994812e6a8f3C8CFe08c609';

// Function selector for updateBaseModel(uint256,string)
const UPDATE_BASEMODEL_SELECTOR = ethers.id('updateBaseModel(uint256,string)').slice(0, 10);

console.log('═══════════════════════════════════════════════════════');
console.log('MODELVAULT FACET UPGRADE PLAN');
console.log('═══════════════════════════════════════════════════════\n');

console.log('New function to add:');
console.log('  updateBaseModel(uint256 modelId, string calldata newBaseModel)');
console.log('  Selector:', UPDATE_BASEMODEL_SELECTOR);
console.log('');

console.log('STEPS:');
console.log('');
console.log('1. Compile updated ModelVault.sol');
console.log('   cd audit-package && npx hardhat compile');
console.log('');
console.log('2. Deploy new ModelVault facet');
console.log('   npx hardhat run scripts/deploy-modelvault-facet.js --network base');
console.log('');
console.log('3. Call diamondCut to ADD the new function');
console.log(`   Diamond: ${GRID_DIAMOND}`);
console.log('   Action: ADD (0)');
console.log(`   Selector: ${UPDATE_BASEMODEL_SELECTOR}`);
console.log('');
console.log('4. Run basemodel migration script');
console.log('   node scripts/migrate-basemodels.js');
console.log('');

console.log('═══════════════════════════════════════════════════════');
console.log('ALTERNATIVE: Manual diamondCut via cast');
console.log('═══════════════════════════════════════════════════════\n');

console.log(`cast send ${GRID_DIAMOND} \\`);
console.log('  "diamondCut((address,uint8,bytes4[])[],address,bytes)" \\');
console.log('  "[(NEW_FACET_ADDRESS,0,[' + UPDATE_BASEMODEL_SELECTOR + '])]" \\');
console.log('  "0x0000000000000000000000000000000000000000" \\');
console.log('  "0x" \\');
console.log('  --rpc-url https://mainnet.base.org \\');
console.log('  --ledger');
