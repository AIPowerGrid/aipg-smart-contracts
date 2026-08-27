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

    function _evidence(string memory label) internal pure returns (bytes32) {
        return keccak256(bytes(label));
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

    function test_register_transferFailureRollsBackAllEffects() public {
        vm.startPrank(worker1);
        aipg.approve(grid, BOND);
        vm.expectRevert(bytes("MockAIPG: insufficient balance"));
        workerReg.registerWorker(BOND);
        vm.stopPrank();

        GridStorage.Worker memory w = workerReg.getWorker(worker1);
        assertEq(w.workerAddress, address(0));
        assertEq(workerReg.getWorkerCount(), 0);
        assertEq(workerReg.getTotalBonded(), 0);
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
        workerReg.slash(worker1, 400 ether, _evidence("bad results"), "bad results");

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
        workerReg.slash(worker1, BOND - (MIN_BOND - 1), _evidence("egregious"), "egregious"); // leaves < min

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
        workerReg.slash(worker1, BOND, _evidence("forged receipts"), "forged receipts");

        assertEq(workerReg.getTotalBonded(), 0);

        // Cooldown elapses; nothing left to withdraw.
        vm.warp(block.timestamp + 7 days);
        vm.prank(worker1);
        vm.expectRevert(bytes("WorkerRegistry: no unbond requested"));
        workerReg.withdrawBond();

        assertEq(aipg.balanceOf(worker1), 0);
    }

    function test_slash_onlyExplicitSlasher() public {
        _register(worker1, BOND);

        vm.prank(user);
        vm.expectRevert(bytes("WorkerRegistry: not slasher"));
        workerReg.slash(worker1, 1 ether, _evidence("nope"), "nope");

        vm.prank(admin);
        vm.expectRevert(bytes("WorkerRegistry: not slasher"));
        workerReg.slash(worker1, 1 ether, _evidence("admin cannot"), "admin cannot");

        vm.prank(slasher);
        workerReg.slash(worker1, 1 ether, _evidence("slasher can"), "slasher can");
        assertEq(workerReg.getTotalBonded(), BOND - 1 ether);
    }

    function test_pause_doesNotTrapMaturedBond() public {
        _register(worker1, BOND);
        vm.prank(worker1);
        workerReg.unbond();

        vm.prank(pauser);
        roles.pause();
        vm.warp(block.timestamp + 7 days);

        vm.prank(worker1);
        workerReg.withdrawBond();

        assertEq(aipg.balanceOf(worker1), BOND);
        assertEq(workerReg.getTotalBonded(), 0);
    }

    function test_pause_allowsCancellingExistingUnbond() public {
        _register(worker1, BOND);
        vm.prank(worker1);
        workerReg.unbond();

        vm.prank(pauser);
        roles.pause();

        vm.prank(worker1);
        workerReg.cancelUnbond();
        assertTrue(workerReg.isWorkerActive(worker1));
    }

    function test_slash_exceedsBondReverts() public {
        _register(worker1, BOND);
        vm.prank(slasher);
        vm.expectRevert(bytes("WorkerRegistry: slash exceeds bond"));
        workerReg.slash(worker1, BOND + 1, _evidence("too much"), "too much");
    }

    function test_slash_unknownWorkerReverts() public {
        vm.prank(slasher);
        vm.expectRevert(bytes("WorkerRegistry: unknown worker"));
        workerReg.slash(worker2, 1 ether, _evidence("ghost"), "ghost");
    }

    function test_slash_reasonIsBounded() public {
        _register(worker1, BOND);
        vm.prank(slasher);
        vm.expectRevert(bytes("WorkerRegistry: reason too long"));
        workerReg.slash(worker1, 1 ether, _evidence("long reason"), new string(257));
    }

    function test_slash_requiresUniqueNonzeroEvidence() public {
        _register(worker1, BOND);

        vm.prank(slasher);
        vm.expectRevert(bytes("WorkerRegistry: zero evidence"));
        workerReg.slash(worker1, 1 ether, bytes32(0), "missing evidence");

        bytes32 evidenceId = _evidence("assignment-finalized-1");
        assertFalse(workerReg.isSlashEvidenceUsed(evidenceId));
        vm.prank(slasher);
        workerReg.slash(worker1, 1 ether, evidenceId, "first adjudication");
        assertTrue(workerReg.isSlashEvidenceUsed(evidenceId));

        vm.prank(slasher);
        vm.expectRevert(bytes("WorkerRegistry: evidence used"));
        workerReg.slash(worker1, 1 ether, evidenceId, "duplicate adjudication");
    }

    function test_partialSlashDuringCooldown_returnsOnlyRemainingBond() public {
        _register(worker1, BOND);
        vm.prank(worker1);
        workerReg.unbond();

        vm.prank(slasher);
        workerReg.slash(worker1, 400 ether, _evidence("reviewed evidence"), "reviewed evidence");

        vm.warp(block.timestamp + 7 days);
        vm.prank(worker1);
        workerReg.withdrawBond();

        assertEq(aipg.balanceOf(worker1), 600 ether);
        assertEq(workerReg.getTotalBonded(), 0);
        assertEq(pool.totalDeposited(), 400 ether);
        assertEq(aipg.balanceOf(grid), 400 ether);
    }

    // ---------- admin config ----------

    function test_setUnbondingPeriod_adminOnly_andBounded() public {
        vm.prank(user);
        vm.expectRevert(bytes("WorkerRegistry: not admin"));
        workerReg.setUnbondingPeriod(1 days);

        vm.prank(admin);
        vm.expectRevert(bytes("WorkerRegistry: invalid cooldown"));
        workerReg.setUnbondingPeriod(31 days);

        vm.prank(admin);
        vm.expectRevert(bytes("WorkerRegistry: invalid cooldown"));
        workerReg.setUnbondingPeriod(1 days - 1);

        vm.prank(admin);
        workerReg.setUnbondingPeriod(2 days);
        assertEq(workerReg.unbondingPeriod(), 2 days);

        vm.prank(admin);
        workerReg.setUnbondingPeriod(0);
        assertEq(workerReg.unbondingPeriod(), 7 days);
    }

    function test_setMinBond_rejectsZero() public {
        vm.prank(admin);
        vm.expectRevert(bytes("WorkerRegistry: zero min bond"));
        workerReg.setMinBond(0);
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
