// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/IModuleInspector.sol";
import "../interfaces/IERC165.sol";
import "../libraries/LibGrid.sol";

/**
 * @title ModuleInspector
 * @dev Introspection for Grid modules
 */
contract ModuleInspector is IModuleInspector, IERC165 {
    
    function modules() external view override returns (Module[] memory modules_) {
        LibGrid.GridCoreStorage storage gs = LibGrid.gridStorage();
        uint256 selectorCount = gs.selectorCount;
        modules_ = new Module[](selectorCount);
        uint16[] memory numModuleSelectors = new uint16[](selectorCount);
        uint256 numModules;
        
        for (uint256 i; i < selectorCount; i++) {
            uint256 slotIndex = i >> 3;
            uint256 slotPosition = (i & 7) << 5;
            bytes4 selector = bytes4(gs.selectorSlots[slotIndex] << slotPosition);
            address moduleAddress_ = address(bytes20(gs.modules[selector]));
            bool exists;
            for (uint256 j; j < numModules; j++) {
                if (modules_[j].moduleAddress == moduleAddress_) {
                    exists = true;
                    numModuleSelectors[j]++;
                    break;
                }
            }
            if (!exists) {
                modules_[numModules].moduleAddress = moduleAddress_;
                numModuleSelectors[numModules] = 1;
                numModules++;
            }
        }
        
        // Resize and populate selectors
        Module[] memory trimmedModules = new Module[](numModules);
        for (uint256 i; i < numModules; i++) {
            trimmedModules[i].moduleAddress = modules_[i].moduleAddress;
            trimmedModules[i].functionSelectors = new bytes4[](numModuleSelectors[i]);
        }
        
        uint16[] memory selectorIndices = new uint16[](numModules);
        for (uint256 i; i < selectorCount; i++) {
            uint256 slotIndex = i >> 3;
            uint256 slotPosition = (i & 7) << 5;
            bytes4 selector = bytes4(gs.selectorSlots[slotIndex] << slotPosition);
            address moduleAddress_ = address(bytes20(gs.modules[selector]));
            for (uint256 j; j < numModules; j++) {
                if (trimmedModules[j].moduleAddress == moduleAddress_) {
                    trimmedModules[j].functionSelectors[selectorIndices[j]] = selector;
                    selectorIndices[j]++;
                    break;
                }
            }
        }
        
        return trimmedModules;
    }

    function moduleFunctionSelectors(address _module) external view override returns (bytes4[] memory selectors_) {
        LibGrid.GridCoreStorage storage gs = LibGrid.gridStorage();
        uint256 selectorCount = gs.selectorCount;
        uint256 numSelectors;
        selectors_ = new bytes4[](selectorCount);
        
        for (uint256 i; i < selectorCount; i++) {
            uint256 slotIndex = i >> 3;
            uint256 slotPosition = (i & 7) << 5;
            bytes4 selector = bytes4(gs.selectorSlots[slotIndex] << slotPosition);
            address moduleAddress_ = address(bytes20(gs.modules[selector]));
            if (moduleAddress_ == _module) {
                selectors_[numSelectors] = selector;
                numSelectors++;
            }
        }
        
        bytes4[] memory trimmedSelectors = new bytes4[](numSelectors);
        for (uint256 i; i < numSelectors; i++) {
            trimmedSelectors[i] = selectors_[i];
        }
        return trimmedSelectors;
    }

    function moduleAddresses() external view override returns (address[] memory addresses_) {
        LibGrid.GridCoreStorage storage gs = LibGrid.gridStorage();
        uint256 selectorCount = gs.selectorCount;
        addresses_ = new address[](selectorCount);
        uint256 numModules;
        
        for (uint256 i; i < selectorCount; i++) {
            uint256 slotIndex = i >> 3;
            uint256 slotPosition = (i & 7) << 5;
            bytes4 selector = bytes4(gs.selectorSlots[slotIndex] << slotPosition);
            address moduleAddress_ = address(bytes20(gs.modules[selector]));
            bool exists;
            for (uint256 j; j < numModules; j++) {
                if (addresses_[j] == moduleAddress_) {
                    exists = true;
                    break;
                }
            }
            if (!exists) {
                addresses_[numModules] = moduleAddress_;
                numModules++;
            }
        }
        
        address[] memory trimmedAddresses = new address[](numModules);
        for (uint256 i; i < numModules; i++) {
            trimmedAddresses[i] = addresses_[i];
        }
        return trimmedAddresses;
    }

    function moduleAddress(bytes4 _functionSelector) external view override returns (address moduleAddress_) {
        LibGrid.GridCoreStorage storage gs = LibGrid.gridStorage();
        moduleAddress_ = address(bytes20(gs.modules[_functionSelector]));
    }

    function supportsInterface(bytes4 _interfaceId) external view override returns (bool) {
        LibGrid.GridCoreStorage storage gs = LibGrid.gridStorage();
        return gs.supportedInterfaces[_interfaceId];
    }
}
