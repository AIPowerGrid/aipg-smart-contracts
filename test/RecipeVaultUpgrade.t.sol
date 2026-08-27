// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "../contracts/grid/Grid.sol";
import "../contracts/grid/interfaces/IModuleManager.sol";
import "../contracts/grid/libraries/GridStorage.sol";
import "../contracts/grid/modules/ModuleInspector.sol";
import "../contracts/grid/modules/ModuleManager.sol";
import "../contracts/grid/modules/Ownership.sol";
import "../contracts/grid/modules/RecipeVault.sol";

/// @dev Reproduces the ten-selector permissionless RecipeVault currently routed
/// on Base. The test deliberately stores a compressed record with an arbitrary
/// root before upgrading so legacy provenance remains readable without being
/// mistaken for a newly governed record.
contract LegacyRecipeVault {
    modifier onlyAdmin() {
        require(
            GridStorage.appStorage().roles[GridStorage.ADMIN_ROLE][msg.sender], "legacy: not admin"
        );
        _;
    }

    modifier notPaused() {
        require(!GridStorage.appStorage().paused, "legacy: paused");
        _;
    }

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
        require(recipeRoot != bytes32(0), "legacy: empty root");
        require(workflowData.length > 0, "legacy: empty workflow");
        require(s.recipeRootToId[recipeRoot] == 0, "legacy: exists");
        s.nextRecipeId++;
        recipeId = s.nextRecipeId;
        s.totalRecipes++;
        GridStorage.Recipe storage recipe = s.recipes[recipeId];
        recipe.recipeId = recipeId;
        recipe.recipeRoot = recipeRoot;
        recipe.workflowData = workflowData;
        recipe.creator = msg.sender;
        recipe.canCreateNFTs = canCreateNFTs;
        recipe.isPublic = isPublic;
        recipe.compression = compression;
        recipe.createdAt = block.timestamp;
        recipe.name = name;
        recipe.description = description;
        s.recipeRootToId[recipeRoot] = recipeId;
        s.creatorRecipes[msg.sender].push(recipeId);
    }

    function updateRecipePermissions(uint256 recipeId, bool canCreateNFTs, bool isPublic)
        external
        notPaused
    {
        GridStorage.Recipe storage recipe = GridStorage.appStorage().recipes[recipeId];
        require(recipe.recipeRoot != bytes32(0), "legacy: not found");
        require(recipe.creator == msg.sender, "legacy: not creator");
        recipe.canCreateNFTs = canCreateNFTs;
        recipe.isPublic = isPublic;
    }

    function setMaxWorkflowBytes(uint256 maxBytes) external onlyAdmin {
        GridStorage.appStorage().maxWorkflowBytes = maxBytes;
    }

    function getRecipe(uint256 recipeId) external view returns (GridStorage.Recipe memory) {
        return GridStorage.appStorage().recipes[recipeId];
    }

    function getRecipeByRoot(bytes32 recipeRoot) external view returns (GridStorage.Recipe memory) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        return s.recipes[s.recipeRootToId[recipeRoot]];
    }

    function getCreatorRecipes(address creator) external view returns (uint256[] memory) {
        return GridStorage.appStorage().creatorRecipes[creator];
    }

    function getTotalRecipes() external view returns (uint256) {
        return GridStorage.appStorage().totalRecipes;
    }

    function getMaxWorkflowBytes() external view returns (uint256) {
        return GridStorage.appStorage().maxWorkflowBytes;
    }

    function isRecipePublic(uint256 recipeId) external view returns (bool) {
        return GridStorage.appStorage().recipes[recipeId].isPublic;
    }

    function canRecipeCreateNFTs(uint256 recipeId) external view returns (bool) {
        return GridStorage.appStorage().recipes[recipeId].canCreateNFTs;
    }
}

