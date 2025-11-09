# Autonomous Fund - Audit Scope & Priorities

## Overview

This audit focuses on the **Autonomous Fund** system - a smart contract that accepts off-chain trading signals and executes BTC perpetual futures trades on Avantis (a decentralized perpetuals exchange on Base).

**Status**: ✅ **DEPLOYED TO BASE MAINNET**  
**Deployment Date**: November 9, 2025  
**Priority**: **HIGH - PRODUCTION CONTRACT WITH REAL FUNDS**

## Contracts Under Audit

### 1. AutonomousFund (DEPLOYED - v6)
**Address**: `0x4De346834C536e1B4Ae47681D4545D655441D253`  
**Location**: `contracts/autonomous-fund/AutonomousFund.sol`  
**Priority**: **CRITICAL**  
**Version**: v6 (FINAL - Accepts price parameter from off-chain)

Main contract that manages treasury, accepts signals, and enforces risk limits.

### 2. AvantisAdapter (DEPLOYED - v9)
**Address**: `0x2F252D2D189C7B916A00C524B9EC2b398aB6BF8C`  
**Location**: `contracts/adapters/AvantisAdapter.sol`  
**Priority**: **HIGH**  
**Version**: v9 (FINAL - Accepts price from off-chain, matches SDK)

**Key Features**:
- **FIXED**: Accepts `openPrice` as parameter (fetched off-chain from Pyth)
- Removed `getPriceFromAggregator()` call (was failing on-chain)
- Matches exactly how Avantis Python SDK works
- Price calculated off-chain: `int(price_data.parsed[0].converted_price * 10**10)`
- Simply forwards ETH for execution fees to Avantis
- `priceUpdateData` parameter kept for interface compatibility but unused
- All functions `payable` to accept ETH for execution fees
- Owner can withdraw ETH for emergency recovery

Adapter contract that interfaces with Avantis Trading contract for trade execution.

### 3. IExecutionAdapter (Interface)
**Location**: `contracts/autonomous-fund/IExecutionAdapter.sol`  
**Priority**: **MEDIUM**

Standard interface for execution adapters. Review for completeness and security.

---

## AutonomousFund - Audit Focus

### 1. Signal Verification & Authorization
- **EIP-712 Signature Verification**
  - Domain separator correctness
  - Signature replay protection (timestamp-based)
  - Signature signer validation
  - Deadline enforcement
  
- **Access Control**
  - `signalSigner` role security
  - Owner role management
  - Pausable functionality

### 2. Risk Management & Position Sizing
- **Leverage Limits**
  - Max leverage enforcement (4x)
  - Leverage validation on signal execution
  - Owner ability to update max leverage
  
- **Position Sizing**
  - Effective treasury balance calculation (USDC + unrealized PnL)
  - Position size calculation correctness
  - All capital usage (100% of treasury)
  
- **Position State Management**
  - Current position tracking (LONG/SHORT/NONE)
  - Position size and leverage tracking
  - State consistency checks

### 3. Treasury Management
- **USDC Handling**
  - SafeERC20 usage
  - Balance tracking
  - Unrealized PnL integration
  
- **Effective Treasury Balance**
  - Calculation correctness
  - Integration with adapter.getUnrealizedPnl()
  - Edge cases (zero balance, negative PnL)

### 4. Trade Execution Flow
- **Signal Processing**
  - LONG signal → open long position
  - SHORT signal → open short position
  - EXIT signal → close current position
  
- **Adapter Integration**
  - Interface compliance
  - Error handling
  - Position ID tracking

### 5. Emergency Controls
- **Pausable**
  - Pause/unpause functionality
  - Impact on signal execution
  - Impact on position management
  
- **Owner Functions**
  - `setMaxLeverage()` security
  - `setSignalSigner()` security
  - `setExecutionAdapter()` security
  - `emergencyWithdraw()` security

### 6. Reentrancy Protection
- `nonReentrant` modifier usage
- Checks-Effects-Interactions pattern
- External call ordering

---

## AvantisAdapter - Audit Focus

### 1. Avantis Integration
- **Contract Interactions**
  - Trading contract calls
  - Multicall usage
  - Low-level call safety
  
- **Trade Execution**
  - `openLong()` implementation
  - `openShort()` implementation
  - `closePosition()` implementation
  
- **Position Tracking**
  - Position ID generation
  - Position info storage
  - User position mapping

