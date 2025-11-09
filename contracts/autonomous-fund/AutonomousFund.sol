// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./IExecutionAdapter.sol";

/**
 * @title AutonomousFund
 * @notice Accepts off-chain signals and executes BTC perpetual trades
 * @dev Simple contract: signal → verify → execute → track
 * 
 * DEPLOYED TO BASE MAINNET
 * Address: 0xE226De8C7832375957c04d9C68E93370E3Ec45Ca
 * Explorer: https://basescan.org/address/0xE226De8C7832375957c04d9C68E93370E3Ec45Ca
 * Deployed: November 9, 2025 (v3 - Added Pyth oracle integration)
 */
contract AutonomousFund is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ Types ============
    
    enum Position { NONE, LONG, SHORT }
    enum Signal { LONG, SHORT, EXIT }
    
    // ============ State ============
    
    Position public currentPosition;
    uint256 public currentPositionSize; // in USDC (collateral)
    uint256 public currentLeverage; // e.g., 2e18 = 2x
    
    // Configurable parameters
    uint256 public maxLeverage; // e.g., 4e18 = 4x
    
    // Signal authorization
    address public signalSigner; // Only this address can send signals
    
    // Treasury
    IERC20 public immutable usdc; // USDC token
    uint256 public treasuryBalance; // Total USDC in contract
    
    // Execution adapter (GMX, Hyperliquid, etc.)
    address public executionAdapter;
    
    // Track position ID from adapter
    bytes32 public currentPositionId;
    
    // Events
    event SignalReceived(Signal signal, uint256 timestamp);
    event PositionOpened(Position position, uint256 size, uint256 leverage, bytes32 positionId);
    event PositionClosed(Position position, int256 pnl);
    event ParametersUpdated(string param, uint256 oldValue, uint256 newValue);
    event ExecutionAdapterUpdated(address oldAdapter, address newAdapter);
    
    // ============ Constructor ============
    
    constructor(
        address _usdc,
        address _signalSigner,
        address _executionAdapter
    ) Ownable(msg.sender) {
        require(_usdc != address(0), "Invalid USDC address");
        require(_signalSigner != address(0), "Invalid signal signer");
        require(_executionAdapter != address(0), "Invalid execution adapter");
        usdc = IERC20(_usdc);
        signalSigner = _signalSigner;
        executionAdapter = _executionAdapter;
        
        // Default parameters
        maxLeverage = 2e18; // 2x
        
        currentPosition = Position.NONE;
    }
    
    // ============ Signal Execution ============
    
    /**
     * @notice Execute a trading signal from off-chain AI
     * @param signal Signal type: LONG, SHORT, or EXIT
     * @param size Position size in USDC (0 = use default)
     * @param leverage Leverage multiplier (e.g., 2e18 = 2x, 0 = use current)
     */
    function executeSignal(
        Signal signal,
        uint256 size,
        uint256 leverage,
        bytes calldata priceUpdateData
    ) external payable whenNotPaused nonReentrant {
        require(msg.sender == signalSigner, "Unauthorized signal");
        
        emit SignalReceived(signal, block.timestamp);
        
        // Update treasury balance (includes unrealized PnL if position open)
        treasuryBalance = getEffectiveTreasuryBalance();
        
        if (signal == Signal.EXIT) {
            _closePosition(priceUpdateData);
        } else {
            // Use ALL capital for the trade
            uint256 positionSize = size > 0 
                ? size 
                : treasuryBalance; // Use entire treasury
            
            // Use provided leverage or max
            uint256 finalLeverage = leverage > 0 ? leverage : maxLeverage;
            
            // Validate leverage
            require(finalLeverage <= maxLeverage, "Leverage too high");
            require(positionSize > 0, "No funds available");
            
            // Determine new position
            Position newPosition = signal == Signal.LONG ? Position.LONG : Position.SHORT;
            
            // Close existing position if switching directions or already have position
            if (currentPosition != Position.NONE) {
                _closePosition(priceUpdateData);
                // Update treasury after close (includes PnL)
                treasuryBalance = getEffectiveTreasuryBalance();
                positionSize = size > 0 ? size : treasuryBalance; // Recalculate with new balance
            }
            
            // Open new position with all capital
            _openPosition(newPosition, positionSize, finalLeverage, priceUpdateData);
        }
    }
    
    // ============ Position Management ============
    
    function _openPosition(
        Position position,
        uint256 size,
        uint256 leverage,
        bytes memory priceUpdateData
    ) internal {
        require(currentPosition == Position.NONE, "Position already open");
        require(size > 0, "Invalid size");
        require(executionAdapter != address(0), "Adapter not set");
        
        // Approve adapter to spend USDC (OpenZeppelin v5 uses forceApprove)
        usdc.forceApprove(executionAdapter, size);
        
        // Call adapter to open position on exchange (forward ETH for execution fee)
        bytes32 positionId;
        if (position == Position.LONG) {
            positionId = IExecutionAdapter(executionAdapter).openLong{value: msg.value}(size, leverage, priceUpdateData);
        } else {
            positionId = IExecutionAdapter(executionAdapter).openShort{value: msg.value}(size, leverage, priceUpdateData);
        }
        
        // Update state
        currentPosition = position;
        currentPositionSize = size;
        currentLeverage = leverage;
        currentPositionId = positionId;
        
        emit PositionOpened(position, size, leverage, positionId);
    }
    
    function _closePosition(bytes memory priceUpdateData) internal {
        require(currentPosition != Position.NONE, "No position to close");
        require(executionAdapter != address(0), "Adapter not set");
        
        Position closedPosition = currentPosition;
        bytes32 positionIdToClose = currentPositionId;
        
        // Call adapter to close position on exchange (forward ETH for execution fee)
        int256 pnl = IExecutionAdapter(executionAdapter).closePosition{value: msg.value}(positionIdToClose, priceUpdateData);
        
        // Reset position state
        currentPosition = Position.NONE;
        currentPositionSize = 0;
        currentLeverage = 0;
        currentPositionId = bytes32(0);
        
        // Update treasury balance after close
        treasuryBalance = usdc.balanceOf(address(this));
        
        emit PositionClosed(closedPosition, pnl);
    }
    
    // ============ Configuration ============
    
    /**
     * @notice Update max leverage
     * @param leverage New max leverage (e.g., 4e18 = 4x)
     */
    function setMaxLeverage(uint256 leverage) external onlyOwner {
        require(leverage >= 1e18 && leverage <= 10e18, "Invalid leverage");
        uint256 oldValue = maxLeverage;
        maxLeverage = leverage;
        emit ParametersUpdated("maxLeverage", oldValue, leverage);
    }
    
    /**
     * @notice Update signal signer address
     */
    function setSignalSigner(address newSigner) external onlyOwner {
        require(newSigner != address(0), "Invalid address");
        signalSigner = newSigner;
    }
    
    /**
     * @notice Update execution adapter
     */
    function setExecutionAdapter(address adapter) external onlyOwner {
        require(adapter != address(0), "Invalid address");
        address oldAdapter = executionAdapter;
        executionAdapter = adapter;
        emit ExecutionAdapterUpdated(oldAdapter, adapter);
    }
    
    // ============ Emergency Controls ============
    
    /**
     * @notice Pause all trading
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @notice Unpause trading
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @notice Emergency close position (bypasses normal checks)
     */
    function emergencyClose() external onlyOwner {
        if (currentPosition != Position.NONE) {
            bytes memory emptyPriceData = new bytes(0);
            _closePosition(emptyPriceData);
        }
    }
    
    /**
     * @notice Withdraw USDC (emergency only)
     */
    function emergencyWithdraw(uint256 amount) external onlyOwner {
        require(currentPosition == Position.NONE, "Close position first");
        SafeERC20.safeTransfer(usdc, owner(), amount);
        treasuryBalance = usdc.balanceOf(address(this));
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get effective treasury balance (USDC + unrealized PnL)
     * @dev This is the true value of treasury including open position value
     */
    function getEffectiveTreasuryBalance() public view returns (uint256) {
        // USDC has 6 decimals, convert to 18 decimals for internal calculations
        uint256 usdcBalance6Dec = usdc.balanceOf(address(this));
        uint256 usdcBalance = usdcBalance6Dec * 1e12; // Convert 6 decimals to 18 decimals
        
        // If position is open, add unrealized PnL
        if (currentPosition != Position.NONE && executionAdapter != address(0) && currentPositionId != bytes32(0)) {
            try IExecutionAdapter(executionAdapter).getUnrealizedPnl(currentPositionId) returns (int256 pnl) {
                if (pnl > 0) {
                    // Profit increases treasury (PnL is already in 18 decimals from adapter)
                    return usdcBalance + uint256(pnl);
                } else if (pnl < 0) {
                    // Loss decreases treasury (but can't go negative)
                    uint256 loss = uint256(-pnl);
                    if (loss < usdcBalance) {
                        return usdcBalance - loss;
                    } else {
                        return 0; // Total loss (shouldn't happen due to liquidation)
                    }
                }
            } catch {
                // If adapter doesn't support getUnrealizedPnl, just return USDC balance
                // Position value is already included in USDC if it was closed
            }
        }
        
        return usdcBalance;
    }
    
    /**
     * @notice Get current position info
     */
    function getPositionInfo() external view returns (
        Position position,
        uint256 size,
        uint256 leverage,
        uint256 utilizationBps
    ) {
        uint256 effectiveTreasury = getEffectiveTreasuryBalance();
        uint256 utilization = effectiveTreasury > 0 
            ? (currentPositionSize * 10000) / effectiveTreasury 
            : 0;
        
        return (
            currentPosition,
            currentPositionSize,
            currentLeverage,
            utilization
        );
    }
    
    /**
     * @notice Get position and PnL data for frontend
     * @return position Current position (0=NONE, 1=LONG, 2=SHORT)
     * @return positionSize Position size in USDC
     * @return leverage Current leverage
     * @return utilizationBps Utilization in basis points
     * @return unrealizedPnl Unrealized PnL in USDC (from adapter)
     * @return totalPnl Total PnL (realized + unrealized)
     */
    function getPositionAndPnl() external view returns (
        uint8 position,
        uint256 positionSize,
        uint256 leverage,
        uint256 utilizationBps,
        int256 unrealizedPnl,
        int256 totalPnl
    ) {
        // Get unrealized PnL from adapter if position is open
        int256 unrealized = 0;
        if (currentPosition != Position.NONE && executionAdapter != address(0) && currentPositionId != bytes32(0)) {
            try IExecutionAdapter(executionAdapter).getUnrealizedPnl(currentPositionId) returns (int256 pnl) {
                unrealized = pnl;
            } catch {
                // If adapter doesn't support getUnrealizedPnl, return 0
                unrealized = 0;
            }
        }
        
        // Calculate effective treasury for utilization (includes unrealized PnL)
        uint256 effectiveTreasury = getEffectiveTreasuryBalance();
        uint256 utilization = effectiveTreasury > 0 
            ? (currentPositionSize * 10000) / effectiveTreasury 
            : 0;
        
        return (
            uint8(currentPosition),
            currentPositionSize,
            currentLeverage,
            utilization,
            unrealized,
            unrealized // Total = unrealized for now (no realized tracking yet)
        );
    }
    
    /**
     * @notice Get all configurable parameters
     */
    function getParameters() external view returns (
        uint256 maxLev,
        address signer,
        address adapter
    ) {
        return (
            maxLeverage,
            signalSigner,
            executionAdapter
        );
    }
}

