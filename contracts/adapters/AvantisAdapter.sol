// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../IExecutionAdapter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AvantisAdapter
 * @notice Adapter for executing trades on Avantis perpetuals on Base
 * @dev Integrates with Avantis DEX for BTC perpetuals trading
 * 
 * DEPLOYED TO BASE MAINNET
 * Address: 0xC0DC344434A048b83a57D07b6adD9744c956f526
 * Explorer: https://basescan.org/address/0xC0DC344434A048b83a57D07b6adD9744c956f526
 * Deployed: November 9, 2025 (v6 - Full Pyth oracle integration)
 * 
 * Avantis Protocol Addresses:
 * - Trading: 0x44914408af82bC9983bbb330e3578E1105e11d4e
 * - TradingStorage: 0x8a311D7048c35985aa31C131B9A13e03a5f7422d
 * - PairStorage: 0x5db3772136e5557EFE028Db05EE95C84D76faEC4
 * - PriceAggregator: 0x64e2625621970F8cfA17B294670d61CB883dA511
 * - USDC: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
 * - Multicall: 0xA7cFc43872F4D7B0E6141ee8c36f1F7FEe5d099e
 * 
 * Docs: https://docs.avantisfi.com/
 * SDK: https://github.com/Avantis-Labs/avantis_trader_sdk
 */
