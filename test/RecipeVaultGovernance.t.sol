// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./utils/DiamondHarness.sol";

contract RecipeVaultGovernanceTest is DiamondHarness {
    bytes internal canonicalRecipe =
        bytes('{"_grid":{"deterministic":false},"1":{"class_type":"Test"}}');

    function _root(bytes memory data) internal pure returns (bytes32) {
        return sha256(data);
    }

    function _storeAs(address actor, bytes memory data) internal returns (uint256) {
        bytes32 root = _root(data);
        vm.prank(actor);
        return recipeVault.storeRecipe(
            root, data, false, true, 0, "governed-test", "canonical test recipe"
        );
    }

    function test_storeRecipe_requiresRegistrar() public {
        bytes32 root = _root(canonicalRecipe);
        vm.prank(user);
        vm.expectRevert("RecipeVault: not registrar");
        recipeVault.storeRecipe(root, canonicalRecipe, false, true, 0, "untrusted", "must fail");
    }

    function test_storeRecipe_registrarAndAdminCanPublishCanonicalBytes() public {
        uint256 first = _storeAs(registrar, canonicalRecipe);
        bytes memory secondRecipe = bytes('{"_grid":{},"2":{"class_type":"Test"}}');
        uint256 second = _storeAs(admin, secondRecipe);

        assertEq(first, 1);
        assertEq(second, 2);
        assertEq(recipeVault.getTotalRecipes(), 2);

        GridStorage.Recipe memory stored = recipeVault.getRecipe(first);
        assertEq(stored.recipeRoot, _root(canonicalRecipe));
        assertEq(stored.workflowData, canonicalRecipe);
        assertEq(stored.creator, registrar);
        assertTrue(stored.isPublic);
        assertFalse(stored.canCreateNFTs);
        assertEq(stored.compression, 0);
    }

    function test_storeRecipe_rejectsMismatchedRoot() public {
        vm.prank(registrar);
        vm.expectRevert("RecipeVault: root mismatch");
        recipeVault.storeRecipe(
            bytes32(uint256(1)), canonicalRecipe, false, true, 0, "mismatch", "must fail"
        );
    }

    function test_storeRecipe_rejectsCompressedGovernedRecord() public {
        bytes32 root = _root(canonicalRecipe);
        vm.prank(registrar);
        vm.expectRevert("RecipeVault: compression unsupported");
        recipeVault.storeRecipe(root, canonicalRecipe, false, true, 1, "compressed", "must fail");
    }

    function test_storeRecipe_rejectsDuplicateRoot() public {
        _storeAs(registrar, canonicalRecipe);
        bytes32 root = _root(canonicalRecipe);
        vm.prank(admin);
        vm.expectRevert("RecipeVault: recipe exists");
        recipeVault.storeRecipe(root, canonicalRecipe, false, true, 0, "duplicate", "must fail");
    }

    function test_storeRecipe_respectsWorkflowCap() public {
        vm.prank(admin);
        recipeVault.setMaxWorkflowBytes(canonicalRecipe.length - 1);

        bytes32 root = _root(canonicalRecipe);
        vm.prank(registrar);
        vm.expectRevert("RecipeVault: workflow too large");
        recipeVault.storeRecipe(root, canonicalRecipe, false, true, 0, "too-large", "must fail");
    }

    function test_pauseBlocksPublishingAndPermissionMutation() public {
        uint256 recipeId = _storeAs(registrar, canonicalRecipe);
        vm.prank(pauser);
        roles.pause();

        bytes memory secondRecipe = bytes('{"_grid":{},"2":{"class_type":"Test"}}');
        bytes32 secondRoot = _root(secondRecipe);
        vm.prank(registrar);
        vm.expectRevert("RecipeVault: paused");
        recipeVault.storeRecipe(secondRoot, secondRecipe, false, true, 0, "paused", "must fail");

        vm.prank(registrar);
        vm.expectRevert("RecipeVault: paused");
        recipeVault.updateRecipePermissions(recipeId, true, false);
    }

    function test_permissions_requireRegistrarAndCreatorOrAdmin() public {
        uint256 recipeId = _storeAs(registrar, canonicalRecipe);

        vm.prank(user);
        vm.expectRevert("RecipeVault: not registrar");
        recipeVault.updateRecipePermissions(recipeId, true, false);

        address otherRegistrar = makeAddr("otherRegistrar");
        vm.prank(admin);
        roles.grantRole(GridStorage.REGISTRAR_ROLE, otherRegistrar);
        vm.prank(otherRegistrar);
        vm.expectRevert("RecipeVault: not creator or admin");
        recipeVault.updateRecipePermissions(recipeId, true, false);

        vm.prank(registrar);
        recipeVault.updateRecipePermissions(recipeId, true, false);
        assertTrue(recipeVault.canRecipeCreateNFTs(recipeId));
        assertFalse(recipeVault.isRecipePublic(recipeId));

        vm.prank(admin);
        recipeVault.updateRecipePermissions(recipeId, false, true);
        assertFalse(recipeVault.canRecipeCreateNFTs(recipeId));
        assertTrue(recipeVault.isRecipePublic(recipeId));
    }

    function test_revokedRegistrarCannotMutateExistingRecipe() public {
        uint256 recipeId = _storeAs(registrar, canonicalRecipe);
        vm.prank(admin);
        roles.revokeRole(GridStorage.REGISTRAR_ROLE, registrar);

        vm.prank(registrar);
        vm.expectRevert("RecipeVault: not registrar");
        recipeVault.updateRecipePermissions(recipeId, true, false);
    }
}
