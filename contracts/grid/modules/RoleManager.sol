// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../libraries/GridStorage.sol";
import "../libraries/LibGrid.sol";

/**
 * @title RoleManager
 * @dev Role-based access control management
 */
contract RoleManager {
    
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event Paused(address account);
    event Unpaused(address account);

    modifier onlyAdmin() {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        require(s.roles[GridStorage.ADMIN_ROLE][msg.sender], "RoleManager: not admin");
        _;
    }

    modifier onlyPauser() {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        require(
            s.roles[GridStorage.PAUSER_ROLE][msg.sender] ||
            s.roles[GridStorage.ADMIN_ROLE][msg.sender],
            "RoleManager: not pauser"
        );
        _;
    }

    function grantRole(bytes32 role, address account) external onlyAdmin {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        s.roles[role][account] = true;
        emit RoleGranted(role, account, msg.sender);
    }

    function revokeRole(bytes32 role, address account) external onlyAdmin {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        s.roles[role][account] = false;
        emit RoleRevoked(role, account, msg.sender);
    }

    function hasRole(bytes32 role, address account) external view returns (bool) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        return s.roles[role][account];
    }

    function pause() external onlyPauser {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        s.paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyAdmin {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        s.paused = false;
        emit Unpaused(msg.sender);
    }

    function isPaused() external view returns (bool) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        return s.paused;
    }

    // Role constants for external use
    function ADMIN_ROLE() external pure returns (bytes32) {
        return GridStorage.ADMIN_ROLE;
    }

    function REGISTRAR_ROLE() external pure returns (bytes32) {
        return GridStorage.REGISTRAR_ROLE;
    }

    function ANCHOR_ROLE() external pure returns (bytes32) {
        return GridStorage.ANCHOR_ROLE;
    }

    function PAUSER_ROLE() external pure returns (bytes32) {
        return GridStorage.PAUSER_ROLE;
    }
}