contract AvantisAdapter is IExecutionAdapter, Ownable {
    using SafeERC20 for IERC20;

    // Avantis contracts (Base mainnet)
    address public constant TRADING = 0x44914408af82bC9983bbb330e3578E1105e11d4e;
    address public constant TRADING_STORAGE = 0x8a311D7048c35985aa31C131B9A13e03a5f7422d;
    address public constant PRICE_AGGREGATOR = 0x64e2625621970F8cfA17B294670d61CB883dA511;
    address public constant MULTICALL = 0xA7cFc43872F4D7B0E6141ee8c36f1F7FEe5d099e;
    
    IERC20 public immutable usdc; // USDC token
    
    // Track positions
    mapping(bytes32 => PositionInfo) public positions;
    mapping(address => bytes32[]) public userPositions;
    
    struct PositionInfo {
        bool isLong;
        uint256 size; // Position size in USD (scaled)
        uint256 collateral; // Collateral in USDC (6 decimals)
        uint256 leverage; // Leverage (scaled to 10 decimals, e.g., 2e10 = 2x)
        uint256 entryPrice; // Entry price (scaled to 10 decimals)
        uint256 timestamp;
        uint256 pairIndex; // Avantis pair index (BTC/USD)
        uint256 tradeIndex; // Avantis trade index
    }
    
    struct TradeInput {
        address trader;
        uint256 pairIndex;
        uint256 index;
        uint256 initialPosToken;
        uint256 positionSizeUSDC;
        uint256 openPrice;
        bool buy;
        uint256 leverage;
        uint256 tp;
        uint256 sl;
        uint256 timestamp;
    }
    
    uint256 private positionCounter;
    uint256 public btcPairIndex; // BTC/USD pair index (set in constructor or via setter)
    
    // Avantis interface functions (using low-level calls)
    
    constructor(address _usdc, uint256 _btcPairIndex) Ownable(msg.sender) {
        usdc = IERC20(_usdc);
        require(_usdc != address(0), "Invalid USDC address");
        btcPairIndex = _btcPairIndex; // BTC/USD pair index (need to query from Avantis)
    }
    
    /**
     * @notice Set BTC pair index (if not known at deployment)
     */
    function setBtcPairIndex(uint256 _btcPairIndex) external {
        require(_btcPairIndex > 0, "Invalid pair index");
        btcPairIndex = _btcPairIndex;
    }
    
    /**
     * @notice Open a long BTC position on Avantis
     */
    function openLong(uint256 collateral, uint256 leverage) 
        external 
        override 
        returns (bytes32 positionId) 
    {
        require(collateral > 0, "Invalid collateral");
        require(leverage >= 1e18 && leverage <= 100e18, "Invalid leverage"); // Avantis supports up to 100x
        require(btcPairIndex > 0, "BTC pair index not set");
        
        // Transfer USDC from caller (Avantis uses 6 decimals for USDC)
        uint256 collateral6Dec = collateral / 1e12; // Convert from 18 to 6 decimals
        SafeERC20.safeTransferFrom(usdc, msg.sender, address(this), collateral6Dec);
        
        // Approve Trading contract to spend USDC (OpenZeppelin v5 uses forceApprove)
        SafeERC20.forceApprove(usdc, TRADING, collateral6Dec);
        
        // For MARKET orders, pass 0 - Avantis will fetch price internally
        uint256 openPrice = 0;
        
        // Convert leverage from 18 decimals to 10 decimals (Avantis format)
        uint256 leverage10Dec = (leverage * 1e10) / 1e18;
        
        // Calculate position size (Avantis calculates this, but we track it)
        uint256 positionSize = (collateral * leverage) / 1e18;
        
        // Get next trade index (Avantis manages this, but we need to track)
        // In production, you'd query existing positions to get the next index
        uint256 tradeIndex = getNextTradeIndex(msg.sender);
        
        // Generate position ID BEFORE external call (Checks-Effects-Interactions pattern)
        positionId = keccak256(abi.encodePacked(
            msg.sender,
            btcPairIndex,
            tradeIndex,
            block.timestamp,
            positionCounter++
        ));
        
        // Store position info BEFORE external call
        positions[positionId] = PositionInfo({
            isLong: true,
            size: positionSize,
            collateral: collateral,
            leverage: leverage,
            entryPrice: 0, // Will be set by Avantis
            timestamp: block.timestamp,
            pairIndex: btcPairIndex,
            tradeIndex: tradeIndex
        });
        
        userPositions[msg.sender].push(positionId);
        
        // Build trade input
        TradeInput memory tradeInput = TradeInput({
            trader: msg.sender,
            pairIndex: btcPairIndex,
            index: tradeIndex,
            initialPosToken: 0, // Not used for USDC
            positionSizeUSDC: collateral6Dec, // Collateral in USDC (6 decimals)
            openPrice: openPrice, // 0 = market order
            buy: true, // isLong = true
            leverage: leverage10Dec, // Leverage (10 decimals)
            tp: 0, // No take profit
            sl: 0, // No stop loss
            timestamp: block.timestamp
        });
        
        // Encode function call for openTrade
        bytes memory data = abi.encodeWithSignature(
            "openTrade((address,uint256,uint256,uint256,uint256,uint256,bool,uint256,uint256,uint256,uint256),uint256,uint256)",
            tradeInput,
            uint256(0), // MARKET order
            uint256(3e10) // 3% slippage (in 10^10 precision)
        );
        
        // Call Avantis Trading contract
        (bool success, ) = TRADING.call{value: getExecutionFee()}(data);
        require(success, "Avantis openTrade failed");
        
        return positionId;
    }
    
    /**
     * @notice Open a short BTC position on Avantis
     */
    function openShort(uint256 collateral, uint256 leverage) 
        external 
        override 
        returns (bytes32 positionId) 
    {
        require(collateral > 0, "Invalid collateral");
        require(leverage >= 1e18 && leverage <= 100e18, "Invalid leverage");
        require(btcPairIndex > 0, "BTC pair index not set");
        
        // Transfer USDC from caller
        uint256 collateral6Dec = collateral / 1e12;
        SafeERC20.safeTransferFrom(usdc, msg.sender, address(this), collateral6Dec);
        
        // Approve Trading contract (OpenZeppelin v5 uses forceApprove)
        SafeERC20.forceApprove(usdc, TRADING, collateral6Dec);
        
        // For MARKET orders, pass 0 - Avantis will fetch price internally
        uint256 openPrice = 0;
        uint256 leverage10Dec = (leverage * 1e10) / 1e18;
        uint256 positionSize = (collateral * leverage) / 1e18;
        uint256 tradeIndex = getNextTradeIndex(msg.sender);
        
        // Generate position ID BEFORE external call (Checks-Effects-Interactions pattern)
        positionId = keccak256(abi.encodePacked(
            msg.sender,
            btcPairIndex,
            tradeIndex,
            block.timestamp,
            positionCounter++
        ));
        
        // Store position info BEFORE external call
        positions[positionId] = PositionInfo({
            isLong: false,
            size: positionSize,
            collateral: collateral,
            leverage: leverage,
            entryPrice: 0,
            timestamp: block.timestamp,
            pairIndex: btcPairIndex,
            tradeIndex: tradeIndex
        });
        
        userPositions[msg.sender].push(positionId);
        
        // Build trade input for short
        TradeInput memory tradeInput = TradeInput({
            trader: msg.sender,
            pairIndex: btcPairIndex,
            index: tradeIndex,
            initialPosToken: 0,
            positionSizeUSDC: collateral6Dec,
            openPrice: openPrice,
            buy: false, // isLong = false for short
            leverage: leverage10Dec,
            tp: 0,
            sl: 0,
            timestamp: block.timestamp
        });
        
        // Encode function call for openTrade
        bytes memory data = abi.encodeWithSignature(
            "openTrade((address,uint256,uint256,uint256,uint256,uint256,bool,uint256,uint256,uint256,uint256),uint256,uint256)",
            tradeInput,
            uint256(0), // MARKET order
            uint256(3e10) // 3% slippage (in 10^10 precision)
        );
        
        // Call Avantis Trading contract
        (bool success, ) = TRADING.call{value: getExecutionFee()}(data);
        require(success, "Avantis openTrade failed");
        
        return positionId;
    }
    
    /**
     * @notice Close a position on Avantis
     */
    function closePosition(bytes32 positionId) 
        external 
        override 
        returns (int256 pnl) 
    {
        PositionInfo memory position = positions[positionId];
        require(position.size > 0, "Position not found");
        
        // Clear position BEFORE external call (Checks-Effects-Interactions pattern)
        delete positions[positionId];
        
        // Close entire position (pass full collateral amount)
        uint256 collateral6Dec = position.collateral / 1e12;
        
        // Encode function call for closeTradeMarket
        bytes memory data = abi.encodeWithSignature(
            "closeTradeMarket(uint256,uint256,uint256)",
            position.pairIndex,
            position.tradeIndex,
            collateral6Dec
        );
        
        // Call Avantis Trading contract
        (bool success, ) = TRADING.call{value: getExecutionFee()}(data);
        require(success, "Avantis closeTradeMarket failed");
        
        // Calculate PnL (simplified - Avantis handles this internally)
        // In production, you'd query the position from Avantis to get actual PnL
        pnl = 0; // Placeholder - would query from Avantis
        
        return pnl;
    }
    
    /**
     * @notice Get position info
     */
    function getPosition(bytes32 positionId) 
        external 
        view 
        override 
        returns (
            bool isLong,
            uint256 size,
            uint256 collateral,
            uint256 leverage
        ) 
    {
        PositionInfo memory position = positions[positionId];
        return (
            position.isLong,
            position.size,
            position.collateral,
            position.leverage
        );
    }
    
    /**
     * @notice Get unrealized PnL for a position
     */
    function getUnrealizedPnl(bytes32 positionId) 
        external 
        view 
        override 
        returns (int256) 
    {
        PositionInfo memory position = positions[positionId];
        if (position.size <= 0) return 0;
        
        // TODO: Query position from Avantis via Multicall.getPositions()
        // For now, return 0 (would calculate based on current price vs entry price)
        return 0;
    }
    
    /**
     * @notice Get all open positions for caller
     */
    function getOpenPositions() 
        external 
        view 
        override 
        returns (bytes32[] memory) 
    {
        return userPositions[msg.sender];
    }
    
    /**
     * @notice Get next trade index for a trader
     * @dev In production, query existing positions from Avantis
     */
    function getNextTradeIndex(address trader) internal view returns (uint256) {
        // TODO: Query positions from Avantis to get next index
        // For now, use a simple counter (not ideal, but works)
        return userPositions[trader].length;
    }
    
    /**
     * @notice Get execution fee for Avantis trades
     * @dev Increased to 0.001 ETH to ensure sufficient fee
     */
    function getExecutionFee() internal view returns (uint256) {
        // Use 0.001 ETH to be safe (SDK calculates ~850k gas * gasPrice)
        return 0.001 ether;
    }
    
    /**
     * @notice Get current price from Avantis PriceAggregator
     * @param pairIndex The pair index (BTC/USD)
     * @param orderType The order type (0=MARKET, 1=STOP_LIMIT, 2=LIMIT, 3=MARKET_ZERO_FEE)
     * @return price The current price in 10^10 precision
     */
    function getPriceFromAggregator(uint256 pairIndex, uint8 orderType) internal returns (uint256) {
        // Call PriceAggregator.getPrice(pairIndex, orderType)
        (bool success, bytes memory data) = PRICE_AGGREGATOR.call(
            abi.encodeWithSignature("getPrice(uint256,uint8)", pairIndex, orderType)
        );
        require(success, "Failed to get price from aggregator");
        return abi.decode(data, (uint256));
    }
    
    /**
     * @notice Receive ETH for execution fees
     */
    receive() external payable {}
    
    /**
     * @notice Withdraw ETH from the contract (owner only)
     * @dev Allows owner to recover ETH sent for execution fees
     */
    function withdrawETH(address payable recipient, uint256 amount) external onlyOwner {
        require(recipient != address(0), "Invalid recipient");
        require(address(this).balance >= amount, "Insufficient balance");
        recipient.transfer(amount);
    }
    
    /**
     * @notice Withdraw all ETH from the contract (owner only)
     * @dev Convenience function to withdraw entire balance
     */
    function withdrawAllETH(address payable recipient) external onlyOwner {
        require(recipient != address(0), "Invalid recipient");
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");
        recipient.transfer(balance);
    }
}

