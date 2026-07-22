// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {GridCatalogV2} from "../contracts/GridCatalogV2.sol";

contract GridCatalogV2Test is Test {
    GridCatalogV2 internal catalog;

    address internal admin = address(0xA11CE);
    address internal registrar = address(0xB0B);
    address internal pauser = address(0xCAFE);
    address internal nftApprover = address(0xD00D);
    address internal publisher = address(0xF00D);
    address internal stranger = address(0xBAD);

    bytes32 internal constant MODEL_HASH = keccak256("model-manifest-v1");
    bytes32 internal constant ARTIFACT_ROOT = keccak256("model-artifacts-v1");
    bytes32 internal constant MODEL_SLUG = keccak256("ltx-2.3");
    bytes32 internal constant MODEL_VERSION = keccak256("2.3.0");
    bytes32 internal constant RECIPE_HASH = keccak256("director-recipe-v1");
    bytes32 internal constant RECIPE_SLUG = keccak256("ltx-director");
    bytes32 internal constant RECIPE_VERSION = keccak256("2.0.0");
    uint32 internal constant VIDEO = 1 << 2;
    uint32 internal constant AUDIO = 1 << 3;

    function setUp() public {
        catalog = new GridCatalogV2(admin, registrar, pauser, nftApprover);
    }

    function _modelInput(bytes32 manifestHash, bytes32 slug, bytes32 versionHash)
        internal
        view
        returns (GridCatalogV2.ModelInput memory)
    {
        return GridCatalogV2.ModelInput({
            manifestHash: manifestHash,
            artifactRoot: ARTIFACT_ROOT,
            slug: slug,
            versionHash: versionHash,
            modalityMask: VIDEO | AUDIO,
            minVramMiB: 24_576,
            publisher: publisher,
            manifestURI: "ipfs://model-manifest"
        });
    }

    function _registerModel() internal returns (bytes32) {
        vm.prank(registrar);
        return catalog.registerModel(_modelInput(MODEL_HASH, MODEL_SLUG, MODEL_VERSION));
    }

    function _recipeInput(bytes32 contentHash, bytes32[] memory requirements)
        internal
        view
        returns (GridCatalogV2.RecipeInput memory)
    {
        return GridCatalogV2.RecipeInput({
            contentHash: contentHash,
            slug: RECIPE_SLUG,
            versionHash: RECIPE_VERSION,
            outputModality: VIDEO,
            publisher: publisher,
            contentURI: "ipfs://director-recipe",
            requiredModelIds: requirements
        });
    }

    function _registerRecipe() internal returns (bytes32) {
        _registerModel();
        bytes32[] memory requirements = new bytes32[](1);
        requirements[0] = MODEL_HASH;
        vm.prank(registrar);
        return catalog.registerRecipe(_recipeInput(RECIPE_HASH, requirements));
    }

    function test_constructor_assignsLeastPrivilegeRoles() public view {
        assertTrue(catalog.hasRole(catalog.DEFAULT_ADMIN_ROLE(), admin));
        assertEq(catalog.defaultAdmin(), admin);
        assertEq(catalog.defaultAdminDelay(), 2 days);
        assertTrue(catalog.hasRole(catalog.REGISTRAR_ROLE(), registrar));
        assertTrue(catalog.hasRole(catalog.PAUSER_ROLE(), pauser));
        assertTrue(catalog.hasRole(catalog.NFT_APPROVER_ROLE(), nftApprover));
        assertFalse(catalog.hasRole(catalog.REGISTRAR_ROLE(), admin));
    }

    function test_defaultAdminTransfer_isDelayedAndTwoStep() public {
        vm.prank(admin);
        catalog.beginDefaultAdminTransfer(stranger);

        vm.prank(stranger);
        vm.expectRevert();
        catalog.acceptDefaultAdminTransfer();

        vm.warp(block.timestamp + catalog.DEFAULT_ADMIN_TRANSFER_DELAY() + 1);
        vm.prank(stranger);
        catalog.acceptDefaultAdminTransfer();

        assertEq(catalog.defaultAdmin(), stranger);
        assertFalse(catalog.hasRole(catalog.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(catalog.hasRole(catalog.DEFAULT_ADMIN_ROLE(), stranger));
    }

    function test_constructor_rejectsZeroRoleAddress() public {
        vm.expectRevert(GridCatalogV2.ZeroAddress.selector);
        new GridCatalogV2(admin, address(0), pauser, nftApprover);
    }

    function test_registerModel_recordsImmutableManifest() public {
        bytes32 modelId = _registerModel();

        GridCatalogV2.ModelRecord memory model = catalog.getModel(modelId);
        assertEq(modelId, MODEL_HASH);
        assertEq(model.manifestHash, MODEL_HASH);
        assertEq(model.artifactRoot, ARTIFACT_ROOT);
        assertEq(model.slug, MODEL_SLUG);
        assertEq(model.versionHash, MODEL_VERSION);
        assertEq(model.modalityMask, catalog.MODALITY_VIDEO() | catalog.MODALITY_AUDIO());
        assertEq(model.minVramMiB, 24_576);
        assertEq(model.publisher, publisher);
        assertTrue(model.active);
        assertEq(model.manifestURI, "ipfs://model-manifest");
        assertEq(catalog.modelCount(), 1);
        assertEq(catalog.getModelIdByRelease(MODEL_SLUG, MODEL_VERSION), MODEL_HASH);
    }

    function test_registerModel_requiresRegistrar() public {
        vm.prank(stranger);
        vm.expectRevert();
        catalog.registerModel(_modelInput(MODEL_HASH, MODEL_SLUG, MODEL_VERSION));
    }

    function test_registerModel_rejectsDuplicateManifest() public {
        _registerModel();
        vm.prank(registrar);
        vm.expectRevert(GridCatalogV2.RecordExists.selector);
        catalog.registerModel(_modelInput(MODEL_HASH, keccak256("other"), MODEL_VERSION));
    }

    function test_registerModel_rejectsDuplicateRelease() public {
        _registerModel();
        vm.prank(registrar);
        vm.expectRevert(GridCatalogV2.ReleaseExists.selector);
        catalog.registerModel(_modelInput(keccak256("different"), MODEL_SLUG, MODEL_VERSION));
    }

    function test_registerModel_rejectsEmptyAndOversizedMetadata() public {
        GridCatalogV2.ModelInput memory input = _modelInput(MODEL_HASH, MODEL_SLUG, MODEL_VERSION);
        input.modalityMask = 0;
        vm.prank(registrar);
        vm.expectRevert(GridCatalogV2.InvalidModality.selector);
        catalog.registerModel(input);

        input.modalityMask = uint32(1 << 31);
        vm.prank(registrar);
        vm.expectRevert(GridCatalogV2.InvalidModality.selector);
        catalog.registerModel(input);

        input.modalityMask = catalog.MODALITY_VIDEO();
        input.manifestURI = string(new bytes(catalog.MAX_URI_BYTES() + 1));
        vm.prank(registrar);
        vm.expectRevert(GridCatalogV2.URITooLong.selector);
        catalog.registerModel(input);
    }

    function test_modelDeactivation_isExplicitAndRoleGated() public {
        _registerModel();

        vm.prank(stranger);
        vm.expectRevert();
        catalog.setModelActive(MODEL_HASH, false);

        vm.prank(registrar);
        catalog.setModelActive(MODEL_HASH, false);
        assertFalse(catalog.isModelActive(MODEL_HASH));

        vm.prank(registrar);
        vm.expectRevert(GridCatalogV2.StateUnchanged.selector);
        catalog.setModelActive(MODEL_HASH, false);
    }

    function test_registerRecipe_linksVerifiedModelDependencies() public {
        bytes32 recipeId = _registerRecipe();

        GridCatalogV2.RecipeRecord memory recipe = catalog.getRecipe(recipeId);
        assertEq(recipeId, RECIPE_HASH);
        assertEq(recipe.requirementsHash, keccak256(abi.encode(_single(MODEL_HASH))));
        assertEq(recipe.outputModality, catalog.MODALITY_VIDEO());
        assertTrue(recipe.active);
        assertFalse(recipe.canCreateNfts);
        assertTrue(catalog.isRecipeExecutable(recipeId));
        assertEq(catalog.recipeCount(), 1);
        assertEq(catalog.getRecipeIdByRelease(RECIPE_SLUG, RECIPE_VERSION), RECIPE_HASH);

        bytes32[] memory requirements = catalog.getRecipeRequirements(recipeId);
        assertEq(requirements.length, 1);
        assertEq(requirements[0], MODEL_HASH);
    }

    function test_registerRecipe_rejectsMissingInactiveAndNoncanonicalRequirements() public {
        bytes32[] memory missing = _single(MODEL_HASH);
        vm.prank(registrar);
        vm.expectRevert(GridCatalogV2.InactiveRequiredModel.selector);
        catalog.registerRecipe(_recipeInput(RECIPE_HASH, missing));

        _registerModel();
        vm.prank(registrar);
        catalog.setModelActive(MODEL_HASH, false);
        vm.prank(registrar);
        vm.expectRevert(GridCatalogV2.InactiveRequiredModel.selector);
        catalog.registerRecipe(_recipeInput(RECIPE_HASH, missing));

        vm.prank(registrar);
        catalog.setModelActive(MODEL_HASH, true);
        bytes32[] memory duplicate = new bytes32[](2);
        duplicate[0] = MODEL_HASH;
        duplicate[1] = MODEL_HASH;
        vm.prank(registrar);
        vm.expectRevert(GridCatalogV2.RequirementsNotSorted.selector);
        catalog.registerRecipe(_recipeInput(RECIPE_HASH, duplicate));
    }

    function test_registerRecipe_requiresStrictlySortedModelIds() public {
        bytes32 first = bytes32(uint256(1));
        bytes32 second = bytes32(uint256(2));
        vm.startPrank(registrar);
        catalog.registerModel(_modelInput(first, keccak256("first"), MODEL_VERSION));
        catalog.registerModel(_modelInput(second, keccak256("second"), MODEL_VERSION));
        vm.stopPrank();

        bytes32[] memory unsorted = new bytes32[](2);
        unsorted[0] = second;
        unsorted[1] = first;
        vm.prank(registrar);
        vm.expectRevert(GridCatalogV2.RequirementsNotSorted.selector);
        catalog.registerRecipe(_recipeInput(RECIPE_HASH, unsorted));
    }

    function test_registerRecipe_rejectsUnknownOutputModality() public {
        _registerModel();
        GridCatalogV2.RecipeInput memory input = _recipeInput(RECIPE_HASH, _single(MODEL_HASH));
        input.outputModality = uint32(1 << 31);

        vm.prank(registrar);
        vm.expectRevert(GridCatalogV2.InvalidModality.selector);
        catalog.registerRecipe(input);
    }

    function test_recipeExecutionTracksModelAndRecipeStatus() public {
        _registerRecipe();

        vm.prank(registrar);
        catalog.setModelActive(MODEL_HASH, false);
        assertFalse(catalog.isRecipeExecutable(RECIPE_HASH));

        vm.prank(registrar);
        catalog.setModelActive(MODEL_HASH, true);
        assertTrue(catalog.isRecipeExecutable(RECIPE_HASH));

        vm.prank(registrar);
        catalog.setRecipeActive(RECIPE_HASH, false);
        assertFalse(catalog.isRecipeExecutable(RECIPE_HASH));
    }

    function test_nftPermission_requiresSeparateApproverRole() public {
        _registerRecipe();

        vm.prank(registrar);
        vm.expectRevert();
        catalog.setRecipeNftPermission(RECIPE_HASH, true);

        vm.prank(nftApprover);
        catalog.setRecipeNftPermission(RECIPE_HASH, true);
        assertTrue(catalog.getRecipe(RECIPE_HASH).canCreateNfts);
        assertTrue(catalog.isRecipeNftEligible(RECIPE_HASH));

        vm.prank(registrar);
        catalog.setModelActive(MODEL_HASH, false);
        assertFalse(catalog.isRecipeNftEligible(RECIPE_HASH));
    }

    function test_pause_blocksNewWritesButAllowsEmergencyDeactivation() public {
        _registerModel();
        vm.prank(pauser);
        catalog.pause();

        GridCatalogV2.ModelInput memory newModel =
            _modelInput(keccak256("new"), keccak256("new-slug"), MODEL_VERSION);
        vm.prank(registrar);
        vm.expectRevert("Pausable: paused");
        catalog.registerModel(newModel);

        vm.prank(registrar);
        catalog.setModelActive(MODEL_HASH, false);
        assertFalse(catalog.getModel(MODEL_HASH).active);

        vm.prank(registrar);
        vm.expectRevert("Pausable: paused");
        catalog.setModelActive(MODEL_HASH, true);
        vm.prank(pauser);
        catalog.unpause();
    }

    function test_pagination_isBoundedAndStable() public {
        for (uint256 i = 0; i < 3; ++i) {
            bytes32 hash = keccak256(abi.encode("model", i));
            bytes32 slug = keccak256(abi.encode("slug", i));
            vm.prank(registrar);
            catalog.registerModel(_modelInput(hash, slug, MODEL_VERSION));
        }

        bytes32[] memory page = catalog.listModelIds(1, 2);
        assertEq(page.length, 2);
        assertEq(page[0], keccak256(abi.encode("model", uint256(1))));
        assertEq(page[1], keccak256(abi.encode("model", uint256(2))));
        assertEq(catalog.listModelIds(3, 10).length, 0);

        vm.expectRevert(GridCatalogV2.InvalidPageSize.selector);
        catalog.listModelIds(0, 0);
        vm.expectRevert(GridCatalogV2.InvalidPageSize.selector);
        catalog.listModelIds(0, 101);
    }

    function test_gettersRejectUnknownRecords() public {
        vm.expectRevert(GridCatalogV2.RecordNotFound.selector);
        catalog.getModel(bytes32(uint256(1)));
        vm.expectRevert(GridCatalogV2.RecordNotFound.selector);
        catalog.getRecipeRequirements(bytes32(uint256(1)));
        assertFalse(catalog.isRecipeExecutable(bytes32(uint256(1))));
    }

    function _single(bytes32 value) private pure returns (bytes32[] memory result) {
        result = new bytes32[](1);
        result[0] = value;
    }
}
