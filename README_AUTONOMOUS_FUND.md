# Autonomous Fund - Quick Start for Auditors

## 📋 Overview

The Autonomous Fund is a smart contract system deployed to **Base Mainnet** that executes BTC perpetual futures trades based on off-chain trading signals.

**Status**: ✅ **DEPLOYED** (November 9, 2025)  
**Priority**: **HIGH** - Production contracts that will hold real funds

## 🎯 Start Here

1. **Read Audit Scope**: `AUDIT_SCOPE_AUTONOMOUS_FUND.md`
2. **Review Architecture**: `docs/autonomous-fund/ARCHITECTURE.md`
3. **Check Deployment Info**: `docs/autonomous-fund/DEPLOYMENT.md`
4. **Review Security Findings**: `docs/autonomous-fund/SECURITY_FINDINGS.md`

## 📁 Contract Locations

- **AutonomousFund**: `contracts/autonomous-fund/AutonomousFund.sol`
- **AvantisAdapter**: `contracts/adapters/AvantisAdapter.sol`
- **IExecutionAdapter**: `contracts/autonomous-fund/IExecutionAdapter.sol`

## 🔗 Deployed Addresses (Base Mainnet)

- **AutonomousFund**: `0xB1d634707554782aC330217329A38E80D03A59B1` (v5)
- **AvantisAdapter**: `0xE1b17dB476Cad5B367FD03A5E61ca322bDE099b2` (v8)

## 🔍 Key Audit Areas

1. **Signal Verification** - EIP-712 signature verification
2. **Reentrancy Protection** - Verify fixes are correct
3. **Risk Management** - Leverage limits, position sizing
4. **Adapter Integration** - AutonomousFund ↔ AvantisAdapter ↔ Avantis
5. **Treasury Management** - USDC handling, PnL calculations

## 📚 Documentation Structure

```
audit-package/
├── AUDIT_SCOPE_AUTONOMOUS_FUND.md    # Complete audit scope
├── contracts/
│   ├── autonomous-fund/
│   │   ├── AutonomousFund.sol        # Main contract
│   │   ├── IExecutionAdapter.sol    # Interface
│   │   └── README.md                 # Contract docs
│   └── adapters/
│       ├── AvantisAdapter.sol        # Avantis adapter
│       └── README.md                 # Adapter docs
└── docs/
    └── autonomous-fund/
        ├── DEPLOYMENT.md             # Deployment details
        ├── ARCHITECTURE.md           # System architecture
        └── SECURITY_FINDINGS.md      # Previous security analysis
```

## ✅ Previous Security Work

- Slither analysis completed
- HIGH severity issues fixed (reentrancy, strict equality)
- MEDIUM issues analyzed (false positives)
- OpenZeppelin v5 compatibility verified

## 🚀 Ready for Audit

All contracts, documentation, and security analysis are ready for review.
