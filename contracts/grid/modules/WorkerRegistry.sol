// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../libraries/GridStorage.sol";
import "../libraries/LibGrid.sol";

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

/**
 * @title WorkerRegistry
 * @dev Worker registration, bonding, slashing, and job tracking.
 *
 *      Bonding model
 *      -------------
 *      A worker locks AIPG into the diamond to register. Misbehavior (forged
 *      receipts, repeated bad/garbage results) can be punished by slashing part
 *      or all of that bond. The bond is what gives the slash teeth — without it
 *      a free worker has nothing to lose.
 *
 *      The slash-escape hole
 *      ---------------------
 *      The original facet let a worker `unbond()` and get its full bond back in
 *      the SAME transaction. A worker could misbehave and instantly pull its
 *      bond before anyone slashed it. This version closes that: unbonding is now
 *      two steps separated by a cooldown —
 *
 *          unbond()        -> marks the worker inactive and starts the cooldown
 *                             (bond stays locked, still slashable)
 *          withdrawBond()  -> after the cooldown elapses, returns the bond
 *
 *      During the cooldown the bond is fully slashable, so a worker can't run.
 *
 *      Slash destination
 *      -----------------
 *      Slashed AIPG is already sitting in the diamond (bonds transfer in on
 *      register). Slashing routes it to the reward pool by internal accounting
 *      only — `totalBonded -= amount; totalDeposited += amount` — with NO token
 *      transfer. The punished worker's stake becomes reward budget for honest
 *      workers. (Same diamond balance backs both bonds and the reward pool.)
 */
