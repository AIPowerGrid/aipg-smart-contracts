// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/IModuleManager.sol";

/**
 * @title LibGrid
 * @dev Core routing library for Grid proxy (based on EIP-2535)
 */
library LibGrid {
    bytes32 constant GRID_STORAGE_POSITION = keccak256("aipg.grid.core.storage");

    struct GridCoreStorage {
        // Function selector => module address + position
        mapping(bytes4 => bytes32) modules;
        // Selector slots (8 selectors per slot for gas optimization)
        mapping(uint256 => bytes32) selectorSlots;
        // Total selector count
        uint16 selectorCount;
        // ERC-165 interface support
        mapping(bytes4 => bool) supportedInterfaces;
        // Contract owner
        address owner;
    }

    function gridStorage() internal pure returns (GridCoreStorage storage gs) {
        bytes32 position = GRID_STORAGE_POSITION;
        assembly {
            gs.slot := position
        }
    }

    // ============ EVENTS ============
    
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event ModulesUpdated(IModuleManager.ModuleCut[] _moduleCut, address _init, bytes _calldata);

    // ============ OWNER ============

    function setOwner(address _newOwner) internal {
        GridCoreStorage storage gs = gridStorage();
        address previousOwner = gs.owner;
        gs.owner = _newOwner;
        emit OwnershipTransferred(previousOwner, _newOwner);
    }

    function owner() internal view returns (address) {
        return gridStorage().owner;
    }

    function enforceIsOwner() internal view {
        require(msg.sender == gridStorage().owner, "Grid: not owner");
    }

    // ============ MODULE MANAGEMENT ============

    bytes32 constant CLEAR_ADDRESS_MASK = bytes32(uint256(0xffffffffffffffffffffffff));
    bytes32 constant CLEAR_SELECTOR_MASK = bytes32(uint256(0xffffffff << 224));

    function updateModules(
        IModuleManager.ModuleCut[] memory _moduleCut,
        address _init,
        bytes memory _calldata
    ) internal {
        GridCoreStorage storage gs = gridStorage();
        uint256 originalSelectorCount = gs.selectorCount;
        uint256 selectorCount = originalSelectorCount;
        bytes32 selectorSlot;
        
        if (selectorCount & 7 > 0) {
            selectorSlot = gs.selectorSlots[selectorCount >> 3];
        }
        
        for (uint256 i; i < _moduleCut.length; i++) {
            (selectorCount, selectorSlot) = processModuleCut(
                selectorCount,
                selectorSlot,
                _moduleCut[i].moduleAddress,
                _moduleCut[i].action,
                _moduleCut[i].functionSelectors
            );
        }
        
        if (selectorCount != originalSelectorCount) {
            gs.selectorCount = uint16(selectorCount);
        }
        
        if (selectorCount & 7 > 0) {
            gs.selectorSlots[selectorCount >> 3] = selectorSlot;
        }
        
        emit ModulesUpdated(_moduleCut, _init, _calldata);
        
        initializeModuleCut(_init, _calldata);
    }

    function processModuleCut(
        uint256 _selectorCount,
        bytes32 _selectorSlot,
        address _moduleAddress,
        IModuleManager.ModuleAction _action,
        bytes4[] memory _selectors
    ) internal returns (uint256, bytes32) {
        GridCoreStorage storage gs = gridStorage();
        require(_selectors.length > 0, "Grid: no selectors");
        
        if (_action == IModuleManager.ModuleAction.Add) {
            enforceHasCode(_moduleAddress, "Grid: add module has no code");
            for (uint256 i; i < _selectors.length; i++) {
                bytes4 selector = _selectors[i];
                bytes32 oldModule = gs.modules[selector];
                require(address(bytes20(oldModule)) == address(0), "Grid: function exists");
                gs.modules[selector] = bytes20(_moduleAddress) | bytes32(_selectorCount);
                uint256 selectorInSlotPosition = (_selectorCount & 7) << 5;
                _selectorSlot = (_selectorSlot & ~(CLEAR_SELECTOR_MASK >> selectorInSlotPosition)) | (bytes32(selector) >> selectorInSlotPosition);
                if (selectorInSlotPosition == 224) {
                    gs.selectorSlots[_selectorCount >> 3] = _selectorSlot;
                    _selectorSlot = 0;
                }
                _selectorCount++;
            }
        } else if (_action == IModuleManager.ModuleAction.Replace) {
            enforceHasCode(_moduleAddress, "Grid: replace module has no code");
            for (uint256 i; i < _selectors.length; i++) {
                bytes4 selector = _selectors[i];
                bytes32 oldModule = gs.modules[selector];
                address oldModuleAddress = address(bytes20(oldModule));
                require(oldModuleAddress != address(this), "Grid: can't replace immutable");
                require(oldModuleAddress != _moduleAddress, "Grid: same module");
                require(oldModuleAddress != address(0), "Grid: function doesn't exist");
                gs.modules[selector] = (oldModule & CLEAR_ADDRESS_MASK) | bytes20(_moduleAddress);
            }
        } else if (_action == IModuleManager.ModuleAction.Remove) {
            require(_moduleAddress == address(0), "Grid: remove address must be 0");
            uint256 selectorSlotCount = _selectorCount >> 3;
            uint256 selectorInSlotIndex = _selectorCount & 7;
            for (uint256 i; i < _selectors.length; i++) {
                if (selectorInSlotIndex == 0) {
                    selectorSlotCount--;
                    _selectorSlot = gs.selectorSlots[selectorSlotCount];
                    selectorInSlotIndex = 7;
                } else {
                    selectorInSlotIndex--;
                }
                bytes4 lastSelector;
                uint256 oldSelectorsSlotCount;
                uint256 oldSelectorInSlotPosition;
                {
                    bytes4 selector = _selectors[i];
                    bytes32 oldModule = gs.modules[selector];
                    require(address(bytes20(oldModule)) != address(0), "Grid: function doesn't exist");
                    require(address(bytes20(oldModule)) != address(this), "Grid: can't remove immutable");
                    lastSelector = bytes4(_selectorSlot << (selectorInSlotIndex << 5));
                    if (lastSelector != selector) {
                        gs.modules[lastSelector] = (oldModule & CLEAR_ADDRESS_MASK) | bytes20(gs.modules[lastSelector]);
                    }
                    delete gs.modules[selector];
                    uint256 oldSelectorCount = uint16(uint256(oldModule));
                    oldSelectorsSlotCount = oldSelectorCount >> 3;
                    oldSelectorInSlotPosition = (oldSelectorCount & 7) << 5;
                }
                if (oldSelectorsSlotCount != selectorSlotCount) {
                    bytes32 oldSelectorSlot = gs.selectorSlots[oldSelectorsSlotCount];
                    oldSelectorSlot = (oldSelectorSlot & ~(CLEAR_SELECTOR_MASK >> oldSelectorInSlotPosition)) | (bytes32(lastSelector) >> oldSelectorInSlotPosition);
                    gs.selectorSlots[oldSelectorsSlotCount] = oldSelectorSlot;
                } else {
                    _selectorSlot = (_selectorSlot & ~(CLEAR_SELECTOR_MASK >> oldSelectorInSlotPosition)) | (bytes32(lastSelector) >> oldSelectorInSlotPosition);
                }
                if (selectorInSlotIndex == 0) {
                    delete gs.selectorSlots[selectorSlotCount];
                    _selectorSlot = 0;
                }
            }
            _selectorCount = selectorSlotCount * 8 + selectorInSlotIndex;
        } else {
            revert("Grid: invalid action");
        }
        return (_selectorCount, _selectorSlot);
    }

    function initializeModuleCut(address _init, bytes memory _calldata) internal {
        if (_init == address(0)) {
            require(_calldata.length == 0, "Grid: _init is 0 but _calldata not empty");
        } else {
            require(_calldata.length > 0, "Grid: _calldata empty but _init not 0");
            if (_init != address(this)) {
                enforceHasCode(_init, "Grid: _init has no code");
            }
            (bool success, bytes memory error) = _init.delegatecall(_calldata);
            if (!success) {
                if (error.length > 0) {
                    revert(string(error));
                } else {
                    revert("Grid: _init reverted");
                }
            }
        }
    }

    function enforceHasCode(address _contract, string memory _errorMessage) internal view {
        uint256 contractSize;
        assembly {
            contractSize := extcodesize(_contract)
        }
        require(contractSize > 0, _errorMessage);
    }
}
