// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../libraries/GridStorage.sol";

interface IERC20Transfer {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title PaymentRouter
 * @dev Anyone can submit a worker's claim using a Merkle proof against the
 *      period's den root. AIPG always goes to the worker address in the leaf —
 *      msg.sender just pays the gas.
 *
 *      This lets the team run a daily settlement bot that pays everyone with
 *      zero worker action required. Workers in countries without easy access to
 *      Base ETH never need to pre-fund a wallet to receive earnings.
 *
 *      Workers can still self-claim if they want a single period sooner.
 *
 *      Math:
 *          share  = workerDen / report.totalDen
 *          amount = share * report.poolAllocation
 *
 *      Each (periodId, worker) is claimable exactly once.
 */
contract PaymentRouter {
    using GridStorage for GridStorage.AppStorage;

    event Claimed(
        uint256 indexed periodId,
        address indexed worker,
        address indexed relayer,
        uint256 den,
        uint256 amount
    );

    modifier notPaused() {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        require(!s.paused, "PaymentRouter: paused");
        _;
    }

    /**
     * @dev Claim a worker's payout for a period. Caller can be the worker themself,
     *      a team settlement bot, or any third party. Payout always goes to the
     *      `worker` address in the leaf.
     */
    function claim(
        address worker,
        uint256 periodId,
        uint256 workerDen,
        bytes32[] calldata proof
    ) external notPaused {
        _claim(worker, periodId, workerDen, proof);
    }

    /**
     * @dev Batch claim — settle many workers in one tx. The team's bot calls
     *      this once a period. On Base this is essentially free; sized for
     *      ~100-200 workers per tx to stay well under block gas limits.
     *
     *      Skips entries where the proof fails or the worker already claimed,
     *      so a bad row doesn't revert the whole batch.
     */
    function claimBatch(
        uint256 periodId,
        address[] calldata workers,
        uint256[] calldata den,
        bytes32[][] calldata proofs
    ) external notPaused {
        require(
            workers.length == den.length && workers.length == proofs.length,
            "PaymentRouter: length mismatch"
        );
        require(workers.length <= 200, "PaymentRouter: batch too large");

        GridStorage.AppStorage storage s = GridStorage.appStorage();
        GridStorage.DenReport storage report = s.periodReports[periodId];
        require(report.denRoot != bytes32(0), "PaymentRouter: period not reported");

        for (uint256 i = 0; i < workers.length; i++) {
            _claimSafe(s, report, periodId, workers[i], den[i], proofs[i]);
        }
    }

    /**
     * @dev Single-claim path that reverts on failure. Used by direct claim().
     */
    function _claim(
        address worker,
        uint256 periodId,
        uint256 workerDen,
        bytes32[] calldata proof
    ) internal {
        require(worker != address(0), "PaymentRouter: zero worker");
        require(workerDen > 0, "PaymentRouter: zero den");

        GridStorage.AppStorage storage s = GridStorage.appStorage();
        GridStorage.DenReport storage report = s.periodReports[periodId];

        require(report.denRoot != bytes32(0), "PaymentRouter: period not reported");
        require(!s.periodClaimed[periodId][worker], "PaymentRouter: already claimed");

        bytes32 leaf = keccak256(abi.encodePacked(worker, workerDen));
        require(_verify(proof, report.denRoot, leaf), "PaymentRouter: bad proof");

        uint256 amount = (workerDen * report.poolAllocation) / report.totalDen;
        require(amount > 0, "PaymentRouter: zero payout");

        // CEI: mark claimed before transferring.
        s.periodClaimed[periodId][worker] = true;
        s.totalPaidOut += amount;

        GridStorage.Worker storage w = s.workers[worker];
        if (w.workerAddress == worker) {
            w.totalRewardsEarned += amount;
        }

        require(
            IERC20Transfer(s.aipgToken).transfer(worker, amount),
            "PaymentRouter: transfer failed"
        );

        emit Claimed(periodId, worker, msg.sender, workerDen, amount);
    }

    /**
     * @dev Batch-friendly claim that silently skips bad entries instead of
     *      reverting. Lets the settlement bot push 200 workers and have 199
     *      succeed if one has a bad proof or already claimed.
     */
    function _claimSafe(
        GridStorage.AppStorage storage s,
        GridStorage.DenReport storage report,
        uint256 periodId,
        address worker,
        uint256 workerDen,
        bytes32[] calldata proof
    ) internal {
        if (worker == address(0) || workerDen == 0) return;
        if (s.periodClaimed[periodId][worker]) return;

        bytes32 leaf = keccak256(abi.encodePacked(worker, workerDen));
        if (!_verify(proof, report.denRoot, leaf)) return;

        uint256 amount = (workerDen * report.poolAllocation) / report.totalDen;
        if (amount == 0) return;

        s.periodClaimed[periodId][worker] = true;
        s.totalPaidOut += amount;

        GridStorage.Worker storage w = s.workers[worker];
        if (w.workerAddress == worker) {
            w.totalRewardsEarned += amount;
        }

        if (!IERC20Transfer(s.aipgToken).transfer(worker, amount)) return;

        emit Claimed(periodId, worker, msg.sender, workerDen, amount);
    }

    // ============ VIEWS ============

    function previewClaim(
        uint256 periodId,
        address worker,
        uint256 workerDen,
        bytes32[] calldata proof
    ) external view returns (uint256 amount, bool valid) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        GridStorage.DenReport storage report = s.periodReports[periodId];

        if (report.denRoot == bytes32(0)) return (0, false);
        if (s.periodClaimed[periodId][worker]) return (0, false);
        if (workerDen == 0 || report.totalDen == 0) return (0, false);

        bytes32 leaf = keccak256(abi.encodePacked(worker, workerDen));
        if (!_verify(proof, report.denRoot, leaf)) return (0, false);

        amount = (workerDen * report.poolAllocation) / report.totalDen;
        valid = true;
    }

    function isClaimed(uint256 periodId, address worker) external view returns (bool) {
        return GridStorage.appStorage().periodClaimed[periodId][worker];
    }

    // ============ INTERNAL ============

    function _verify(
        bytes32[] calldata proof,
        bytes32 root,
        bytes32 leaf
    ) internal pure returns (bool) {
        bytes32 computed = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 sibling = proof[i];
            if (computed <= sibling) {
                computed = keccak256(abi.encodePacked(computed, sibling));
            } else {
                computed = keccak256(abi.encodePacked(sibling, computed));
            }
        }
        return computed == root;
    }
}
