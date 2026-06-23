// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title GridRewardDistributor
 * @notice Standalone, token-generic Merkle distributor for AI Power Grid worker
 *         payouts. Deploy it with `payoutToken = USDC` to pay workers real money;
 *         deploy a second instance with AIPG for a bonus layer. It is deliberately
 *         NOT part of the grid Diamond — self-contained, auditable in isolation,
 *         and it leaves the live AIPG RewardPool/PaymentRouter untouched.
 *
 * @dev It consumes the SAME per-period den Merkle root the settlement bot already
 *      produces for the AIPG path, so one snapshot can fund payouts in multiple
 *      assets. The leaf and proof conventions are byte-for-byte identical to
 *      `PaymentRouter`:
 *
 *          leaf      = keccak256(abi.encodePacked(worker, den))   // den = scaled micro-den
 *          innerNode = keccak256(min(a,b) || max(a,b))            // sorted pairs
 *          amount    = den * report.poolAllocation / report.totalDen
 *
 *      Each (periodId, worker) is claimable exactly once. Anyone may relay a
 *      claim; the payout always goes to the `worker` in the leaf, so a settlement
 *      bot can pay everyone with zero worker action and workers never need gas.
 *
 *      Token-agnostic math: `poolAllocation` is denominated in the payout token's
 *      own base units (e.g. 6 decimals for USDC), so nothing here assumes 18.
 *
 *      Safety: a period can only be reported once funding covers its full
 *      allocation, so every claim for a reported period is guaranteed payable.
 */
