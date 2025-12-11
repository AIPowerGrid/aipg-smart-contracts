// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./libraries/LibGrid.sol";
import "./interfaces/IModuleManager.sol";
import "./interfaces/IModuleInspector.sol";
import "./interfaces/IERC165.sol";
import "./interfaces/IERC173.sol";

/**
 * @title Grid
 * @dev Main proxy contract for AIPG Grid infrastructure
 *      Uses EIP-2535 pattern for modular, upgradeable architecture
 * 
 * Modules:
 *   - ModelVault: AI model registry
 *   - RecipeVault: Workflow storage
 *   - JobAnchor: Job tracking
 *   - WorkerRegistry: Worker management
 */
contract Grid {
    struct GridArgs {
        address owner;
        address aipgToken;
        address stakingVault;
    }

    constructor(
        IModuleManager.ModuleCut[] memory _moduleCut,
        GridArgs memory _args
    ) payable {
        LibGrid.setOwner(_args.owner);
        LibGrid.updateModules(_moduleCut, address(0), "");

        LibGrid.GridCoreStorage storage gs = LibGrid.gridStorage();
        
        // ERC-165 interface support
        gs.supportedInterfaces[type(IERC165).interfaceId] = true;
        gs.supportedInterfaces[type(IModuleManager).interfaceId] = true;
        gs.supportedInterfaces[type(IModuleInspector).interfaceId] = true;
        gs.supportedInterfaces[type(IERC173).interfaceId] = true;
    }

    /**
     * @dev Fallback function - routes calls to appropriate module
     */
    fallback() external payable {
        LibGrid.GridCoreStorage storage gs;
        bytes32 position = LibGrid.GRID_STORAGE_POSITION;
        assembly {
            gs.slot := position
        }
        
        address module = address(bytes20(gs.modules[msg.sig]));
        require(module != address(0), "Grid: function not found");
        
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), module, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
                case 0 { revert(0, returndatasize()) }
                default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}
}
