// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IExecutionAdapter
 * @notice Interface for executing trades on different DeFi venues
 * @dev Each venue (GMX, Hyperliquid, etc.) implements this interface
 */
interface IExecutionAdapter {
    /**
     * @notice Open a long BTC position
     * @param collateral Amount of USDC to use as collateral
     * @param leverage Leverage multiplier (e.g., 2e18 = 2x)
     * @return positionId Unique identifier for the position
     */
    function openLong(uint256 collateral, uint256 leverage) 
        external 
        returns (bytes32 positionId);
    
    /**
     * @notice Open a short BTC position
     * @param collateral Amount of USDC to use as collateral
     * @param leverage Leverage multiplier (e.g., 2e18 = 2x)
     * @return positionId Unique identifier for the position
     */
    function openShort(uint256 collateral, uint256 leverage) 
        external 
        returns (bytes32 positionId);
    
    /**
     * @notice Close the current position
     * @param positionId Position to close
     * @return pnl Profit/loss in USDC (can be negative)
     */
    function closePosition(bytes32 positionId) 
        external 
        returns (int256 pnl);
    
    /**
     * @notice Get current position info
     * @param positionId Position to query
     * @return isLong True if long, false if short
     * @return size Position size in USDC
     * @return collateral Collateral amount in USDC
     * @return leverage Current leverage
     */
    function getPosition(bytes32 positionId) 
        external 
        view 
        returns (
            bool isLong,
            uint256 size,
            uint256 collateral,
            uint256 leverage
        );
    
    /**
     * @notice Get unrealized PnL for a position
     * @param positionId Position to query
     * @return pnl Unrealized profit/loss in USDC (can be negative)
     */
    function getUnrealizedPnl(bytes32 positionId) 
        external 
        view 
        returns (int256 pnl);
    
    /**
     * @notice Get all open positions for this contract
     * @return positionIds Array of position IDs
     */
    function getOpenPositions() 
        external 
        view 
        returns (bytes32[] memory positionIds);
}

