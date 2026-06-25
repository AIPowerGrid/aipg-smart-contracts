// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "./utils/DiamondHarness.sol";

contract PaymentRouterTest is DiamondHarness {
    // Period setup constants
    uint256 internal periodId;
    uint256 internal constant POOL = 4_080 ether; // matches 1%/yr daily allocation
    uint256 internal constant TOTAL_DEN = 6_000;

    // A 3-leaf tree
    bytes32 internal leaf1; // worker1 has 1000 den → 680 ether
    bytes32 internal leaf2; // worker2 has 2000 den → 1360 ether
    bytes32 internal leaf3; // worker3 has 3000 den → 2040 ether
    bytes32 internal root;
    bytes32[] internal proof1;
    bytes32[] internal proof2;
    bytes32[] internal proof3;

    function setUp() public override {
        super.setUp();

        // Fund the pool with plenty.
        aipg.mint(admin, 100_000 ether);
        vm.startPrank(admin);
        aipg.approve(grid, 100_000 ether);
        pool.depositRewards(100_000 ether);
        vm.stopPrank();

        // Set the per-period rate
        vm.prank(pricingAdmin);
        pool.setPeriodAllocation(POOL, "launch");

        // Build the canonical tree of (worker, den)
        leaf1 = _leaf(worker1, 1_000);
        leaf2 = _leaf(worker2, 2_000);
        leaf3 = _leaf(worker3, 3_000);

        // Sort leaves so we can reason about the tree predictably.
        bytes32[] memory sorted = new bytes32[](3);
        sorted[0] = leaf1;
        sorted[1] = leaf2;
        sorted[2] = leaf3;
        _sortBytes32(sorted);

        // Tree (3 leaves, orphan carries up):
        //         root
        //        /    \
        //     hAB      sorted[2]
        //    /   \
        //  s[0]   s[1]
        bytes32 hAB = _hashPair(sorted[0], sorted[1]);
        root = _hashPair(hAB, sorted[2]);

        // Build proofs for each leaf
        proof1 = _buildProof(leaf1, sorted, hAB);
        proof2 = _buildProof(leaf2, sorted, hAB);
        proof3 = _buildProof(leaf3, sorted, hAB);

        // Sanity: every leaf verifies against root using contract's algorithm.
        require(_localVerify(leaf1, proof1, root), "test setup: bad proof1");
        require(_localVerify(leaf2, proof2, root), "test setup: bad proof2");
        require(_localVerify(leaf3, proof3, root), "test setup: bad proof3");

        // Commit the report. Warp past the period boundary first.
        periodId = block.timestamp / 86400;
        vm.warp((periodId + 1) * 86400 + 1);
        vm.prank(reporter);
        reporterFacet.reportPeriod(periodId, root, TOTAL_DEN, "");
    }

    function test_claim_paysWorkerProportionalShare() public {
        // worker1 has 1000 of 6000 den → 1000 * 4080 / 6000 = 680 ether
        payments.claim(worker1, periodId, 1_000, proof1);
        assertEq(aipg.balanceOf(worker1), 680 ether);
        assertTrue(payments.isClaimed(periodId, worker1));
    }

    function test_claim_anyoneCanRelay_payoutGoesToLeafAddress() public {
        // Random user pays gas; worker1 receives funds.
        vm.prank(user);
        payments.claim(worker1, periodId, 1_000, proof1);

        assertEq(aipg.balanceOf(worker1), 680 ether);
        assertEq(aipg.balanceOf(user), 0, "relayer must not receive funds");
    }

    function test_claim_doubleClaimReverts() public {
        payments.claim(worker1, periodId, 1_000, proof1);
        vm.expectRevert(bytes("PaymentRouter: already claimed"));
        payments.claim(worker1, periodId, 1_000, proof1);
    }

    function test_claim_badProofReverts() public {
        // Use worker2's proof to claim for worker1 — must fail.
        vm.expectRevert(bytes("PaymentRouter: bad proof"));
        payments.claim(worker1, periodId, 1_000, proof2);
    }

    function test_claim_wrongDenReverts() public {
        // Same worker, different den value — leaf won't match.
        vm.expectRevert(bytes("PaymentRouter: bad proof"));
        payments.claim(worker1, periodId, 999, proof1);
    }

    function test_claim_unreportedPeriodReverts() public {
        vm.expectRevert(bytes("PaymentRouter: period not reported"));
        payments.claim(worker1, periodId + 1, 1_000, proof1);
    }

    function test_claim_zeroWorkerReverts() public {
        vm.expectRevert(bytes("PaymentRouter: zero worker"));
        payments.claim(address(0), periodId, 1_000, proof1);
    }

    function test_claim_zeroDenReverts() public {
        vm.expectRevert(bytes("PaymentRouter: zero den"));
        payments.claim(worker1, periodId, 0, proof1);
    }

    function test_claimBatch_paysAllThree() public {
        address[] memory ws = new address[](3);
        ws[0] = worker1;
        ws[1] = worker2;
        ws[2] = worker3;
        uint256[] memory dens = new uint256[](3);
        dens[0] = 1_000;
        dens[1] = 2_000;
        dens[2] = 3_000;
        bytes32[][] memory proofs = new bytes32[][](3);
        proofs[0] = proof1;
        proofs[1] = proof2;
        proofs[2] = proof3;

        payments.claimBatch(periodId, ws, dens, proofs);

        assertEq(aipg.balanceOf(worker1), 680 ether);
        assertEq(aipg.balanceOf(worker2), 1_360 ether);
        assertEq(aipg.balanceOf(worker3), 2_040 ether);
    }

    function test_claimBatch_skipsBadRowDoesNotRevert() public {
        // Mix in one bad-proof row; the rest should still succeed.
        address[] memory ws = new address[](3);
        ws[0] = worker1;
        ws[1] = worker2;
        ws[2] = worker3;
        uint256[] memory dens = new uint256[](3);
        dens[0] = 1_000; // worker2 has wrong den value
        dens[1] = 999;
        dens[2] = 3_000;
        bytes32[][] memory proofs = new bytes32[][](3);
        proofs[0] = proof1;
        proofs[1] = proof2;
        proofs[2] = proof3;

        payments.claimBatch(periodId, ws, dens, proofs);

        assertEq(aipg.balanceOf(worker1), 680 ether);
        assertEq(aipg.balanceOf(worker2), 0, "bad-proof row should be skipped");
        assertEq(aipg.balanceOf(worker3), 2_040 ether);
        assertTrue(payments.isClaimed(periodId, worker1));
        assertFalse(payments.isClaimed(periodId, worker2));
        assertTrue(payments.isClaimed(periodId, worker3));
    }

    function test_claimBatch_skipsAlreadyClaimed() public {
        // Pre-claim worker1, then batch with worker1 in it — batch should skip.
        payments.claim(worker1, periodId, 1_000, proof1);
        uint256 balBefore = aipg.balanceOf(worker1);

        address[] memory ws = new address[](2);
        ws[0] = worker1;
        ws[1] = worker2;
        uint256[] memory dens = new uint256[](2);
        dens[0] = 1_000;
        dens[1] = 2_000;
        bytes32[][] memory proofs = new bytes32[][](2);
        proofs[0] = proof1;
        proofs[1] = proof2;

        payments.claimBatch(periodId, ws, dens, proofs);

        // worker1 balance unchanged; worker2 still paid.
        assertEq(aipg.balanceOf(worker1), balBefore);
        assertEq(aipg.balanceOf(worker2), 1_360 ether);
    }

    function test_claimBatch_rejectsLengthMismatch() public {
        address[] memory ws = new address[](2);
        uint256[] memory dens = new uint256[](3);
        bytes32[][] memory proofs = new bytes32[][](2);

        vm.expectRevert(bytes("PaymentRouter: length mismatch"));
        payments.claimBatch(periodId, ws, dens, proofs);
    }

    function test_claimBatch_rejectsOversize() public {
        address[] memory ws = new address[](201);
        uint256[] memory dens = new uint256[](201);
        bytes32[][] memory proofs = new bytes32[][](201);

        vm.expectRevert(bytes("PaymentRouter: batch too large"));
        payments.claimBatch(periodId, ws, dens, proofs);
    }

    function test_previewClaim_returnsExpectedAmountAndValidFlag() public {
        (uint256 amount, bool valid) = payments.previewClaim(periodId, worker1, 1_000, proof1);
        assertTrue(valid);
        assertEq(amount, 680 ether);
    }

    function test_previewClaim_returnsZeroForAlreadyClaimed() public {
        payments.claim(worker1, periodId, 1_000, proof1);
        (uint256 amount, bool valid) = payments.previewClaim(periodId, worker1, 1_000, proof1);
        assertFalse(valid);
        assertEq(amount, 0);
    }

    function test_previewClaim_returnsZeroForUnreportedPeriod() public {
        (uint256 amount, bool valid) = payments.previewClaim(periodId + 7, worker1, 1_000, proof1);
        assertFalse(valid);
        assertEq(amount, 0);
    }

    function test_pauseBlocksClaim() public {
        vm.prank(pauser);
        roles.pause();

        vm.expectRevert(bytes("PaymentRouter: paused"));
        payments.claim(worker1, periodId, 1_000, proof1);
    }

    function test_claim_periodCapBoundsCorruptReport() public {
        uint256 badPeriod = periodId + 1;
        vm.warp((badPeriod + 1) * 86400 + 1);

        bytes32 la = _leaf(worker1, 1_000);
        bytes32 lb = _leaf(worker2, 1_000);
        bytes32 badRoot = _hashPair(la, lb);

        // The root contains 2,000 den, but the reporter understates totalDen as
        // 1,000. Without a per-period cap each worker computes a whole-pool share.
        vm.prank(reporter);
        reporterFacet.reportPeriod(badPeriod, badRoot, 1_000, "");

        bytes32[] memory proofA = new bytes32[](1);
        proofA[0] = lb;
        bytes32[] memory proofB = new bytes32[](1);
        proofB[0] = la;

        payments.claim(worker1, badPeriod, 1_000, proofA);
        assertEq(aipg.balanceOf(worker1), POOL);

        vm.expectRevert(bytes("PaymentRouter: period overpay"));
        payments.claim(worker2, badPeriod, 1_000, proofB);

        assertEq(aipg.balanceOf(worker2), 0);
        assertFalse(payments.isClaimed(badPeriod, worker2));
    }

    function test_claimBatch_periodCapRevertsWholeCorruptBatch() public {
        uint256 badPeriod = periodId + 1;
        vm.warp((badPeriod + 1) * 86400 + 1);

        bytes32 la = _leaf(worker1, 1_000);
        bytes32 lb = _leaf(worker2, 1_000);
        vm.prank(reporter);
        reporterFacet.reportPeriod(badPeriod, _hashPair(la, lb), 1_000, "");

        address[] memory ws = new address[](2);
        ws[0] = worker1;
        ws[1] = worker2;
        uint256[] memory dens = new uint256[](2);
        dens[0] = 1_000;
        dens[1] = 1_000;
        bytes32[][] memory proofs = new bytes32[][](2);
        proofs[0] = new bytes32[](1);
        proofs[0][0] = lb;
        proofs[1] = new bytes32[](1);
        proofs[1][0] = la;

        vm.expectRevert(bytes("PaymentRouter: period overpay"));
        payments.claimBatch(badPeriod, ws, dens, proofs);

        assertEq(aipg.balanceOf(worker1), 0);
        assertEq(aipg.balanceOf(worker2), 0);
        assertFalse(payments.isClaimed(badPeriod, worker1));
        assertFalse(payments.isClaimed(badPeriod, worker2));
    }

    // -------- helpers --------

    function _sortBytes32(bytes32[] memory arr) internal pure {
        // tiny bubble sort, n is small in tests
        for (uint256 i = 0; i < arr.length; i++) {
            for (uint256 j = i + 1; j < arr.length; j++) {
                if (arr[i] > arr[j]) {
                    (arr[i], arr[j]) = (arr[j], arr[i]);
                }
            }
        }
    }

    /// Build a proof for `leaf` against a 3-leaf sorted tree.
    function _buildProof(bytes32 leaf, bytes32[] memory sorted, bytes32 hAB)
        internal
        pure
        returns (bytes32[] memory)
    {
        // Position 0 and 1 pair up (their proof needs the other + sorted[2])
        // Position 2 is the orphan that pairs with hAB at level 1.
        if (leaf == sorted[0]) {
            bytes32[] memory p = new bytes32[](2);
            p[0] = sorted[1];
            p[1] = sorted[2];
            return p;
        } else if (leaf == sorted[1]) {
            bytes32[] memory p = new bytes32[](2);
            p[0] = sorted[0];
            p[1] = sorted[2];
            return p;
        } else if (leaf == sorted[2]) {
            bytes32[] memory p = new bytes32[](1);
            p[0] = hAB;
            return p;
        } else {
            revert("leaf not in tree");
        }
    }

    function _localVerify(bytes32 leaf, bytes32[] memory proof, bytes32 expectedRoot)
        internal
        pure
        returns (bool)
    {
        bytes32 computed = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            computed = computed <= proof[i]
                ? keccak256(abi.encodePacked(computed, proof[i]))
                : keccak256(abi.encodePacked(proof[i], computed));
        }
        return computed == expectedRoot;
    }
}

