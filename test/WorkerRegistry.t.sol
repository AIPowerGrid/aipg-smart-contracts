// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "./utils/DiamondHarness.sol";

contract WorkerRegistryTest is DiamondHarness {
    function setUp() public override {
        super.setUp();
        aipg.mint(worker1, 100 ether);
    }

    // Regression (P2): re-registering after an unbond must not push a duplicate
    // entry into workerList.
    function test_reRegisterAfterUnbond_noDuplicateInList() public {
        vm.startPrank(worker1);
        aipg.approve(grid, 100 ether);
        workerReg.registerWorker(1 ether);
        assertEq(workerReg.getWorkerCount(), 1);

        workerReg.unbond();
        assertFalse(workerReg.isWorkerActive(worker1));

        vm.warp(block.timestamp + 7 days);
        workerReg.withdrawBond();

        // Re-register after withdrawal: still exactly one enumeration entry.
        aipg.approve(grid, 100 ether);
        workerReg.registerWorker(1 ether);
        vm.stopPrank();

        assertTrue(workerReg.isWorkerActive(worker1));
        assertEq(workerReg.getWorkerCount(), 1, "duplicate workerList entry after re-register");
        assertEq(workerReg.getWorkerAt(0), worker1);
    }

    function test_getWorkerAt_revertsOutOfBounds() public {
        vm.expectRevert(bytes("WorkerRegistry: index out of bounds"));
        workerReg.getWorkerAt(0);
    }
}
