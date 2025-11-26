# Autonomous Fund - Deployment Information

## 📋 Deployed Contracts (Base Mainnet)

### AutonomousFund (v7 - **CURRENT**)
**Address**: `0x01a360773623fbC3778d2931bF11f48800Df5d71`  
**Explorer**: https://basescan.org/address/0x01a360773623fbC3778d2931bF11f48800Df5d71  
**Deployed**: November 9, 2025  
**Network**: Base Mainnet (Chain ID: 8453)  
**Version**: v7 (Uses AvantisAdapter v10 with delegatedAction)

**Configuration**:
- **USDC**: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` (Base Mainnet USDC)
- **Signal Signer**: `0xA218db26ed545f3476e6c3E827b595cf2E182533` (Ledger hardware wallet)
- **Execution Adapter**: `0xD66d431AEe720cEF609916f4F34c3528dA20f504` (AvantisAdapter v10)
- **Max Leverage**: 4x (4e18)

**Key Changes in v7**:
- ✅ Uses new AvantisAdapter v10 with `delegatedAction` support
- ✅ No contract changes from v6 - adapter compatibility maintained
- ✅ Accepts BTC `price` as parameter (fetched off-chain from Pyth)
- ✅ `executeSignal(signal, size, leverage, price, priceUpdateData)` signature
- ✅ Function is `payable` to forward ETH for execution fees

### AvantisAdapter (v10 - **CURRENT**)
**Address**: `0xD66d431AEe720cEF609916f4F34c3528dA20f504`  
**Explorer**: https://basescan.org/address/0xD66d431AEe720cEF609916f4F34c3528dA20f504  
**Deployed**: November 9, 2025  
**Network**: Base Mainnet (Chain ID: 8453)  
**Version**: v10 (FINAL - Uses delegatedAction for contract-based trading)

**Configuration**:
- **USDC**: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` (Base Mainnet USDC)
- **BTC Pair Index**: 0 (BTC/USD on Avantis)
- **Owner Address**: `0xA218db26ed545f3476e6c3E827b595cf2E182533` (Ledger - receives all positions)
- **Avantis Trading Contract**: `0x44914408af82bC9983bbb330e3578E1105e11d4e`
- **Avantis PriceAggregator**: `0x64e2625621970F8cfA17B294670d61CB883dA511`
- **Avantis Multicall**: `0xA7cFc43872F4D7B0E6141ee8c36f1F7FEe5d099e`
- **Execution Fee**: 0.001 ETH per trade (forwarded to Avantis)

**Key Changes in v10 (FINAL FIX - delegatedAction)**:
- ✅ **FIXED**: Uses `delegatedAction()` instead of direct `openTrade()` call
- ✅ Allows smart contracts to trade on behalf of an EOA (ownerAddress)
- ✅ Owner (Ledger) receives the position and PnL, not the contract
- ✅ Matches Avantis SDK's `build_trade_open_tx_delegate()` pattern
- ✅ Position ownership: owner EOA (`0xA218...2533`), not this contract
- ✅ Accepts `openPrice` as parameter (fetched off-chain from Pyth)
- ✅ No on-chain price fetching (avoids failed calls)
- ✅ All functions are `payable` to accept ETH for execution fees
- ✅ Owner can withdraw ETH for emergency recovery

**Why v1-v9 Failed**:
- v1-v9 tried to call `openTrade()` directly with `trader = address(this)` (contract)
- **Avantis requires `trader` to be an EOA (wallet), not a contract**
- Reverted with "Avantis openTrade failed"
- **Solution**: Use `delegatedAction(ownerAddress, encodedOpenTradeCall)`
- This allows contracts to execute trades, but owner receives the position

## 🔗 External Dependencies

### Avantis Protocol (Base Mainnet)
- **Trading**: `0x44914408af82bC9983bbb330e3578E1105e11d4e`
- **TradingStorage**: `0x8a311D7048c35985aa31C131B9A13e03a5f7422d`
- **PairStorage**: `0x5db3772136e5557EFE028Db05EE95C84D76faEC4`
- **Multicall**: `0xA7cFc43872F4D7B0E6141ee8c36f1F7FEe5d099e`

### Base Mainnet Tokens
- **USDC**: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` (6 decimals)

## 📊 Current Status

- ✅ Contracts deployed (v7 + v10, uses delegatedAction)
- ✅ Max leverage set to 4x
- ✅ BTC pair index configured (index 0)
- ⏳ AutonomousFund needs funding with USDC
- ⏳ AvantisAdapter needs funding with ETH (for execution fees)
- 🎯 **Ready for live trading after funding**

**Test Plan**:
1. ⏳ Fund AutonomousFund with 10 USDC
2. ⏳ Fund AvantisAdapter with 0.002 ETH
3. ⏳ Send SHORT signal to test live trading with delegatedAction
4. Verify trade executes successfully (owner receives position)
5. Scale up to 100 USDC

## 🔐 Security Notes

- **Signal Signer**: Controlled by Ledger hardware wallet
- **Owner**: Same Ledger address (can pause/update parameters)
- **Reentrancy Protection**: `nonReentrant` modifier on all external functions
- **Access Control**: Only `signalSigner` can execute signals, only `owner` can update parameters

## 📝 Deployment Transactions

1. **AvantisAdapter v10**: `0x9df91d24c3ce87e7aa203292ed7f2fa430a8e653c12b140b358126566c115450`
2. **AutonomousFund v7**: `0x67da4c663ac09077f705d172572a2a5a3ae4e956194201f26d9db6267c9d3541`
3. **Set Max Leverage (4x)**: `0x48fe90f03e8e7b247c27aff3e48ae5481fb2bd9332747631000c185ed6680028`

## 🧪 Testing

Contracts can be tested on Base Sepolia testnet using MockAdapter for development.

## 📚 Documentation

- **Architecture**: See `README_CONTRACT.md` in btc-treasury
- **Avantis Integration**: See `docs/AVANTIS_SETUP.md` in btc-treasury
- **Security Analysis**: See `SECURITY_FINDINGS.md` in btc-treasury