contract WorkerRegistry {
    using GridStorage for GridStorage.AppStorage;

    // Default cooldown if governance hasn't set one. 7 days gives the grid time
    // to detect and act on misbehavior surfaced after a worker requests unbond.
    uint256 constant DEFAULT_UNBONDING_PERIOD = 7 days;

    event WorkerRegistered(address indexed worker, uint256 bondAmount);
    event WorkerBondIncreased(address indexed worker, uint256 additionalBond);
    event UnbondRequested(address indexed worker, uint256 amount, uint256 unbondingAt);
    event UnbondCancelled(address indexed worker);
    event BondWithdrawn(address indexed worker, uint256 amount);
    event WorkerSlashed(address indexed worker, uint256 slashedAmount, string reason);
    event JobCompleted(address indexed worker, uint256 jobCount, uint256 rewardAmount);
    event MinBondUpdated(uint256 oldMin, uint256 newMin);
    event UnbondingPeriodUpdated(uint256 oldSeconds, uint256 newSeconds);

    modifier onlyAdmin() {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        require(s.roles[GridStorage.ADMIN_ROLE][msg.sender], "WorkerRegistry: not admin");
        _;
    }

    modifier onlySlasher() {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        require(
            s.roles[GridStorage.SLASHER_ROLE][msg.sender]
                || s.roles[GridStorage.ADMIN_ROLE][msg.sender],
            "WorkerRegistry: not slasher"
        );
        _;
    }

    modifier notPaused() {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        require(!s.paused, "WorkerRegistry: paused");
        _;
    }

    // ============ REGISTRATION / BONDING ============

    function registerWorker(uint256 bondAmount) external notPaused {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        require(!s.workers[msg.sender].isActive, "WorkerRegistry: already registered");
        require(bondAmount >= s.minBondAmount, "WorkerRegistry: insufficient bond");
        require(s.aipgToken != address(0), "WorkerRegistry: token not set");

        GridStorage.Worker storage w = s.workers[msg.sender];
        // A worker mid-cooldown (inactive but bond still locked) can't stack a
        // second bond — they must withdraw first. New workers have bondAmount 0.
        require(w.bondAmount == 0, "WorkerRegistry: bond in cooldown");

        require(
            IERC20(s.aipgToken).transferFrom(msg.sender, address(this), bondAmount),
            "WorkerRegistry: transfer failed"
        );

        w.workerAddress = msg.sender;
        w.bondAmount = bondAmount;
        w.registeredAt = block.timestamp;
        w.isActive = true;
        w.isSlashed = false;
        w.unbondingAt = 0;

        s.workerList.push(msg.sender);
        s.totalBonded += bondAmount;

        emit WorkerRegistered(msg.sender, bondAmount);
    }

    /**
     * @dev Start unbonding. Marks the worker inactive (grid stops dispatching to
     *      it) and begins the cooldown. The bond stays locked and fully slashable
     *      until withdrawBond() is called after the cooldown. Replaces the old
     *      instant-return unbond() (same selector) — existing callers now get the
     *      safe two-step flow instead of an immediate payout.
     */
    function unbond() external notPaused {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        GridStorage.Worker storage w = s.workers[msg.sender];
        require(w.isActive, "WorkerRegistry: not registered");
        require(!w.isSlashed, "WorkerRegistry: slashed");
        require(w.unbondingAt == 0, "WorkerRegistry: already unbonding");

        w.isActive = false;
        uint256 period =
            s.unbondingPeriodSeconds == 0 ? DEFAULT_UNBONDING_PERIOD : s.unbondingPeriodSeconds;
        w.unbondingAt = block.timestamp + period;

        emit UnbondRequested(msg.sender, w.bondAmount, w.unbondingAt);
    }

    /**
     * @dev Abort an in-progress unbond and return to active service. Only valid
     *      while still bonded and not slashed.
     */
    function cancelUnbond() external notPaused {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        GridStorage.Worker storage w = s.workers[msg.sender];
        require(w.unbondingAt != 0, "WorkerRegistry: not unbonding");
        require(!w.isSlashed, "WorkerRegistry: slashed");
        require(w.bondAmount >= s.minBondAmount, "WorkerRegistry: bond below min");

        w.unbondingAt = 0;
        w.isActive = true;

        emit UnbondCancelled(msg.sender);
    }

    /**
     * @dev Withdraw the bond after the cooldown has elapsed. CEI: state is
     *      cleared before the external transfer, so no reentrancy guard needed.
     */
    function withdrawBond() external notPaused {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        GridStorage.Worker storage w = s.workers[msg.sender];
        require(w.unbondingAt != 0, "WorkerRegistry: no unbond requested");
        require(block.timestamp >= w.unbondingAt, "WorkerRegistry: cooldown active");

        uint256 amount = w.bondAmount;
        require(amount > 0, "WorkerRegistry: nothing to withdraw");

        w.bondAmount = 0;
        w.isActive = false;
        w.unbondingAt = 0;
        s.totalBonded -= amount;

        require(IERC20(s.aipgToken).transfer(msg.sender, amount), "WorkerRegistry: transfer failed");

        emit BondWithdrawn(msg.sender, amount);
    }

    // ============ SLASHING ============

    /**
     * @dev Slash a worker's bond. Callable by SLASHER_ROLE (the grid's
     *      settlement/enforcement key) or ADMIN_ROLE. Works whether or not the
     *      worker is mid-unbond — that's the point of the cooldown.
     *
     *      Slashed AIPG is routed to the reward pool by accounting only (the
     *      tokens are already in the diamond): totalBonded down, totalDeposited
     *      up. If the remaining bond drops below the minimum, the worker is
     *      deactivated and flagged slashed.
     *
     * @param worker  Worker to slash.
     * @param amount  AIPG to slash (<= current bond).
     * @param reason  Short human-readable reason, event-logged for auditability.
     */
    function slash(address worker, uint256 amount, string calldata reason) external onlySlasher {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        GridStorage.Worker storage w = s.workers[worker];
        require(w.workerAddress == worker && worker != address(0), "WorkerRegistry: unknown worker");
        require(amount > 0, "WorkerRegistry: zero slash");
        require(amount <= w.bondAmount, "WorkerRegistry: slash exceeds bond");

        uint256 remaining = w.bondAmount - amount;
        uint256 slashedAmount = amount;
        if (remaining > 0 && remaining < s.minBondAmount) {
            // A below-min remainder cannot be used to re-register or return to
            // service, so classify it as slashed instead of stranding dust.
            slashedAmount = w.bondAmount;
            remaining = 0;
        }

        w.bondAmount = remaining;
        s.totalBonded -= slashedAmount;
        // Route to the reward pool by internal accounting — funds already held.
        s.totalDeposited += slashedAmount;

        if (remaining == 0 || remaining < s.minBondAmount) {
            w.isActive = false;
            w.isSlashed = true;
            w.unbondingAt = 0;
        }

        emit WorkerSlashed(worker, slashedAmount, reason);
    }

    // ============ ADMIN ============

    function setMinBond(uint256 newMin) external onlyAdmin {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        uint256 old = s.minBondAmount;
        s.minBondAmount = newMin;
        emit MinBondUpdated(old, newMin);
    }

    function setUnbondingPeriod(uint256 newSeconds) external onlyAdmin {
        require(newSeconds <= 30 days, "WorkerRegistry: cooldown too long");
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        uint256 old = s.unbondingPeriodSeconds;
        s.unbondingPeriodSeconds = newSeconds;
        emit UnbondingPeriodUpdated(old, newSeconds);
    }

    // ============ VIEWS ============

    function getWorker(address worker) external view returns (GridStorage.Worker memory) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        return s.workers[worker];
    }

    function isWorkerActive(address worker) external view returns (bool) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        return s.workers[worker].isActive;
    }

    function getTotalBonded() external view returns (uint256) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        return s.totalBonded;
    }

    function getMinBond() external view returns (uint256) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        return s.minBondAmount;
    }

    function unbondingPeriod() external view returns (uint256) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        return s.unbondingPeriodSeconds == 0 ? DEFAULT_UNBONDING_PERIOD : s.unbondingPeriodSeconds;
    }

    /**
     * @dev Unbond status for a worker. unbondingAt == 0 means no unbond is in
     *      progress; otherwise `withdrawable` is true once the cooldown elapses.
     */
    function getUnbondInfo(address worker)
        external
        view
        returns (uint256 unbondingAt, uint256 bondAmount, bool withdrawable)
    {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        GridStorage.Worker storage w = s.workers[worker];
        unbondingAt = w.unbondingAt;
        bondAmount = w.bondAmount;
        withdrawable = w.unbondingAt != 0 && block.timestamp >= w.unbondingAt && w.bondAmount > 0;
    }
}
