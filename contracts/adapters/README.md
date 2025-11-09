# Execution Adapters

## Overview

Execution adapters interface with different perpetuals exchanges to execute trades. The Autonomous Fund uses adapters to abstract away exchange-specific details.

## Contracts

### AvantisAdapter.sol
Adapter for executing trades on Avantis perpetuals exchange (Base Mainnet).

**Deployed Address**: `0x98b71a03B4142178eec62E2378372E8AB87A5B96` (Base Mainnet, v2 - Fixed)

**Features**:
- Opens/closes BTC perpetual positions
- Tracks position IDs and metadata
- Calculates unrealized PnL
- Handles USDC decimal conversion (18 ↔ 6 decimals)
- Manages execution fees in ETH

## Other Adapters (Reference Only)

- **GMXAdapter.sol**: Adapter for GMX (not deployed)
- **SynthetixAdapter.sol**: Adapter for Synthetix (deprecated - shutting down July 2025)
- **MockAdapter.sol**: Mock adapter for testing (not deployed to mainnet)

## Documentation

- **Architecture**: `../../docs/autonomous-fund/ARCHITECTURE.md`
- **Deployment**: `../../docs/autonomous-fund/DEPLOYMENT.md`
- **Avantis Setup**: See `btc-treasury/docs/AVANTIS_SETUP.md` in main repo

