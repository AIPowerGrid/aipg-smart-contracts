// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "./utils/DiamondHarness.sol";

contract BondReserveTest is DiamondHarness {
    uint256 internal constant BOND = 1_000 ether;
    uint256 internal constant REWARD = 200 ether;

    function setUp() public override {
        super.setUp();

        aipg.mint(worker1, BOND);
        vm.startPrank(worker1);
        aipg.approve(grid, BOND);
        workerReg.registerWorker(BOND);
        vm.stopPrank();

        vm.prank(pricingAdmin);
        pool.setPeriodAllocation(REWARD, "bond reserve regression");
    }

    function test_poolBalance_excludesBondPrincipal() public view {
        assertEq(aipg.balanceOf(grid), BOND);
        assertEq(workerReg.getTotalBonded(), BOND);
        assertEq(pool.poolBalance(), 0);
    }

    function test_claim_cannotSpendBondPrincipal() public {
        (uint256 periodId, bytes32[] memory proof) = _reportSingleWorkerPeriod();

        (uint256 previewAmount, bool previewValid) =
            payments.previewClaim(periodId, worker2, 1, proof);
        assertEq(previewAmount, 0);
        assertFalse(previewValid);

        vm.expectRevert(bytes("PaymentRouter: exceeds rewards"));
        payments.claim(worker2, periodId, 1, proof);

        _assertBondCovered();
        assertFalse(payments.isClaimed(periodId, worker2));
    }

    function test_claimBatch_cannotSpendBondPrincipal() public {
        (uint256 periodId, bytes32[] memory proof) = _reportSingleWorkerPeriod();
        address[] memory workers = new address[](1);
        workers[0] = worker2;
        uint256[] memory den = new uint256[](1);
        den[0] = 1;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = proof;

        vm.expectRevert(bytes("PaymentRouter: exceeds rewards"));
        payments.claimBatch(periodId, workers, den, proofs);

        _assertBondCovered();
        assertFalse(payments.isClaimed(periodId, worker2));
    }

    function test_fundedClaim_leavesBondFullyCovered() public {
        aipg.mint(user, REWARD);
        vm.startPrank(user);
        aipg.approve(grid, REWARD);
        pool.depositRewards(REWARD);
        vm.stopPrank();

        (uint256 periodId, bytes32[] memory proof) = _reportSingleWorkerPeriod();
        payments.claim(worker2, periodId, 1, proof);

        assertEq(aipg.balanceOf(worker2), REWARD);
        assertEq(pool.poolBalance(), 0);
        _assertBondCovered();
    }

    function _reportSingleWorkerPeriod()
        internal
        returns (uint256 periodId, bytes32[] memory proof)
    {
        periodId = block.timestamp / 86400;
        bytes32 leaf = keccak256(abi.encodePacked(worker2, uint256(1)));
        vm.warp((periodId + 1) * 86400 + 1);
        vm.prank(reporter);
        reporterFacet.reportPeriod(periodId, leaf, 1, "");
        proof = new bytes32[](0);
    }

    function _assertBondCovered() internal view {
        assertEq(aipg.balanceOf(grid), BOND);
        assertEq(workerReg.getTotalBonded(), BOND);
        assertGe(aipg.balanceOf(grid), workerReg.getTotalBonded());
    }
}
