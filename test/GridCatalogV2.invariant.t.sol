// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {GridCatalogV2} from "../contracts/GridCatalogV2.sol";

contract GridCatalogV2Handler {
    GridCatalogV2 public immutable catalog;

    bytes32[] public modelIds;
    bytes32[] public modelSlugs;
    bytes32[] public modelVersions;
    bytes32[] public recipeIds;
    bytes32[] public recipeSlugs;
    bytes32[] public recipeVersions;

    uint256 private _modelNonce;
    uint256 private _recipeNonce;

    constructor(GridCatalogV2 catalog_) {
        catalog = catalog_;
    }

    function registerModel(uint256 seed) external {
        if (catalog.paused()) return;
        uint256 nonce = _modelNonce++;
        bytes32 modelId = keccak256(abi.encode("model", nonce, seed));
        bytes32 slug = keccak256(abi.encode("model-slug", nonce));
        bytes32 versionHash = keccak256(abi.encode("model-version", nonce));
        uint32 modality = uint32(1 << (seed % 5));
        catalog.registerModel(
            GridCatalogV2.ModelInput({
                manifestHash: modelId,
                artifactRoot: keccak256(abi.encode("artifacts", nonce, seed)),
                slug: slug,
                versionHash: versionHash,
                modalityMask: modality,
                minVramMiB: uint32(seed),
                publisher: address(this),
                manifestURI: "ipfs://invariant-model"
            })
        );
        modelIds.push(modelId);
        modelSlugs.push(slug);
        modelVersions.push(versionHash);
    }

    function toggleModel(uint256 index) external {
        if (modelIds.length == 0) return;
        bytes32 modelId = modelIds[index % modelIds.length];
        bool active = catalog.isModelActive(modelId);
        if (!active && catalog.paused()) return;
        catalog.setModelActive(modelId, !active);
    }

    function registerRecipe(uint256 seed) external {
        if (catalog.paused()) return;
        (bool found, bytes32 modelId) = _firstActiveModel();
        if (!found) return;

        uint256 nonce = _recipeNonce++;
        bytes32 recipeId = keccak256(abi.encode("recipe", nonce, seed));
        bytes32 slug = keccak256(abi.encode("recipe-slug", nonce));
        bytes32 versionHash = keccak256(abi.encode("recipe-version", nonce));
        bytes32[] memory requirements = new bytes32[](1);
        requirements[0] = modelId;
        catalog.registerRecipe(
            GridCatalogV2.RecipeInput({
                contentHash: recipeId,
                slug: slug,
                versionHash: versionHash,
                outputModality: uint32(1 << (seed % 5)),
                publisher: address(this),
                contentURI: "ipfs://invariant-recipe",
                requiredModelIds: requirements
            })
        );
        recipeIds.push(recipeId);
        recipeSlugs.push(slug);
        recipeVersions.push(versionHash);
    }

    function toggleRecipe(uint256 index) external {
        if (recipeIds.length == 0) return;
        bytes32 recipeId = recipeIds[index % recipeIds.length];
        bool active = catalog.getRecipe(recipeId).active;
        if (!active && catalog.paused()) return;
        catalog.setRecipeActive(recipeId, !active);
    }

    function toggleNftPermission(uint256 index) external {
        if (recipeIds.length == 0) return;
        bytes32 recipeId = recipeIds[index % recipeIds.length];
        bool allowed = catalog.getRecipe(recipeId).canCreateNfts;
        if (!allowed && catalog.paused()) return;
        catalog.setRecipeNftPermission(recipeId, !allowed);
    }

    function togglePause() external {
        if (catalog.paused()) {
            catalog.unpause();
        } else {
            catalog.pause();
        }
    }

    function modelCount() external view returns (uint256) {
        return modelIds.length;
    }

    function recipeCount() external view returns (uint256) {
        return recipeIds.length;
    }

    function _firstActiveModel() private view returns (bool found, bytes32 modelId) {
        uint256 count = modelIds.length;
        for (uint256 i = 0; i < count;) {
            modelId = modelIds[i];
            if (catalog.isModelActive(modelId)) return (true, modelId);
            unchecked {
                ++i;
            }
        }
    }
}

