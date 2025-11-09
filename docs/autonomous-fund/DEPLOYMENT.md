# Autonomous Fund - Deployment Information

## 📋 Deployed Contracts (Base Mainnet)

### AutonomousFund (v3 - **CURRENT**)
**Address**: `0xE226De8C7832375957c04d9C68E93370E3Ec45Ca`  
**Explorer**: https://basescan.org/address/0xE226De8C7832375957c04d9C68E93370E3Ec45Ca  
**Deployed**: November 9, 2025  
**Network**: Base Mainnet (Chain ID: 8453)  
**Version**: v3 (Added Pyth price oracle integration)

**Configuration**:
- **USDC**: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` (Base Mainnet USDC)
- **Signal Signer**: `0xA218db26ed545f3476e6c3E827b595cf2E182533` (Ledger hardware wallet)
- **Execution Adapter**: `0xC0DC344434A048b83a57D07b6adD9744c956f526` (AvantisAdapter v6)
- **Max Leverage**: 4x (4e18)

**Key Changes in v3**:
- ✅ `executeSignal()` now accepts `bytes calldata priceUpdateData` parameter
- ✅ Function is now `payable` to forward ETH for execution fees
- ✅ Forwards Pyth price data to adapter for oracle updates

### AvantisAdapter (v6 - **CURRENT**)
**Address**: `0xC0DC344434A048b83a57D07b6adD9744c956f526`  
**Explorer**: https://basescan.org/address/0xC0DC344434A048b83a57D07b6adD9744c956f526  
**Deployed**: November 9, 2025  
**Network**: Base Mainnet (Chain ID: 8453)  
**Version**: v6 (Full Pyth oracle integration)

**Configuration**:
- **USDC**: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` (Base Mainnet USDC)
- **BTC Pair Index**: 1 (BTC/USD on Avantis)
- **Avantis Trading Contract**: `0x44914408af82bC9983bbb330e3578E1105e11d4e`
- **Avantis PriceAggregator**: `0x64e2625621970F8cfA17B294670d61CB883dA511`
- **Avantis Multicall**: `0xA7cFc43872F4D7B0E6141ee8c36f1F7FEe5d099e`
- **Pyth Oracle**: Hermes API (https://hermes.pyth.network)
- **Execution Fee**: 0.001 ETH per trade (split between Pyth and Avantis)

**Key Changes in v6**:
- ✅ All functions accept `bytes calldata priceUpdateData` parameter
- ✅ Calls `PriceAggregator.updatePriceFeeds()` before each trade
- ✅ All functions are `payable` to accept ETH for Pyth + execution fees
- ✅ Splits `msg.value` between Pyth oracle fee and trade execution fee
- ✅ Ensures fresh price data for every trade (Avantis requirement)

## 🔗 External Dependencies

### Avantis Protocol (Base Mainnet)
- **Trading**: `0x44914408af82bC9983bbb330e3578E1105e11d4e`
- **TradingStorage**: `0x8a311D7048c35985aa31C131B9A13e03a5f7422d`
- **PairStorage**: `0x5db3772136e5557EFE028Db05EE95C84D76faEC4`
- **Multicall**: `0xA7cFc43872F4D7B0E6141ee8c36f1F7FEe5d099e`

### Base Mainnet Tokens
- **USDC**: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` (6 decimals)

## 📊 Current Status

- ✅ Contracts deployed (v3 + v6 with Pyth integration)
- ✅ Max leverage set to 4x
- ✅ BTC pair index configured (index 1)
- ⏳ Awaiting funding for testing
- 🎯 **Next**: Fund with 10 USDC for live test

**Test Plan**:
1. Fund AutonomousFund with 10 USDC
2. Fund AvantisAdapter with 0.002 ETH
3. Send SHORT signal with Pyth price data
4. Verify trade executes successfully
5. Scale up to 100 USDC

## 🔐 Security Notes

- **Signal Signer**: Controlled by Ledger hardware wallet
- **Owner**: Same Ledger address (can pause/update parameters)
- **Reentrancy Protection**: `nonReentrant` modifier on all external functions
- **Access Control**: Only `signalSigner` can execute signals, only `owner` can update parameters

## 📝 Deployment Transactions

1. **AvantisAdapter v6**: `0x9048e4d3c1d530bd96f3503b3afe62ddfab336bfb68f5f79896c7dded7cde043`
2. **AutonomousFund v3**: `0x0d81762b018c56c8bfb5cacb4495096c65272b975ca8120b25780ef877eb1052`
3. **Set Max Leverage (4x)**: `0x55c05b1ff8801c532a152a075d9aa8bacdcbace91f471e6677e32817abe784fd`

## 🧪 Testing

Contracts can be tested on Base Sepolia testnet using MockAdapter for development.

## 📚 Documentation

- **Architecture**: See `README_CONTRACT.md` in btc-treasury
- **Avantis Integration**: See `docs/AVANTIS_SETUP.md` in btc-treasury
- **Security Analysis**: See `SECURITY_FINDINGS.md` in btc-treasury

