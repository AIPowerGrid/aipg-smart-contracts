// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPerpsMarketModule {
    function openPosition(
        uint128 accountId,
        uint128 marketId,
        int128 sizeDelta,
        uint256 acceptablePrice,
        bytes32 trackingCode
    ) external returns (uint256 commitmentTime);
    
    function closePosition(
        uint128 accountId,
        uint128 marketId,
        uint256 acceptablePrice
    ) external returns (uint256 commitmentTime);
    
    function getPosition(
        uint128 accountId,
        uint128 marketId
    ) external view returns (
        int128 size,
        int128 entryPrice,
        int128 entryFundingRate,
        uint256 collateral
    );
}

interface ICoreProxy {
    function createAccount() external returns (uint128 accountId);
    function deposit(uint128 accountId, address collateralType, uint256 amount) external;
    function withdraw(uint128 accountId, address collateralType, uint256 amount) external;
}