contract GridCatalogV2InvariantTest is StdInvariant, Test {
    GridCatalogV2 internal catalog;
    GridCatalogV2Handler internal handler;

    function setUp() public {
        catalog = new GridCatalogV2(address(this), address(this), address(this), address(this));
        handler = new GridCatalogV2Handler(catalog);

        catalog.grantRole(catalog.REGISTRAR_ROLE(), address(handler));
        catalog.grantRole(catalog.PAUSER_ROLE(), address(handler));
        catalog.grantRole(catalog.NFT_APPROVER_ROLE(), address(handler));
        catalog.revokeRole(catalog.REGISTRAR_ROLE(), address(this));
        catalog.revokeRole(catalog.PAUSER_ROLE(), address(this));
        catalog.revokeRole(catalog.NFT_APPROVER_ROLE(), address(this));

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = handler.registerModel.selector;
        selectors[1] = handler.toggleModel.selector;
        selectors[2] = handler.registerRecipe.selector;
        selectors[3] = handler.toggleRecipe.selector;
        selectors[4] = handler.toggleNftPermission.selector;
        selectors[5] = handler.togglePause.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        excludeContract(address(catalog));
    }

    function invariant_modelInventoryIsUniqueAndInternallyConsistent() public view {
        uint256 count = catalog.modelCount();
        assertEq(count, handler.modelCount());

        for (uint256 i = 0; i < count; ++i) {
            bytes32 modelId = handler.modelIds(i);
            GridCatalogV2.ModelRecord memory model = catalog.getModel(modelId);
            assertEq(model.manifestHash, modelId);
            assertEq(
                catalog.getModelIdByRelease(handler.modelSlugs(i), handler.modelVersions(i)),
                modelId
            );
            assertTrue(model.modalityMask != 0);
            assertEq(model.modalityMask & ~catalog.KNOWN_MODALITIES(), 0);

            for (uint256 j = i + 1; j < count; ++j) {
                assertTrue(modelId != handler.modelIds(j));
            }
        }

        _assertModelPagination(count);
    }

    function invariant_recipeStateAndNftEligibilityStayDerived() public view {
        uint256 count = catalog.recipeCount();
        assertEq(count, handler.recipeCount());

        for (uint256 i = 0; i < count; ++i) {
            bytes32 recipeId = handler.recipeIds(i);
            GridCatalogV2.RecipeRecord memory recipe = catalog.getRecipe(recipeId);
            bytes32[] memory requirements = catalog.getRecipeRequirements(recipeId);
            assertEq(recipe.contentHash, recipeId);
            assertEq(
                catalog.getRecipeIdByRelease(handler.recipeSlugs(i), handler.recipeVersions(i)),
                recipeId
            );
            assertTrue(requirements.length > 0);
            assertEq(recipe.requirementsHash, keccak256(abi.encode(requirements)));

            bool expectedExecutable = recipe.active;
            for (uint256 j = 0; j < requirements.length; ++j) {
                if (j != 0) {
                    assertTrue(uint256(requirements[j - 1]) < uint256(requirements[j]));
                }
                GridCatalogV2.ModelRecord memory model = catalog.getModel(requirements[j]);
                if (!model.active) expectedExecutable = false;
            }
            assertEq(catalog.isRecipeExecutable(recipeId), expectedExecutable);
            assertEq(
                catalog.isRecipeNftEligible(recipeId), recipe.canCreateNfts && expectedExecutable
            );
        }

        _assertRecipePagination(count);
    }

    function invariant_onlyConfiguredActorsHoldOperationalRoles() public view {
        assertTrue(catalog.hasRole(catalog.DEFAULT_ADMIN_ROLE(), address(this)));
        assertTrue(catalog.hasRole(catalog.REGISTRAR_ROLE(), address(handler)));
        assertTrue(catalog.hasRole(catalog.PAUSER_ROLE(), address(handler)));
        assertTrue(catalog.hasRole(catalog.NFT_APPROVER_ROLE(), address(handler)));
        assertFalse(catalog.hasRole(catalog.REGISTRAR_ROLE(), address(this)));
    }

    function _assertModelPagination(uint256 count) private view {
        uint256 offset;
        while (offset < count) {
            uint256 pageSize = count - offset;
            if (pageSize > catalog.MAX_PAGE_SIZE()) pageSize = catalog.MAX_PAGE_SIZE();
            bytes32[] memory page = catalog.listModelIds(offset, pageSize);
            for (uint256 i = 0; i < page.length; ++i) {
                assertEq(page[i], handler.modelIds(offset + i));
            }
            offset += page.length;
        }
    }

    function _assertRecipePagination(uint256 count) private view {
        uint256 offset;
        while (offset < count) {
            uint256 pageSize = count - offset;
            if (pageSize > catalog.MAX_PAGE_SIZE()) pageSize = catalog.MAX_PAGE_SIZE();
            bytes32[] memory page = catalog.listRecipeIds(offset, pageSize);
            for (uint256 i = 0; i < page.length; ++i) {
                assertEq(page[i], handler.recipeIds(offset + i));
            }
            offset += page.length;
        }
    }
}
