# AI Power Grid Smart Contracts

Open-source smart contracts for the AI Power Grid decentralized GPU network.

## Deployed Contracts

**AIPGTokenV2** - ERC20 token on Base Mainnet  
Address: `0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608`  
[View on BaseScan](https://basescan.org/address/0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608)

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
3. **contracts/AIPGTokenV2.sol** - Primary audit target
4. **docs/EMISSIONS_CONTROLLER.md** - EmissionsControllerV2 overview (testnet)
5. **docs/GRIDNFT.md** - GridNFT system overview (testnet)
6. **sdk/README.md** - SDK documentation and usage
7. **examples/README.md** - Reference implementations

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

See `scripts/README.md` for detailed usage instructions.

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
