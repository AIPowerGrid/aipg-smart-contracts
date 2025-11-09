# Autonomous Fund - Architecture Overview

## Purpose

The Autonomous Fund is a smart contract system that accepts off-chain trading signals and executes BTC perpetual futures trades on Avantis (a decentralized perpetuals exchange on Base). The system is designed for automated treasury management with strict risk controls.

## System Components

### 1. AutonomousFund (Main Contract)

**Location**: `contracts/autonomous-fund/AutonomousFund.sol`

**Responsibilities**:
- Accepts EIP-712 signed trading signals from authorized signer
- Enforces risk limits (max leverage, position sizing)
- Manages USDC treasury
- Tracks current position state
- Delegates trade execution to execution adapter

**Key Features**:
- **Signal Verification**: EIP-712 signature verification for off-chain signals
- **Risk Management**: Max leverage enforcement (4x), position size limits
- **Treasury Management**: Tracks USDC balance + unrealized PnL
- **Position Tracking**: Current position (LONG/SHORT/NONE), size, leverage
- **Emergency Controls**: Pausable, owner-controlled parameter updates

**State Variables**:
- `currentPosition`: Position enum (NONE, LONG, SHORT)
- `currentPositionSize`: Position size in USDC (collateral)
- `currentLeverage`: Current leverage multiplier (e.g., 2e18 = 2x)
- `maxLeverage`: Maximum allowed leverage (4e18 = 4x)
- `signalSigner`: Address authorized to send signals
- `executionAdapter`: Address of adapter contract for trade execution
- `usdc`: USDC token address (immutable)

**Key Functions**:
- `executeSignal(Signal signal, uint256 timestamp, bytes signature)`: Main entry point for trading signals
- `getPositionAndPnl()`: Returns current position info and unrealized PnL
- `getEffectiveTreasuryBalance()`: Calculates USDC balance + unrealized PnL
- `setMaxLeverage(uint256)`: Owner function to update max leverage
- `setSignalSigner(address)`: Owner function to update signal signer
- `setExecutionAdapter(address)`: Owner function to update adapter

### 2. AvantisAdapter (Execution Adapter)

**Location**: `contracts/adapters/AvantisAdapter.sol`

**Responsibilities**:
- Interfaces with Avantis Trading contract
- Executes long/short BTC perpetual trades
- Closes positions
- Tracks position IDs and metadata
- Calculates unrealized PnL

**Key Features**:
- **Trade Execution**: Opens/closes BTC perpetual positions on Avantis
- **Position Tracking**: Maps position IDs to position info
- **PnL Calculation**: Calculates unrealized PnL from Avantis
- **USDC Handling**: Converts between 18-decimal and 6-decimal USDC
- **Execution Fees**: Handles ETH fees for Avantis trades

**State Variables**:
- `usdc`: USDC token address (immutable)
- `btcPairIndex`: Avantis BTC/USD pair index (currently 1)
- `positions`: Mapping of position ID to position info
- `userPositions`: Mapping of user to array of position IDs

**Key Functions**:
- `openLong(uint256 collateral, uint256 leverage)`: Opens long BTC position
- `openShort(uint256 collateral, uint256 leverage)`: Opens short BTC position
- `closePosition(bytes32 positionId)`: Closes position and returns PnL
- `getUnrealizedPnl(bytes32 positionId)`: Returns current unrealized PnL
- `getPosition(bytes32 positionId)`: Returns position details

### 3. IExecutionAdapter (Interface)

**Location**: `contracts/autonomous-fund/IExecutionAdapter.sol`

Standard interface that all execution adapters must implement. Allows AutonomousFund to work with different perpetuals providers (Avantis, GMX, Synthetix, etc.).

## Signal Flow

```
1. Off-chain bot generates trading signal (LONG/SHORT/EXIT)
2. Bot signs signal with EIP-712 using signalSigner private key
3. Bot calls executeSignal() with signal, timestamp, signature
4. AutonomousFund verifies signature and timestamp
5. AutonomousFund checks risk limits (leverage, position size)
6. AutonomousFund calls adapter.openLong() or adapter.openShort()
7. Adapter executes trade on Avantis
8. Adapter returns position ID
9. AutonomousFund stores position ID and updates state
```

## Risk Management

### Leverage Limits
- **Max Leverage**: 4x (configurable by owner)
- Enforced on every signal execution
- Stored as 18-decimal value (4e18 = 4x)

### Position Sizing
- Uses **all available capital** (USDC + unrealized PnL)
- Calculated as: `positionSize = effectiveTreasuryBalance * leverage`
- No minimum/maximum position size limits (uses all capital)

### Treasury Management
- **Effective Treasury Balance** = USDC balance + unrealized PnL
- Position size recalculated on each signal based on current treasury
- Automatically scales position with treasury growth/losses

## Security Features

### Access Control
- **Signal Signer**: Only authorized address can send signals (EIP-712 verified)
- **Owner**: Can pause, update parameters, emergency withdraw
- **Reentrancy Protection**: `nonReentrant` modifier on all external functions

### Checks-Effects-Interactions Pattern
- State updates happen BEFORE external calls
- Prevents reentrancy attacks
- Implemented in AvantisAdapter (position tracking before trade execution)

### Zero-Address Validation
- Constructor validates all addresses are non-zero
- Prevents deployment with invalid configuration

### Immutable Variables
- `usdc`: Immutable to prevent accidental changes
- Critical addresses set at deployment

## Integration Points

### Avantis Protocol
- Uses Avantis Trading contract for trade execution
- Uses Avantis Multicall for batch operations
- Relies on Avantis price oracle for BTC/USD pricing
- Pays execution fees in ETH (not USDC)

### USDC Token
- Base Mainnet USDC (6 decimals)
- Adapter handles conversion between 18-decimal and 6-decimal formats
- AutonomousFund uses 18-decimal internally for precision

## Known Limitations

1. **Single Position**: Can only hold one position at a time (LONG or SHORT, not both)
2. **All Capital**: Uses 100% of treasury for each position (no partial allocation)
3. **ETH Dependency**: AvantisAdapter needs ETH balance for execution fees
4. **BTC Only**: Currently configured only for BTC/USD pair (index 1)

## Future Enhancements

- Support for multiple positions
- Partial position sizing (utilization cap)
- Multi-asset support (ETH, etc.)
- Gas optimization improvements
- Additional adapter implementations (GMX, Hyperliquid)

