// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../libraries/GridStorage.sol";

/**
 * @title DenReporter
 * @dev The trusted reporter (multisig initially, validators eventually) commits
 *      per-period den snapshots on-chain. Stored as Merkle roots so the contract
 *      stays cheap regardless of worker count.
 *
 *      Den (電) is AIPG's work-measurement unit. The off-chain formula in
 *      `system-core/grid_api/services/den.py` computes how much den each job
 *      earns based on tokens/steps/model size/context. The on-chain layer never
 *      sees individual jobs — it sees per-period [worker, den] roots.
 *
 *      Off-chain (system-core) builds the tree:
 *          leaves = sorted [worker_address, den] tuples
 *          root   = keccak256(leaves)  // standard pairwise hashing per JobAnchor convention
 *
 *      Workers receive their proof from system-core when they query their den.
 *      PaymentRouter.claim() verifies the proof and pays out their share.
 *
 *      Why Merkle: matches the existing JobAnchor pattern, scales to thousands of
 *      workers per report without gas blowups, and means we never store per-worker
 *      den on-chain — only the root and totals.
 */
contract DenReporter {
    using GridStorage for GridStorage.AppStorage;

    event PeriodReported(
        uint256 indexed periodId,
        bytes32 denRoot,
        uint256 totalDen,
        uint256 poolAllocation,
        address reporter,
        string ipfsUri
    );

    modifier onlyReporter() {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        require(
            s.roles[GridStorage.REPORTER_ROLE][msg.sender] ||
            s.roles[GridStorage.ADMIN_ROLE][msg.sender],
            "DenReporter: not reporter"
        );
        _;
    }

    modifier notPaused() {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        require(!s.paused, "DenReporter: paused");
        _;
    }

    /**
     * @dev Commit a period's den snapshot. The pool allocation is snapshotted
     *      at report time so subsequent allocation changes don't retroactively
     *      affect this period's payouts.
     *
     * @param periodId    block.timestamp / periodLengthSeconds at report time.
     * @param denRoot     Merkle root of sorted [worker, den] leaves.
     * @param totalDen    Sum of all workers' den this period.
     * @param ipfsUri     ipfs://<cid> pointing to JSON with the full
     *                    [worker, den] list, so anyone can independently
     *                    rebuild the tree and verify the root. Pass "" if
     *                    no IPFS pin (degraded auditability but still valid).
     */
    function reportPeriod(
        uint256 periodId,
        bytes32 denRoot,
        uint256 totalDen,
        string calldata ipfsUri
    ) external onlyReporter notPaused {
        require(denRoot != bytes32(0), "DenReporter: empty root");
        require(totalDen > 0, "DenReporter: zero den");

        GridStorage.AppStorage storage s = GridStorage.appStorage();

        // Period must have ended (you can't report the current period mid-way).
        uint256 length = s.periodLengthSeconds == 0 ? 86400 : s.periodLengthSeconds;
        require((periodId + 1) * length <= block.timestamp, "DenReporter: period not ended");

        // Reports are one-shot. To correct a bad report, admin must use a separate
        // recovery path (intentionally not built v1 — fail loudly, fix off-chain,
        // re-report under a different periodId if needed).
        GridStorage.DenReport storage report = s.periodReports[periodId];
        require(report.denRoot == bytes32(0), "DenReporter: period exists");

        report.periodId = periodId;
        report.denRoot = denRoot;
        report.totalDen = totalDen;
        report.poolAllocation = s.periodAllocation;
        report.timestamp = block.timestamp;
        report.reporter = msg.sender;
        report.ipfsUri = ipfsUri;

        emit PeriodReported(periodId, denRoot, totalDen, s.periodAllocation, msg.sender, ipfsUri);
    }

    // ============ VIEWS ============

    function getReport(uint256 periodId) external view returns (GridStorage.DenReport memory) {
        return GridStorage.appStorage().periodReports[periodId];
    }

    function isReported(uint256 periodId) external view returns (bool) {
        return GridStorage.appStorage().periodReports[periodId].denRoot != bytes32(0);
    }
}
