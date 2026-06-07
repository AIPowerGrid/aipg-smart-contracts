// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "./utils/DiamondHarness.sol";

contract DenReporterTest is DiamondHarness {
    bytes32 internal constant ROOT = bytes32(uint256(0xabc));
    uint256 internal constant TOTAL_DEN = 10_000;
    string internal constant IPFS_URI = "ipfs://bafy-mock-cid";

    function setUp() public override {
        super.setUp();
        // Ensure a meaningful pool allocation is set so the snapshot is non-trivial.
        vm.prank(pricingAdmin);
        pool.setPeriodAllocation(4_080 ether, "launch");
    }

    function test_reportPeriod_storesAllFieldsAndEmits() public {
        // Move past the period being reported.
        uint256 periodId = (block.timestamp / 86400);
        vm.warp((periodId + 1) * 86400 + 1);

        vm.prank(reporter);
        reporterFacet.reportPeriod(periodId, ROOT, TOTAL_DEN, IPFS_URI);

        GridStorage.DenReport memory r = reporterFacet.getReport(periodId);
        assertEq(r.periodId, periodId);
        assertEq(r.denRoot, ROOT);
        assertEq(r.totalDen, TOTAL_DEN);
        assertEq(r.poolAllocation, 4_080 ether, "allocation should snapshot at report time");
        assertEq(r.reporter, reporter);
        assertEq(r.ipfsUri, IPFS_URI);
        assertTrue(reporterFacet.isReported(periodId));
    }

    function test_reportPeriod_requiresReporterRole() public {
        uint256 periodId = block.timestamp / 86400;
        vm.warp((periodId + 1) * 86400 + 1);

        vm.prank(user);
        vm.expectRevert(bytes("DenReporter: not reporter"));
        reporterFacet.reportPeriod(periodId, ROOT, TOTAL_DEN, IPFS_URI);
    }

    function test_reportPeriod_rejectsCurrentPeriod() public {
        // Don't warp — current period hasn't ended.
        uint256 periodId = block.timestamp / 86400;
        vm.prank(reporter);
        vm.expectRevert(bytes("DenReporter: period not ended"));
        reporterFacet.reportPeriod(periodId, ROOT, TOTAL_DEN, IPFS_URI);
    }

    function test_reportPeriod_rejectsDoubleReport() public {
        uint256 periodId = block.timestamp / 86400;
        vm.warp((periodId + 1) * 86400 + 1);

        vm.prank(reporter);
        reporterFacet.reportPeriod(periodId, ROOT, TOTAL_DEN, IPFS_URI);

        vm.prank(reporter);
        vm.expectRevert(bytes("DenReporter: period exists"));
        reporterFacet.reportPeriod(periodId, ROOT, TOTAL_DEN, IPFS_URI);
    }

    function test_reportPeriod_rejectsEmptyRoot() public {
        uint256 periodId = block.timestamp / 86400;
        vm.warp((periodId + 1) * 86400 + 1);
        vm.prank(reporter);
        vm.expectRevert(bytes("DenReporter: empty root"));
        reporterFacet.reportPeriod(periodId, bytes32(0), TOTAL_DEN, IPFS_URI);
    }

    function test_reportPeriod_rejectsZeroDen() public {
        uint256 periodId = block.timestamp / 86400;
        vm.warp((periodId + 1) * 86400 + 1);
        vm.prank(reporter);
        vm.expectRevert(bytes("DenReporter: zero den"));
        reporterFacet.reportPeriod(periodId, ROOT, 0, IPFS_URI);
    }

    function test_reportPeriod_allowsEmptyIpfsUri() public {
        uint256 periodId = block.timestamp / 86400;
        vm.warp((periodId + 1) * 86400 + 1);
        vm.prank(reporter);
        reporterFacet.reportPeriod(periodId, ROOT, TOTAL_DEN, "");
        assertEq(reporterFacet.getReport(periodId).ipfsUri, "");
    }

    function test_reportPeriod_snapshotsAllocation_changesAfterDoNotAffectPriorPeriods() public {
        uint256 periodA = block.timestamp / 86400;
        vm.warp((periodA + 1) * 86400 + 1);

        vm.prank(reporter);
        reporterFacet.reportPeriod(periodA, ROOT, TOTAL_DEN, "");

        // Change rate after period A is already snapshotted.
        vm.prank(pricingAdmin);
        pool.setPeriodAllocation(8_160 ether, "ramp");

        // Period B uses the new rate.
        uint256 periodB = periodA + 1;
        vm.warp((periodB + 1) * 86400 + 1);
        vm.prank(reporter);
        reporterFacet.reportPeriod(periodB, ROOT, TOTAL_DEN, "");

        assertEq(reporterFacet.getReport(periodA).poolAllocation, 4_080 ether);
        assertEq(reporterFacet.getReport(periodB).poolAllocation, 8_160 ether);
    }

    function test_pauseBlocksReports() public {
        uint256 periodId = block.timestamp / 86400;
        vm.warp((periodId + 1) * 86400 + 1);

        vm.prank(pauser);
        roles.pause();

        vm.prank(reporter);
        vm.expectRevert(bytes("DenReporter: paused"));
        reporterFacet.reportPeriod(periodId, ROOT, TOTAL_DEN, IPFS_URI);
    }
}
