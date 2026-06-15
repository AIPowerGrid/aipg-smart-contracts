// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "./utils/DiamondHarness.sol";
import "../contracts/grid/modules/ModelVault.sol";
import "../contracts/grid/interfaces/IModuleManager.sol";
import "../contracts/grid/libraries/GridStorage.sol";

/// @dev Cuts ModelVault into the harness diamond and exercises the on-chain
/// den-multiplier (the field the off-chain grid syncs for reward pricing).
contract ModelVaultDenMultiplierTest is DiamondHarness {
    ModelVault internal vault; // bound to the diamond
    uint256 internal modelId;

    function setUp() public override {
        super.setUp();

        // Deploy + cut in ModelVault (the shared harness doesn't include it).
        ModelVault impl = new ModelVault();
        bytes4[] memory sel = new bytes4[](5);
        sel[0] = ModelVault.registerModel.selector;
        sel[1] = ModelVault.setDenMultiplier.selector;
        sel[2] = ModelVault.setDenMultipliers.selector;
        sel[3] = ModelVault.getDenMultiplier.selector;
        sel[4] = ModelVault.isModelActive.selector;

        IModuleManager.ModuleCut[] memory cut = new IModuleManager.ModuleCut[](1);
        cut[0] = IModuleManager.ModuleCut({
            moduleAddress: address(impl),
            action: IModuleManager.ModuleAction.Add,
            functionSelectors: sel
        });
        vm.prank(admin);
        IModuleManager(grid).updateModules(cut, address(0), "");

        vault = ModelVault(grid);

        // Register one model (admin has ADMIN_ROLE => passes onlyRegistrar).
        vm.prank(admin);
        modelId = vault.registerModel(
            keccak256("gpt-oss-120b"), GridStorage.ModelType.TEXT_MODEL,
            "gpt-oss-120b.gguf", "gpt-oss-120b", "1.0", "", "",
            0, "fp8", "gguf", 0, "", false, false, false, false, false
        );
    }

    function test_setAndGetDenMultiplier() public {
        assertEq(vault.getDenMultiplier(modelId), 0, "unset = 0");
        vm.prank(admin);
        vault.setDenMultiplier(modelId, 120_000); // 120.0
        assertEq(vault.getDenMultiplier(modelId), 120_000);
    }

    function test_setDenMultiplier_requiresAdmin() public {
        vm.prank(user);
        vm.expectRevert(bytes("ModelVault: not admin"));
        vault.setDenMultiplier(modelId, 27_000);
    }

    function test_setDenMultiplier_unknownModelReverts() public {
        vm.prank(admin);
        vm.expectRevert(bytes("ModelVault: not found"));
        vault.setDenMultiplier(999, 27_000);
    }

    function test_batchSetDenMultipliers() public {
        vm.prank(admin);
        uint256 id2 = vault.registerModel(
            keccak256("qwen3-7b"), GridStorage.ModelType.TEXT_MODEL,
            "qwen3-7b.gguf", "qwen3-7b", "1.0", "", "",
            0, "fp16", "gguf", 0, "", false, false, false, false, false
        );

        uint256[] memory ids = new uint256[](2);
        ids[0] = modelId; ids[1] = id2;
        uint256[] memory mults = new uint256[](2);
        mults[0] = 120_000; mults[1] = 7_000;

        vm.prank(admin);
        vault.setDenMultipliers(ids, mults);
        assertEq(vault.getDenMultiplier(modelId), 120_000);
        assertEq(vault.getDenMultiplier(id2), 7_000);
    }

    function test_batchSet_lengthMismatchReverts() public {
        uint256[] memory ids = new uint256[](2);
        uint256[] memory mults = new uint256[](1);
        vm.prank(admin);
        vm.expectRevert(bytes("ModelVault: length mismatch"));
        vault.setDenMultipliers(ids, mults);
    }
}
