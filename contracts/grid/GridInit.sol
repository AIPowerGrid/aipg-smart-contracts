// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./libraries/GridStorage.sol";

/**
 * @title GridInit
 * @dev Initialization contract for Grid deployment
 */
contract GridInit {
    
    function init(
        address aipgToken,
        address stakingVault,
        address admin
    ) external {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        
        // Set addresses
        s.aipgToken = aipgToken;
        s.stakingVault = stakingVault;
        
        // Setup roles
        s.roles[GridStorage.DEFAULT_ADMIN_ROLE][admin] = true;
        s.roles[GridStorage.ADMIN_ROLE][admin] = true;
        s.roles[GridStorage.REGISTRAR_ROLE][admin] = true;
        s.roles[GridStorage.ANCHOR_ROLE][admin] = true;
        s.roles[GridStorage.PAUSER_ROLE][admin] = true;
        
        // Set defaults
        s.minBondAmount = 1000 * 10**18; // 1000 AIPG default
        s.maxWorkflowBytes = 100 * 1024; // 100KB default
    }
}

