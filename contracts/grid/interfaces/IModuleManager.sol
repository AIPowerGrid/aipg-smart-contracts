// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IModuleManager
 * @dev Interface for adding/replacing/removing modules (EIP-2535 DiamondCut)
 */
interface IModuleManager {
    enum ModuleAction { Add, Replace, Remove }

    struct ModuleCut {
        address moduleAddress;
        ModuleAction action;
        bytes4[] functionSelectors;
    }

    /**
     * @dev Add/replace/remove modules and their functions
     * @param _moduleCut Array of module updates
     * @param _init Address of contract to execute _calldata
     * @param _calldata Function call data for initialization
     */
    function updateModules(
        ModuleCut[] calldata _moduleCut,
        address _init,
        bytes calldata _calldata
    ) external;

    event ModulesUpdated(ModuleCut[] _moduleCut, address _init, bytes _calldata);
}