### 2. Reentrancy Protection
- **Checks-Effects-Interactions Pattern**
  - State updates BEFORE external calls
  - Position deletion before closePosition() call
  - Position storage before openLong/openShort calls
  
- **Critical**: Previous audit found reentrancy issues that were fixed. Verify fixes are correct.

### 3. USDC Handling
- **Decimal Conversion**
  - 18-decimal to 6-decimal conversion
  - Precision loss handling
  - Rounding behavior
  
- **Token Transfers**
  - SafeERC20 usage
  - Approval handling (forceApprove)
  - Transfer safety

### 4. PnL Calculation
- **Unrealized PnL**
  - Calculation correctness
  - Edge cases (zero position, negative PnL)
  - Integration with Avantis contracts
  
- **Position Data**
  - Entry price tracking
  - Current price retrieval
  - Size and leverage tracking

### 5. Execution Fees
- **ETH Handling**
  - Payable receive function
  - Fee calculation
  - Fee payment to Avantis

### 6. BTC Pair Index
- **Configuration**
  - Constructor parameter
  - `setBtcPairIndex()` function
  - Validation (non-zero check)

---

## Integration Security

### AutonomousFund ↔ AvantisAdapter
- Interface compliance
- Error propagation
- Position ID handling
- PnL calculation integration

### AvantisAdapter ↔ Avantis Protocol
- External contract calls
- Low-level call safety
- Multicall batch operations
- Error handling

---

## Economic Security

### Risk Limits
- Max leverage enforcement (4x)
- Position sizing (100% of treasury)
- No minimum/maximum position size

### Treasury Scaling
- Automatic position resizing based on PnL
- Effective treasury balance calculation
- Edge cases (negative PnL, zero balance)

---

## Known Issues (From Previous Security Analysis)

### ✅ Fixed Issues
1. **Reentrancy in AvantisAdapter**: Fixed by moving state updates before external calls
2. **Dangerous Strict Equality**: Fixed by changing `== 0` to `<= 0`
3. **Zero-Address Validation**: Added constructor checks
4. **OpenZeppelin v5 Compatibility**: Updated imports and function calls

### ⚠️ Medium Severity (False Positives)
- Reentrancy warnings in AutonomousFund are false positives due to `nonReentrant` modifier

---

## Testing Requirements

### Unit Tests
- Signal verification (valid/invalid signatures)
- Leverage enforcement
- Position sizing calculations
- Treasury balance calculations
- PnL calculations

### Integration Tests
- Full signal flow (LONG → SHORT → EXIT)
- Adapter integration
- Avantis contract interactions (mock)

### Edge Cases
- Zero treasury balance
- Negative unrealized PnL
- Maximum leverage scenarios
- Invalid signatures
- Expired timestamps

---

## Audit Deliverables Requested

- [ ] Full security audit report with executive summary
- [ ] Critical/High/Medium/Low severity findings with remediation steps
- [ ] Gas optimization recommendations
- [ ] Access control analysis (signalSigner, owner)
- [ ] EIP-712 signature implementation review
- [ ] Reentrancy analysis (verify fixes are correct)
- [ ] Integration security review (AutonomousFund ↔ AvantisAdapter ↔ Avantis)
- [ ] Economic security review (leverage limits, position sizing)
- [ ] Edge case analysis (zero balance, negative PnL, etc.)
- [ ] Test coverage recommendations
- [ ] Deployment verification checklist

---

## Deployment Information

See `docs/autonomous-fund/DEPLOYMENT.md` for:
- Contract addresses
- Deployment transactions
- Configuration details
- External dependencies

---

## Architecture Documentation

See `docs/autonomous-fund/ARCHITECTURE.md` for:
- System overview
- Component responsibilities
- Signal flow
- Risk management
- Security features

---

## Timeline

- **Target**: Complete audit within 2-3 weeks
- **Priority**: HIGH (contracts are deployed and will hold real funds)
- **Status**: Contracts deployed, awaiting initial funding

---

## Contact & Questions

For questions about:
- **Architecture**: See `docs/autonomous-fund/ARCHITECTURE.md`
- **Deployment**: See `docs/autonomous-fund/DEPLOYMENT.md`
- **Security Analysis**: See `SECURITY_FINDINGS.md` in btc-treasury (previous analysis)

---

**Last Updated**: November 9, 2025  
**Audit Status**: Ready for audit

