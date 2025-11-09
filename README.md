# AI Power Grid Smart Contracts

Open-source smart contracts for the AI Power Grid decentralized GPU network.

## Deployed Contracts

**AIPGTokenV2** - ERC20 token (150M supply, minting disabled)  
Address: `0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608`  
[View on BaseScan](https://basescan.org/address/0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608)

**StakingVault** - Staking rewards (10M AIPG over 1 year)  
Address: `0x3ED14A6D5A48614D77f313389611410d38fd8277`  
[View on BaseScan](https://basescan.org/address/0x3ED14A6D5A48614D77f313389611410d38fd8277)

**Status**: Production (Base Mainnet) | Other contracts on testnet

## Contents

- `contracts/` - Solidity smart contracts
- `docs/` - Deployment addresses and comprehensive documentation
- `scripts/` - Interaction scripts for testing deployed contracts
- `sdk/` - JavaScript SDKs for contract interaction
- `examples/` - Reference implementations and usage examples
- `AUDIT_SCOPE.md` - **READ THIS FIRST** - Detailed audit priorities and scope
- `MANIFEST.md` - Package contents summary
- `package.json` - Node.js dependencies (ethers v6)


## Read First

1. **AUDIT_SCOPE.md** - Understand what to focus on
2. **docs/ADDRESSES.md** - Deployment addresses
3. **docs/STAKING.md** - Staking system documentation (NEW)
4. **docs/TOKENOMICS_AND_ECONOMICS.md** - Economic model and payment flows
5. **docs/NFT_SYSTEM_EXPLAINED.md** - NFT construction and utility (non-technical)
6. **contracts/AIPGTokenV2.sol** - Token contract (minting disabled)
7. **contracts/StakingVault.sol** - Staking contract (LIVE)
8. **sdk/README.md** - SDK documentation and usage
9. **examples/README.md** - Reference implementations

## Testing Scripts

Install dependencies:
```bash
npm install
```

Test the deployed AIPGTokenV2 contract:
```bash
# Check mainnet contract (read-only)
node scripts/interact-aipg-token.js

# Check specific address balance and roles
node scripts/interact-aipg-token.js mainnet 0xYourAddress
```

Test EmissionsController integration (after deployment):
```bash
# Verify roles, configuration, and vault integration
export EMISSIONS_CONTROLLER_ADDRESS=<address>
export STAKING_VAULT_ADDRESS=<address>
node scripts/test-emissions-integration.js
```

See `scripts/README.md` for detailed usage instructions and `docs/DEPLOYMENT_CHECKLIST.md` for deployment steps.

## Contributing

Contributions are welcome! Please:
1. Open an issue for bugs or feature requests
2. Submit pull requests for improvements
3. Follow existing code style and patterns

## License

MIT License - see [LICENSE](LICENSE) file for details

## Links

- [Website](https://aipowergrid.io)
- [Documentation](https://docs.aipowergrid.io)
- [BaseScan](https://basescan.org/address/0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608)

---

**Network**: Base Mainnet (Chain ID: 8453)  
**Contract**: AIPGTokenV2 @ `0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608`
