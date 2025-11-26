# Autonomous Fund Contracts

## Overview

This directory contains the smart contracts for the Autonomous Fund system - a treasury management system that executes BTC perpetual futures trades based on off-chain signals.

## Contracts

### AutonomousFund.sol
Main contract that manages the treasury, accepts trading signals, and enforces risk limits.

**Deployed Address**: `0xcD820c4E99526891374e203b66f509Ae994e6b7D` (Base Mainnet, v2 - Fixed)

### IExecutionAdapter.sol
Interface that all execution adapters must implement. Allows the fund to work with different perpetuals providers.

## Dependencies

- OpenZeppelin Contracts v5
  - `Ownable`
  - `Pausable`
  - `ReentrancyGuard`
  - `SafeERC20`
  - `IERC20`

## Compilation

```bash
# From audit-package root
npx hardhat compile
```

## Documentation

- **Architecture**: `../../docs/autonomous-fund/ARCHITECTURE.md`
- **Deployment**: `../../docs/autonomous-fund/DEPLOYMENT.md`
- **Audit Scope**: `../../AUDIT_SCOPE_AUTONOMOUS_FUND.md`
- **Security Findings**: `../../docs/autonomous-fund/SECURITY_FINDINGS.md`

