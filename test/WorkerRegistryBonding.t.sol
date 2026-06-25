// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "./utils/DiamondHarness.sol";

/**
 * @dev Bonding / slashing / unbond-cooldown coverage for WorkerRegistry.
 *      The headline property: a worker can NOT escape a slash by unbonding —
 *      unbonding only starts a cooldown, and the bond stays slashable until the
 *      cooldown elapses and withdrawBond() is called.
 */
contract WorkerRegistryBondingTest is DiamondHarness {
    uint256 constant MIN_BOND = 100 ether;
    uint256 constant BOND = 1_000 ether;

    function setUp() public override {
        super.setUp();
        vm.prank(admin);
        workerReg.setMinBond(MIN_BOND);
    }

    function _register(address w, uint256 amount) internal {
        aipg.mint(w, amount);
        vm.startPrank(w);
        aipg.approve(grid, amount);
        workerReg.registerWorker(amount);
        vm.stopPrank();
    }

    // ---------- registration ----------

    function test_register_locksBondInDiamond() public {
        _register(worker1, BOND);
        assertEq(aipg.balanceOf(grid), BOND);
        assertEq(workerReg.getTotalBonded(), BOND);
        assertTrue(workerReg.isWorkerActive(worker1));
    }

    function test_register_insufficientBondReverts() public {
        aipg.mint(worker1, MIN_BOND);
        vm.startPrank(worker1);
        aipg.approve(grid, MIN_BOND);
        vm.expectRevert(bytes("WorkerRegistry: insufficient bond"));
        workerReg.registerWorker(MIN_BOND - 1);
        vm.stopPrank();
    }

    // ---------- unbond cooldown ----------

    function test_unbond_startsCooldown_noImmediateTransfer() public {
        _register(worker1, BOND);

        vm.prank(worker1);
        workerReg.unbond();

        // Bond is still in the diamond — nothing returned.
        assertEq(aipg.balanceOf(grid), BOND);
        assertEq(aipg.balanceOf(worker1), 0);
        assertEq(workerReg.getTotalBonded(), BOND);
        assertFalse(workerReg.isWorkerActive(worker1));

        (uint256 unbondingAt, uint256 bondAmount, bool withdrawable) =
            workerReg.getUnbondInfo(worker1);
        assertEq(unbondingAt, block.timestamp + 7 days);
        assertEq(bondAmount, BOND);
        assertFalse(withdrawable);
    }

    function test_withdraw_revertsBeforeCooldown() public {
        _register(worker1, BOND);
        vm.prank(worker1);
        workerReg.unbond();

        vm.warp(block.timestamp + 7 days - 1);
        vm.prank(worker1);
        vm.expectRevert(bytes("WorkerRegistry: cooldown active"));
        workerReg.withdrawBond();
    }

    function test_unbond_thenWithdraw_returnsFunds() public {
        _register(worker1, BOND);
        vm.prank(worker1);
        workerReg.unbond();

        vm.warp(block.timestamp + 7 days);

        (,, bool withdrawable) = workerReg.getUnbondInfo(worker1);
        assertTrue(withdrawable);

        vm.prank(worker1);
        workerReg.withdrawBond();

        assertEq(aipg.balanceOf(worker1), BOND);
        assertEq(aipg.balanceOf(grid), 0);
        assertEq(workerReg.getTotalBonded(), 0);
    }

    function test_withdraw_revertsWithoutUnbondRequest() public {
        _register(worker1, BOND);
        vm.prank(worker1);
        vm.expectRevert(bytes("WorkerRegistry: no unbond requested"));
        workerReg.withdrawBond();
    }

    function test_cancelUnbond_returnsToActive() public {
        _register(worker1, BOND);
        vm.prank(worker1);
        workerReg.unbond();
        assertFalse(workerReg.isWorkerActive(worker1));

        vm.prank(worker1);
        workerReg.cancelUnbond();

        assertTrue(workerReg.isWorkerActive(worker1));
        (uint256 unbondingAt,,) = workerReg.getUnbondInfo(worker1);
        assertEq(unbondingAt, 0);
    }

    function test_cannotRegisterDuringCooldown() public {
        _register(worker1, BOND);
        vm.prank(worker1);
        workerReg.unbond();

        aipg.mint(worker1, BOND);
        vm.startPrank(worker1);
        aipg.approve(grid, BOND);
        vm.expectRevert(bytes("WorkerRegistry: bond in cooldown"));
        workerReg.registerWorker(BOND);
        vm.stopPrank();
    }

    // ---------- slashing ----------

    function test_slash_routesToRewardPool() public {
        _register(worker1, BOND);
        uint256 depositedBefore = pool.totalDeposited();

        vm.prank(slasher);
        workerReg.slash(worker1, 400 ether, "bad results");

        // Bond accounting down, reward pool accounting up; tokens stay put.
        assertEq(workerReg.getTotalBonded(), BOND - 400 ether);
        assertEq(pool.totalDeposited(), depositedBefore + 400 ether);
        assertEq(aipg.balanceOf(grid), BOND); // physical balance unchanged

        // Still above min => stays active, not flagged.
        assertTrue(workerReg.isWorkerActive(worker1));
    }

    function test_slash_belowMin_deactivatesAndFlags() public {
        _register(worker1, BOND);
        uint256 depositedBefore = pool.totalDeposited();

        vm.prank(slasher);
        workerReg.slash(worker1, BOND - (MIN_BOND - 1), "egregious"); // leaves < min

        assertFalse(workerReg.isWorkerActive(worker1));
        GridStorage.Worker memory w = workerReg.getWorker(worker1);
        assertTrue(w.isSlashed);
        assertEq(w.bondAmount, 0);
        assertEq(workerReg.getTotalBonded(), 0);
        assertEq(pool.totalDeposited(), depositedBefore + BOND);
    }

    function test_slash_duringCooldown_closesEscapeHole() public {
        _register(worker1, BOND);

        // Worker tries to run: requests unbond.
        vm.prank(worker1);
        workerReg.unbond();

        // Grid detects forged receipts mid-cooldown and slashes the full bond.
        vm.prank(slasher);
        workerReg.slash(worker1, BOND, "forged receipts");

        assertEq(workerReg.getTotalBonded(), 0);

        // Cooldown elapses; nothing left to withdraw.
        vm.warp(block.timestamp + 7 days);
        vm.prank(worker1);
        vm.expectRevert(bytes("WorkerRegistry: no unbond requested"));
        workerReg.withdrawBond();

        assertEq(aipg.balanceOf(worker1), 0);
    }

    function test_slash_onlySlasherOrAdmin() public {
        _register(worker1, BOND);

        vm.prank(user);
        vm.expectRevert(bytes("WorkerRegistry: not slasher"));
        workerReg.slash(worker1, 1 ether, "nope");

        // admin also allowed
        vm.prank(admin);
        workerReg.slash(worker1, 1 ether, "admin can");
        assertEq(workerReg.getTotalBonded(), BOND - 1 ether);
    }

    function test_slash_exceedsBondReverts() public {
        _register(worker1, BOND);
        vm.prank(slasher);
        vm.expectRevert(bytes("WorkerRegistry: slash exceeds bond"));
        workerReg.slash(worker1, BOND + 1, "too much");
    }

    function test_slash_unknownWorkerReverts() public {
        vm.prank(slasher);
        vm.expectRevert(bytes("WorkerRegistry: unknown worker"));
        workerReg.slash(worker2, 1 ether, "ghost");
    }

    // ---------- admin config ----------

    function test_setUnbondingPeriod_adminOnly_andBounded() public {
        vm.prank(user);
        vm.expectRevert(bytes("WorkerRegistry: not admin"));
        workerReg.setUnbondingPeriod(1 days);

        vm.prank(admin);
        vm.expectRevert(bytes("WorkerRegistry: cooldown too long"));
        workerReg.setUnbondingPeriod(31 days);

        vm.prank(admin);
        workerReg.setUnbondingPeriod(2 days);
        assertEq(workerReg.unbondingPeriod(), 2 days);
    }

    function test_customUnbondingPeriod_appliesToNewUnbonds() public {
        vm.prank(admin);
        workerReg.setUnbondingPeriod(1 days);

        _register(worker1, BOND);
        vm.prank(worker1);
        workerReg.unbond();

        (uint256 unbondingAt,,) = workerReg.getUnbondInfo(worker1);
        assertEq(unbondingAt, block.timestamp + 1 days);
    }
}
