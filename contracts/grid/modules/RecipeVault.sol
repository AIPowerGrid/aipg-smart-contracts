// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../libraries/GridStorage.sol";
import "../libraries/LibGrid.sol";

/**
 * @title RecipeVault
 * @dev On-chain storage for AI generation workflows/recipes
 */
contract RecipeVault {
    using GridStorage for GridStorage.AppStorage;

    // ============ EVENTS ============
    
    event RecipeStored(uint256 indexed recipeId, bytes32 indexed recipeRoot, address creator);
    event RecipePermissionsUpdated(uint256 indexed recipeId, bool canCreateNFTs, bool isPublic);
    event MaxWorkflowBytesUpdated(uint256 oldMax, uint256 newMax);

    // ============ MODIFIERS ============
    
    modifier onlyAdmin() {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        require(s.roles[GridStorage.ADMIN_ROLE][msg.sender], "RecipeVault: not admin");
        _;
    }

    modifier notPaused() {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        require(!s.paused, "RecipeVault: paused");
        _;
    }

    // ============ STORAGE ============
    
    function storeRecipe(
        bytes32 recipeRoot,
        bytes calldata workflowData,
        bool canCreateNFTs,
        bool isPublic,
        uint8 compression,
        string calldata name,
        string calldata description
    ) external notPaused returns (uint256 recipeId) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        
        require(recipeRoot != bytes32(0), "RecipeVault: empty root");
        require(workflowData.length > 0, "RecipeVault: empty workflow");
        require(
            s.maxWorkflowBytes == 0 || workflowData.length <= s.maxWorkflowBytes,
            "RecipeVault: workflow too large"
        );
        require(s.recipeRootToId[recipeRoot] == 0, "RecipeVault: recipe exists");

        s.nextRecipeId++;
        recipeId = s.nextRecipeId;
        s.totalRecipes++;

        GridStorage.Recipe storage r = s.recipes[recipeId];
        r.recipeId = recipeId;
        r.recipeRoot = recipeRoot;
        r.workflowData = workflowData;
        r.creator = msg.sender;
        r.canCreateNFTs = canCreateNFTs;
        r.isPublic = isPublic;
        r.compression = compression;
        r.createdAt = block.timestamp;
        r.name = name;
        r.description = description;

        s.recipeRootToId[recipeRoot] = recipeId;
        s.creatorRecipes[msg.sender].push(recipeId);

        emit RecipeStored(recipeId, recipeRoot, msg.sender);
    }

    function updateRecipePermissions(
        uint256 recipeId,
        bool canCreateNFTs,
        bool isPublic
    ) external notPaused {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        GridStorage.Recipe storage r = s.recipes[recipeId];
        
        require(r.recipeRoot != bytes32(0), "RecipeVault: not found");
        require(r.creator == msg.sender, "RecipeVault: not creator");

        r.canCreateNFTs = canCreateNFTs;
        r.isPublic = isPublic;

        emit RecipePermissionsUpdated(recipeId, canCreateNFTs, isPublic);
    }

    // ============ ADMIN ============
    
    function setMaxWorkflowBytes(uint256 _maxBytes) external onlyAdmin {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        uint256 oldMax = s.maxWorkflowBytes;
        s.maxWorkflowBytes = _maxBytes;
        emit MaxWorkflowBytesUpdated(oldMax, _maxBytes);
    }

    // ============ VIEWS ============
    
    function getRecipe(uint256 recipeId) external view returns (GridStorage.Recipe memory) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        return s.recipes[recipeId];
    }

    function getRecipeByRoot(bytes32 recipeRoot) external view returns (GridStorage.Recipe memory) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        uint256 recipeId = s.recipeRootToId[recipeRoot];
        return s.recipes[recipeId];
    }

    function getCreatorRecipes(address creator) external view returns (uint256[] memory) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        return s.creatorRecipes[creator];
    }

    function getTotalRecipes() external view returns (uint256) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        return s.totalRecipes;
    }

    function getMaxWorkflowBytes() external view returns (uint256) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        return s.maxWorkflowBytes;
    }

    function isRecipePublic(uint256 recipeId) external view returns (bool) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        return s.recipes[recipeId].isPublic;
    }

    function canRecipeCreateNFTs(uint256 recipeId) external view returns (bool) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        return s.recipes[recipeId].canCreateNFTs;
    }
}