contract PaymentRouterCollateralHandler {
    PaymentRouter internal payments;
    uint256 internal periodId;
    address internal worker;
    uint256 internal workerDen;

    constructor(PaymentRouter _payments, uint256 _periodId, address _worker, uint256 _workerDen) {
        payments = _payments;
        periodId = _periodId;
        worker = _worker;
        workerDen = _workerDen;
    }

    function claim() external {
        bytes32[] memory proof = new bytes32[](0);
        try payments.claim(worker, periodId, workerDen, proof) {} catch {}
    }

    function claimBatch() external {
        address[] memory workers = new address[](1);
        workers[0] = worker;
        uint256[] memory dens = new uint256[](1);
        dens[0] = workerDen;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);
        try payments.claimBatch(periodId, workers, dens, proofs) {} catch {}
    }
}

contract PaymentRouterCollateralSafetyTest is DiamondHarness {
    uint256 internal constant BOND = 1_000 ether;
    uint256 internal constant CLAIM_ALLOCATION = 500 ether;
    uint256 internal periodId;
    PaymentRouterCollateralHandler internal handler;

    function setUp() public override {
        super.setUp();

        aipg.mint(worker1, BOND);
        vm.startPrank(worker1);
        aipg.approve(grid, BOND);
        workerReg.registerWorker(BOND);
        vm.stopPrank();

        vm.prank(pricingAdmin);
        pool.setPeriodAllocation(CLAIM_ALLOCATION, "underfunded regression");

        periodId = block.timestamp / 86400;
        vm.warp((periodId + 1) * 86400 + 1);

        vm.prank(reporter);
        reporterFacet.reportPeriod(periodId, _leaf(worker2, 1_000), 1_000, "");

        handler = new PaymentRouterCollateralHandler(payments, periodId, worker2, 1_000);
        targetContract(address(handler));
    }

    function test_claim_revertsBeforeConsumingBondedCollateralWhenRewardsUnderfunded() public {
        bytes32[] memory proof = new bytes32[](0);

        vm.expectRevert(bytes("exceeds rewards"));
        payments.claim(worker2, periodId, 1_000, proof);

        assertEq(aipg.balanceOf(grid), BOND);
        assertEq(workerReg.getTotalBonded(), BOND);
        assertEq(pool.totalPaidOut(), 0);
        assertFalse(payments.isClaimed(periodId, worker2));
        assertGe(aipg.balanceOf(grid), workerReg.getTotalBonded());
    }

    function test_claimBatch_revertsBeforeConsumingBondedCollateralWhenRewardsUnderfunded() public {
        address[] memory workers = new address[](1);
        workers[0] = worker2;
        uint256[] memory dens = new uint256[](1);
        dens[0] = 1_000;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);

        vm.expectRevert(bytes("exceeds rewards"));
        payments.claimBatch(periodId, workers, dens, proofs);

        assertEq(aipg.balanceOf(grid), BOND);
        assertEq(workerReg.getTotalBonded(), BOND);
        assertEq(pool.totalPaidOut(), 0);
        assertFalse(payments.isClaimed(periodId, worker2));
        assertGe(aipg.balanceOf(grid), workerReg.getTotalBonded());
    }

    function invariant_diamondBalanceCoversBondedCollateral() public view {
        require(
            aipg.balanceOf(grid) >= workerReg.getTotalBonded(),
            "invariant: bonds undercollateralized"
        );
    }
}
