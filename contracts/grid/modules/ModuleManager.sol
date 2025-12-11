// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/IModuleManager.sol";
import "../libraries/LibGrid.sol";

/**
 * @title ModuleManager
 * @dev Handles adding/replacing/removing modules
 */
contract ModuleManager is IModuleManager {
    
    function updateModules(
        ModuleCut[] calldata _moduleCut,
        address _init,
        bytes calldata _calldata
    ) external override {
        LibGrid.enforceIsOwner();
        LibGrid.updateModules(_moduleCut, _init, _calldata);
    }
}
