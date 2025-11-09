# Audit Package Manifest

## 📦 Package Contents

### Core Audit Materials
- `contracts/` - All smart contracts with mainnet addresses in headers
  - `autonomous-fund/` - Autonomous Fund contracts (DEPLOYED)
  - `adapters/` - Execution adapter contracts (DEPLOYED)
- `docs/` - Comprehensive documentation and deployment addresses
  - `autonomous-fund/` - Autonomous Fund documentation
- `AUDIT_SCOPE.md` - Detailed audit priorities and scope (Round 1)
- `AUDIT_SCOPE_AUTONOMOUS_FUND.md` - Autonomous Fund audit scope (Round 2)

### Supporting Materials
- `sdk/` - JavaScript SDKs for all contracts (ethers v6)
- `scripts/` - Read-only interaction scripts for testing
- `examples/` - Reference implementations and usage patterns
- `package.json` - Node.js dependencies

### Security Assurance
- ✅ No secrets, private keys, or `.env` files
- ✅ All sensitive deployment data removed
- ✅ Safe to share with external auditors