contract GridRewardDistributor is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant REPORTER_ROLE = keccak256("REPORTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Max workers per batch claim (block-gas safety; Base is cheap but bounded).
    uint256 public constant MAX_BATCH = 200;

    /// @notice The ERC20 paid to workers (e.g. USDC on Base). Immutable by design.
    IERC20 public immutable payoutToken;

    struct Report {
        bytes32 denRoot; // Merkle root of sorted [worker, den] leaves
        uint256 totalDen; // sum of all workers' den this period
        uint256 poolAllocation; // payout-token units released for this period (snapshot)
        uint64 reportedAt; // block timestamp of the report
    }

    /// @notice Per-period settlement report (periodId => Report).
    mapping(uint256 => Report) public reports;
    /// @notice periodId => worker => claimed.
    mapping(uint256 => mapping(address => bool)) public periodClaimed;
    /// @notice periodId => total paid so far (hard cap = that period's poolAllocation).
    mapping(uint256 => uint256) public paidPerPeriod;

    /// @notice Per-period payout budget applied to the NEXT reported period.
    uint256 public periodAllocation;

    /// @notice Lifetime accounting.
    uint256 public totalPaidOut;
    /// @notice Sum of every reported period's allocation. `totalCommitted -
    ///         totalPaidOut` is USDC owed to workers and is NOT withdrawable.
    uint256 public totalCommitted;

    event Funded(address indexed from, uint256 amount, uint256 newBalance);
    event Withdrawn(address indexed to, uint256 amount, string reason);
    event PeriodAllocationSet(uint256 oldAllocation, uint256 newAllocation, string reason);
    event PeriodReported(
        uint256 indexed periodId,
        bytes32 denRoot,
        uint256 totalDen,
        uint256 poolAllocation,
        address indexed reporter,
        string ipfsUri
    );
    event Claimed(
        uint256 indexed periodId,
        address indexed worker,
        address indexed relayer,
        uint256 den,
        uint256 amount
    );

    /**
     * @param token ERC20 paid to workers (USDC on Base).
     * @param admin Holds DEFAULT_ADMIN_ROLE + PAUSER_ROLE (use a Safe multisig).
     */
    constructor(IERC20 token, address admin) {
        require(address(token) != address(0), "Distributor: zero token");
        require(admin != address(0), "Distributor: zero admin");
        payoutToken = token;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    // ============ FUNDING / ADMIN ============

    /// @notice Deposit payout tokens into the pool. Caller must approve first.
    function fund(uint256 amount) external nonReentrant {
        require(amount > 0, "Distributor: zero amount");
        payoutToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Funded(msg.sender, amount, poolBalance());
    }

    /// @notice Set the per-period allocation (payout-token units). Applies to the
    ///         NEXT reported period; already-reported periods keep their snapshot.
    function setPeriodAllocation(uint256 newAllocation, string calldata reason)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        emit PeriodAllocationSet(periodAllocation, newAllocation, reason);
        periodAllocation = newAllocation;
    }

    /// @notice Recover tokens not committed to a reported period (e.g. overfunding
    ///         or a wrong deposit). Admin-gated; emits for transparency.
    function withdraw(address to, uint256 amount, string calldata reason)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonReentrant
    {
        require(to != address(0), "Distributor: zero to");
        // Never touch USDC already owed to workers for reported, unclaimed periods.
        require(
            poolBalance() - amount >= totalCommitted - totalPaidOut,
            "Distributor: committed funds"
        );
        payoutToken.safeTransfer(to, amount);
        emit Withdrawn(to, amount, reason);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // ============ REPORTING ============

    /**
     * @notice Commit a period's den Merkle root and snapshot its allocation.
     * @dev Requires the pool to already cover this period's allocation, so every
     *      claim for it is guaranteed payable. One report per period (immutable).
     */
    function reportPeriod(
        uint256 periodId,
        bytes32 denRoot,
        uint256 totalDen,
        string calldata ipfsUri
    ) external onlyRole(REPORTER_ROLE) whenNotPaused {
        require(denRoot != bytes32(0), "Distributor: empty root");
        require(totalDen > 0, "Distributor: zero den");

        Report storage report = reports[periodId];
        require(report.denRoot == bytes32(0), "Distributor: period exists");

        uint256 alloc = periodAllocation;
        require(alloc > 0, "Distributor: zero allocation");
        require(poolBalance() >= alloc, "Distributor: pool underfunded");

        report.denRoot = denRoot;
        report.totalDen = totalDen;
        report.poolAllocation = alloc;
        report.reportedAt = uint64(block.timestamp);
        totalCommitted += alloc; // locks `alloc` against admin withdrawal

        emit PeriodReported(periodId, denRoot, totalDen, alloc, msg.sender, ipfsUri);
    }

    // ============ CLAIMS ============

    /// @notice Claim one worker's payout. Caller may be the worker, a bot, or anyone;
    ///         funds always go to `worker`.
    function claim(uint256 periodId, address worker, uint256 workerDen, bytes32[] calldata proof)
        external
        whenNotPaused
        nonReentrant
    {
        require(worker != address(0), "Distributor: zero worker");
        require(workerDen > 0, "Distributor: zero den");

        Report storage report = reports[periodId];
        require(report.denRoot != bytes32(0), "Distributor: not reported");
        require(!periodClaimed[periodId][worker], "Distributor: already claimed");

        bytes32 leaf = keccak256(abi.encodePacked(worker, workerDen));
        require(_verify(proof, report.denRoot, leaf), "Distributor: bad proof");

        uint256 amount = (workerDen * report.poolAllocation) / report.totalDen;
        require(amount > 0, "Distributor: zero payout");

        // Hard cap: a period can never pay out more than its snapshotted
        // allocation, even if the reported root/totalDen is wrong. Bounds a bad
        // report's blast radius to that one period's budget.
        uint256 newPaid = paidPerPeriod[periodId] + amount;
        require(newPaid <= report.poolAllocation, "Distributor: period overpay");

        periodClaimed[periodId][worker] = true; // CEI: state before transfer
        paidPerPeriod[periodId] = newPaid;
        totalPaidOut += amount;
        payoutToken.safeTransfer(worker, amount);

        emit Claimed(periodId, worker, msg.sender, workerDen, amount);
    }

    /**
     * @notice Settle many workers in one tx. Invalid rows (bad proof, already
     *         claimed, zero amount) are skipped so one bad entry can't fail the
     *         batch. Funded periods guarantee valid rows are payable.
     */
    function claimBatch(
        uint256 periodId,
        address[] calldata workers,
        uint256[] calldata den,
        bytes32[][] calldata proofs
    ) external whenNotPaused nonReentrant {
        require(
            workers.length == den.length && workers.length == proofs.length,
            "Distributor: length mismatch"
        );
        require(workers.length <= MAX_BATCH, "Distributor: batch too large");

        Report storage report = reports[periodId];
        require(report.denRoot != bytes32(0), "Distributor: not reported");

        uint256 cap = report.poolAllocation;
        uint256 paid = paidPerPeriod[periodId];
        uint256 added;
        for (uint256 i = 0; i < workers.length; i++) {
            address worker = workers[i];
            uint256 workerDen = den[i];
            if (worker == address(0) || workerDen == 0) continue;
            if (periodClaimed[periodId][worker]) continue;

            bytes32 leaf = keccak256(abi.encodePacked(worker, workerDen));
            if (!_verify(proofs[i], report.denRoot, leaf)) continue;

            uint256 amount = (workerDen * report.poolAllocation) / report.totalDen;
            if (amount == 0) continue;

            // Same hard per-period cap as claim(); fail loud on a corrupt root
            // rather than overpay into another period's funds.
            require(paid + amount <= cap, "Distributor: period overpay");

            periodClaimed[periodId][worker] = true;
            paid += amount;
            added += amount;
            payoutToken.safeTransfer(worker, amount);

            emit Claimed(periodId, worker, msg.sender, workerDen, amount);
        }
        paidPerPeriod[periodId] = paid;
        totalPaidOut += added;
    }

    // ============ VIEWS ============

    function poolBalance() public view returns (uint256) {
        return payoutToken.balanceOf(address(this));
    }

    function previewClaim(uint256 periodId, address worker, uint256 workerDen, bytes32[] calldata proof)
        external
        view
        returns (uint256 amount, bool valid)
    {
        Report storage report = reports[periodId];
        if (report.denRoot == bytes32(0)) return (0, false);
        if (periodClaimed[periodId][worker]) return (0, false);
        if (workerDen == 0 || report.totalDen == 0) return (0, false);

        bytes32 leaf = keccak256(abi.encodePacked(worker, workerDen));
        if (!_verify(proof, report.denRoot, leaf)) return (0, false);

        amount = (workerDen * report.poolAllocation) / report.totalDen;
        valid = amount > 0;
    }

    function isClaimed(uint256 periodId, address worker) external view returns (bool) {
        return periodClaimed[periodId][worker];
    }

    function isReported(uint256 periodId) external view returns (bool) {
        return reports[periodId].denRoot != bytes32(0);
    }

    // ============ INTERNAL ============

    /// @dev Sorted-pair Merkle verification — identical convention to PaymentRouter.
    function _verify(bytes32[] calldata proof, bytes32 root, bytes32 leaf)
        internal
        pure
        returns (bool)
    {
        bytes32 computed = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 sibling = proof[i];
            computed = computed <= sibling
                ? keccak256(abi.encodePacked(computed, sibling))
                : keccak256(abi.encodePacked(sibling, computed));
        }
        return computed == root;
    }
}
