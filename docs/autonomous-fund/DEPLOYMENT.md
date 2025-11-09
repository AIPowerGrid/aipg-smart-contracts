# Autonomous Fund - Deployment Information

## 📋 Deployed Contracts (Base Mainnet)

### AutonomousFund (v4 - **CURRENT**)
**Address**: `0x934b5a80505fEd84c42f48006d159B0d394EA81e`  
**Explorer**: https://basescan.org/address/0x934b5a80505fEd84c42f48006d159B0d394EA81e  
**Deployed**: November 9, 2025  
**Network**: Base Mainnet (Chain ID: 8453)  
**Version**: v4 (Fixed Avantis adapter integration)

**Configuration**:
- **USDC**: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` (Base Mainnet USDC)
- **Signal Signer**: `0xA218db26ed545f3476e6c3E827b595cf2E182533` (Ledger hardware wallet)
- **Execution Adapter**: `0x1A1A6791cB54aCE3924F90563f5B2AD4F7f03387` (AvantisAdapter v7)
- **Max Leverage**: 4x (4e18)

**Key Changes in v4**:
- ✅ Fixed adapter to work correctly with Avantis (v7 adapter)
- ✅ `executeSignal()` accepts `bytes calldata priceUpdateData` parameter (interface only)
- ✅ Function is `payable` to forward ETH for execution fees

### AvantisAdapter (v7 - **CURRENT**)
**Address**: `0x1A1A6791cB54aCE3924F90563f5B2AD4F7f03387`  
**Explorer**: https://basescan.org/address/0x1A1A6791cB54aCE3924F90563f5B2AD4F7f03387  
**Deployed**: November 9, 2025  
**Network**: Base Mainnet (Chain ID: 8453)  
**Version**: v7 (Fixed - Removed manual Pyth calls)

**Configuration**:
- **USDC**: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` (Base Mainnet USDC)
- **BTC Pair Index**: 1 (BTC/USD on Avantis)
- **Avantis Trading Contract**: `0x44914408af82bC9983bbb330e3578E1105e11d4e`
- **Avantis PriceAggregator**: `0x64e2625621970F8cfA17B294670d61CB883dA511`
- **Avantis Multicall**: `0xA7cFc43872F4D7B0E6141ee8c36f1F7FEe5d099e`
- **Execution Fee**: 0.001 ETH per trade (forwarded to Avantis)

**Key Changes in v7 (BUG FIX)**:
- ✅ **FIXED**: Removed manual `PriceAggregator.updatePriceFeeds()` calls
- ✅ Avantis handles Pyth oracle updates internally
- ✅ Simply forward full `msg.value` as ETH execution fee to Avantis
- ✅ `priceUpdateData` parameter kept for interface compatibility but unused
- ✅ All functions are `payable` to accept ETH for execution fees
- ✅ Owner can withdraw ETH for emergency recovery

**Why v6 Failed**:
- v6 tried to manually call `PRICE_AGGREGATOR.updatePriceFeeds()` which doesn't exist or isn't the right interface
- Avantis SDK doesn't pass Pyth data - it just sends ETH and Avantis handles Pyth internally
- Transaction reverted with "Pyth price update failed"

## 🔗 External Dependencies

### Avantis Protocol (Base Mainnet)
- **Trading**: `0x44914408af82bC9983bbb330e3578E1105e11d4e`
- **TradingStorage**: `0x8a311D7048c35985aa31C131B9A13e03a5f7422d`
- **PairStorage**: `0x5db3772136e5557EFE028Db05EE95C84D76faEC4`
- **Multicall**: `0xA7cFc43872F4D7B0E6141ee8c36f1F7FEe5d099e`

### Base Mainnet Tokens
- **USDC**: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` (6 decimals)

## 📊 Current Status

- ✅ Contracts deployed (v4 + v7, fixed Avantis integration)
- ✅ Max leverage set to 4x
- ✅ BTC pair index configured (index 1)
- ✅ AutonomousFund funded with 10 USDC
- ✅ AvantisAdapter funded with 0.002 ETH
- 🎯 **Ready for live trading**

**Test Plan**:
1. ✅ Fund AutonomousFund with 10 USDC
2. ✅ Fund AvantisAdapter with 0.002 ETH
3. ⏳ Send SHORT signal to test live trading
4. Verify trade executes successfully
5. Scale up to 100 USDC

## 🔐 Security Notes

- **Signal Signer**: Controlled by Ledger hardware wallet
- **Owner**: Same Ledger address (can pause/update parameters)
- **Reentrancy Protection**: `nonReentrant` modifier on all external functions
- **Access Control**: Only `signalSigner` can execute signals, only `owner` can update parameters

## 📝 Deployment Transactions

1. **AvantisAdapter v7**: `0xed38865b8ccd872db4a8b60a1e328adbb527cdf385f3b544c3dcd0841a85fafd`
2. **AutonomousFund v4**: `0x1e59f4d78df5a275e980204f081d2a96e442cba25a3ec5e793a58f4871cc3bca`
3. **Set Max Leverage (4x)**: `0x948ff15f9c2a8d35bea4cc5aa31df5ff3599d66c388c8f6e578e9973b093624b`

## 🧪 Testing

Contracts can be tested on Base Sepolia testnet using MockAdapter for development.

## 📚 Documentation

- **Architecture**: See `README_CONTRACT.md` in btc-treasury
- **Avantis Integration**: See `docs/AVANTIS_SETUP.md` in btc-treasury
- **Security Analysis**: See `SECURITY_FINDINGS.md` in btc-treasury