contract RecipeVaultUpgradeTest is Test {
    address private admin = makeAddr("admin");
    address private legacyCreator = makeAddr("legacy-creator");
    address private registrar = makeAddr("registrar");
    address payable private grid;
    LegacyRecipeVault private legacy;

    function setUp() public {
        ModuleManager manager = new ModuleManager();
        ModuleInspector inspector = new ModuleInspector();
        Ownership ownership = new Ownership();
        legacy = new LegacyRecipeVault();

        IModuleManager.ModuleCut[] memory initialCut = new IModuleManager.ModuleCut[](4);
        initialCut[0] = _cut(address(manager), _one(IModuleManager.updateModules.selector));
        initialCut[1] = _cut(address(inspector), _inspectorSelectors());
        initialCut[2] = _cut(address(ownership), _ownershipSelectors());
        initialCut[3] = _cut(address(legacy), _recipeSelectors());
        Grid.GridArgs memory args =
            Grid.GridArgs({owner: admin, aipgToken: address(0), stakingVault: address(0)});
        grid = payable(address(new Grid(initialCut, args)));
        _grantRole(GridStorage.ADMIN_ROLE, admin);
        _grantRole(GridStorage.REGISTRAR_ROLE, registrar);

        vm.prank(legacyCreator);
        LegacyRecipeVault(grid)
            .storeRecipe(
                bytes32(uint256(0x1234)),
                hex"1f8b0800",
                true,
                true,
                1,
                "legacy compressed",
                "arbitrary historical root"
            );
    }

    function test_upgradePreservesLegacyRecordsAndMovesEverySelector() public {
        GridStorage.Recipe memory beforeRecord = LegacyRecipeVault(grid).getRecipe(1);
        assertEq(beforeRecord.creator, legacyCreator);
        assertEq(beforeRecord.compression, 1);
        assertEq(LegacyRecipeVault(grid).getTotalRecipes(), 1);

        RecipeVault candidate = new RecipeVault();
        IModuleManager.ModuleCut[] memory upgrade = new IModuleManager.ModuleCut[](1);
        upgrade[0] = IModuleManager.ModuleCut({
            moduleAddress: address(candidate),
            action: IModuleManager.ModuleAction.Replace,
            functionSelectors: _recipeSelectors()
        });
        vm.prank(admin);
        ModuleManager(grid).updateModules(upgrade, address(0), "");

        assertEq(
            ModuleInspector(grid).moduleFunctionSelectors(address(legacy)).length,
            0,
            "legacy facet retained a selector"
        );
        bytes4[] memory candidateRoutes =
            ModuleInspector(grid).moduleFunctionSelectors(address(candidate));
        assertEq(candidateRoutes.length, 10);
        for (uint256 i; i < candidateRoutes.length; i++) {
            assertEq(ModuleInspector(grid).moduleAddress(candidateRoutes[i]), address(candidate));
        }

        RecipeVault governed = RecipeVault(grid);
        GridStorage.Recipe memory afterRecord = governed.getRecipe(1);
        assertEq(afterRecord.recipeRoot, beforeRecord.recipeRoot);
        assertEq(afterRecord.workflowData, beforeRecord.workflowData);
        assertEq(afterRecord.creator, beforeRecord.creator);
        assertEq(afterRecord.canCreateNFTs, beforeRecord.canCreateNFTs);
        assertEq(afterRecord.isPublic, beforeRecord.isPublic);
        assertEq(afterRecord.compression, beforeRecord.compression);
        assertEq(afterRecord.createdAt, beforeRecord.createdAt);
        assertEq(afterRecord.name, beforeRecord.name);
        assertEq(afterRecord.description, beforeRecord.description);
        assertEq(governed.getTotalRecipes(), 1);

        vm.prank(legacyCreator);
        vm.expectRevert("RecipeVault: not registrar");
        governed.storeRecipe(bytes32(uint256(9)), hex"01", false, true, 0, "untrusted", "must fail");

        bytes memory canonical = bytes('{"_grid":{},"1":{"class_type":"Test"}}');
        bytes32 root = sha256(canonical);
        vm.prank(registrar);
        uint256 newId =
            governed.storeRecipe(root, canonical, false, true, 0, "governed", "content addressed");
        assertEq(newId, 2);
        assertEq(governed.getRecipeByRoot(root).workflowData, canonical);

        vm.prank(admin);
        governed.updateRecipePermissions(1, false, false);
        assertFalse(governed.isRecipePublic(1));
        assertFalse(governed.canRecipeCreateNFTs(1));
    }

    function _grantRole(bytes32 role, address account) private {
        bytes32 base = keccak256("aipg.grid.storage");
        bytes32 inner = keccak256(abi.encode(role, base));
        vm.store(grid, keccak256(abi.encode(account, inner)), bytes32(uint256(1)));
    }

    function _cut(address facet, bytes4[] memory selectors)
        private
        pure
        returns (IModuleManager.ModuleCut memory)
    {
        return IModuleManager.ModuleCut({
            moduleAddress: facet,
            action: IModuleManager.ModuleAction.Add,
            functionSelectors: selectors
        });
    }

    function _one(bytes4 selector) private pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = selector;
    }

    function _inspectorSelectors() private pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = ModuleInspector.modules.selector;
        selectors[1] = ModuleInspector.moduleFunctionSelectors.selector;
        selectors[2] = ModuleInspector.moduleAddresses.selector;
        selectors[3] = ModuleInspector.moduleAddress.selector;
    }

    function _ownershipSelectors() private pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = Ownership.transferOwnership.selector;
        selectors[1] = Ownership.owner.selector;
    }

    function _recipeSelectors() private pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](10);
        selectors[0] = LegacyRecipeVault.canRecipeCreateNFTs.selector;
        selectors[1] = LegacyRecipeVault.getCreatorRecipes.selector;
        selectors[2] = LegacyRecipeVault.getMaxWorkflowBytes.selector;
        selectors[3] = LegacyRecipeVault.getRecipe.selector;
        selectors[4] = LegacyRecipeVault.getRecipeByRoot.selector;
        selectors[5] = LegacyRecipeVault.getTotalRecipes.selector;
        selectors[6] = LegacyRecipeVault.isRecipePublic.selector;
        selectors[7] = LegacyRecipeVault.setMaxWorkflowBytes.selector;
        selectors[8] = LegacyRecipeVault.storeRecipe.selector;
        selectors[9] = LegacyRecipeVault.updateRecipePermissions.selector;
    }
}
