// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/IERC173.sol";
import "../libraries/LibGrid.sol";

/**
 * @title Ownership
 * @dev Contract ownership management
 */
contract Ownership is IERC173 {
    
    function transferOwnership(address _newOwner) external override {
        LibGrid.enforceIsOwner();
        LibGrid.setOwner(_newOwner);
    }

    function owner() external view override returns (address owner_) {
        owner_ = LibGrid.owner();
    }
}
