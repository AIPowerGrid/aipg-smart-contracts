# Autonomous Fund - Deployment Information

## 📋 Deployed Contracts (Base Mainnet)

### AutonomousFund (v5 - **CURRENT**)
**Address**: `0xB1d634707554782aC330217329A38E80D03A59B1`  
**Explorer**: https://basescan.org/address/0xB1d634707554782aC330217329A38E80D03A59B1  
**Deployed**: November 9, 2025  
**Network**: Base Mainnet (Chain ID: 8453)  
**Version**: v5 (Final - with working Avantis adapter v8)

**Configuration**:
- **USDC**: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` (Base Mainnet USDC)
- **Signal Signer**: `0xA218db26ed545f3476e6c3E827b595cf2E182533` (Ledger hardware wallet)
- **Execution Adapter**: `0xE1b17dB476Cad5B367FD03A5E61ca322bDE099b2` (AvantisAdapter v8)
- **Max Leverage**: 4x (4e18)

**Key Changes in v5**:
- ✅ Fixed adapter to work correctly with Avantis (v8 adapter calls getPriceFromAggregator)
- ✅ `executeSignal()` accepts `bytes calldata priceUpdateData` parameter (interface only)
- ✅ Function is `payable` to forward ETH for execution fees

### AvantisAdapter (v8 - **CURRENT**)
**Address**: `0xE1b17dB476Cad5B367FD03A5E61ca322bDE099b2`  
**Explorer**: https://basescan.org/address/0xE1b17dB476Cad5B367FD03A5E61ca322bDE099b2  
**Deployed**: November 9, 2025  
**Network**: Base Mainnet (Chain ID: 8453)  
**Version**: v8 (FINAL - Calls getPriceFromAggregator)

**Configuration**:
- **USDC**: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` (Base Mainnet USDC)
- **BTC Pair Index**: 1 (BTC/USD on Avantis)
- **Avantis Trading Contract**: `0x44914408af82bC9983bbb330e3578E1105e11d4e`
- **Avantis PriceAggregator**: `0x64e2625621970F8cfA17B294670d61CB883dA511`
- **Avantis Multicall**: `0xA7cFc43872F4D7B0E6141ee8c36f1F7FEe5d099e`
- **Execution Fee**: 0.001 ETH per trade (forwarded to Avantis)

**Key Changes in v8 (FINAL FIX)**:
- ✅ **FIXED**: Calls `getPriceFromAggregator(pairIndex, 0)` to fetch current BTC price
- ✅ Sets `openPrice` correctly for market orders (Avantis requires this)
- ✅ No manual Pyth calls (Avantis handles Pyth internally)
- ✅ Simply forwards ETH for execution fees to Avantis
- ✅ `priceUpdateData` parameter kept for interface compatibility but unused
- ✅ All functions are `payable` to accept ETH for execution fees
- ✅ Owner can withdraw ETH for emergency recovery

**Why v7 Failed**:
- v7 set `openPrice = 0` but Avantis requires the actual price
- Avantis SDK calls `get_latest_price_updates()` and sets `openPrice` for market orders (line 69-71 in SDK)
- Transaction reverted with "Avantis openTrade failed"

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

1. **AvantisAdapter v8**: `0x63ede2a0ede34ec8eeccea6e0a3d2ee0b5cdd22c2c5fbe2b5632cf4984cd12d0`
2. **AutonomousFund v5**: `0xe35b0db57f3f8d9816c7fcecde0b3c8c35ad3a8f1f2f4a6d73f6b73e6e8df37c`
3. **Set Max Leverage (4x)**: `0x0cbed5bbe60b021a40015f51b8e5a7f245d130128a928bdc7ac109996994ddd3`

## 🧪 Testing

Contracts can be tested on Base Sepolia testnet using MockAdapter for development.

## 📚 Documentation

- **Architecture**: See `README_CONTRACT.md` in btc-treasury
- **Avantis Integration**: See `docs/AVANTIS_SETUP.md` in btc-treasury
- **Security Analysis**: See `SECURITY_FINDINGS.md` in btc-treasury

