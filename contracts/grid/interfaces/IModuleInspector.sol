// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IModuleInspector
 * @dev Interface for inspecting modules (EIP-2535 DiamondLoupe)
 */
interface IModuleInspector {
    struct Module {
        address moduleAddress;
        bytes4[] functionSelectors;
    }

    /// @notice Gets all modules and their selectors
    function modules() external view returns (Module[] memory modules_);

    /// @notice Gets all function selectors for a module
    function moduleFunctionSelectors(address _module) external view returns (bytes4[] memory selectors_);

    /// @notice Gets all module addresses
    function moduleAddresses() external view returns (address[] memory addresses_);

    /// @notice Gets the module address for a function selector
    function moduleAddress(bytes4 _functionSelector) external view returns (address moduleAddress_);
}
