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
 * @dev Worker registration, cooldown-backed bonding, and reviewed slashing.
 */
contract WorkerRegistry {
    using GridStorage for GridStorage.AppStorage;

    uint256 constant DEFAULT_UNBONDING_PERIOD = 7 days;
    uint256 constant MIN_CUSTOM_UNBONDING_PERIOD = 1 days;
    uint256 constant MAX_UNBONDING_PERIOD = 30 days;
    uint256 constant MAX_SLASH_REASON_BYTES = 256;

    event WorkerRegistered(address indexed worker, uint256 bondAmount);
    event WorkerBondIncreased(address indexed worker, uint256 additionalBond);
    event UnbondRequested(address indexed worker, uint256 amount, uint256 unbondingAt);
    event UnbondCancelled(address indexed worker);
    event BondWithdrawn(address indexed worker, uint256 amount);
    event WorkerSlashed(
        address indexed worker, bytes32 indexed evidenceId, uint256 slashedAmount, string reason
    );
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
        require(s.roles[GridStorage.SLASHER_ROLE][msg.sender], "WorkerRegistry: not slasher");
        _;
    }

    modifier notPaused() {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        require(!s.paused, "WorkerRegistry: paused");
        _;
    }

    function registerWorker(uint256 bondAmount) external notPaused {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        require(!s.workers[msg.sender].isActive, "WorkerRegistry: already registered");
        require(bondAmount >= s.minBondAmount, "WorkerRegistry: insufficient bond");
        require(s.aipgToken != address(0), "WorkerRegistry: token not set");

        GridStorage.Worker storage w = s.workers[msg.sender];
        require(w.bondAmount == 0, "WorkerRegistry: bond in cooldown");

        bool firstRegistration = w.workerAddress == address(0);
        w.workerAddress = msg.sender;
        w.bondAmount = bondAmount;
        w.registeredAt = block.timestamp;
        w.isActive = true;
        w.isSlashed = false;
        w.unbondingAt = 0;

        // Only enumerate once — a re-register after unbond must not push a
        // duplicate entry into workerList.
        if (firstRegistration) {
            s.workerList.push(msg.sender);
        }
        s.totalBonded += bondAmount;

        require(
            IERC20(s.aipgToken).transferFrom(msg.sender, address(this), bondAmount),
            "WorkerRegistry: transfer failed"
        );

        emit WorkerRegistered(msg.sender, bondAmount);
    }

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

    function cancelUnbond() external {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        GridStorage.Worker storage w = s.workers[msg.sender];
        require(w.unbondingAt != 0, "WorkerRegistry: not unbonding");
        require(!w.isSlashed, "WorkerRegistry: slashed");
        require(w.bondAmount >= s.minBondAmount, "WorkerRegistry: bond below min");

        w.unbondingAt = 0;
        w.isActive = true;

        emit UnbondCancelled(msg.sender);
    }

    function withdrawBond() external {
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

    function slash(address worker, uint256 amount, bytes32 evidenceId, string calldata reason)
        external
        onlySlasher
    {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        GridStorage.Worker storage w = s.workers[worker];
        require(worker != address(0) && w.workerAddress == worker, "WorkerRegistry: unknown worker");
        require(amount > 0, "WorkerRegistry: zero slash");
        require(amount <= w.bondAmount, "WorkerRegistry: slash exceeds bond");
        require(evidenceId != bytes32(0), "WorkerRegistry: zero evidence");
        require(!s.usedSlashEvidence[evidenceId], "WorkerRegistry: evidence used");
        require(bytes(reason).length <= MAX_SLASH_REASON_BYTES, "WorkerRegistry: reason too long");

        uint256 remaining = w.bondAmount - amount;
        uint256 slashedAmount = amount;
        if (remaining > 0 && remaining < s.minBondAmount) {
            slashedAmount = w.bondAmount;
            remaining = 0;
        }

        s.usedSlashEvidence[evidenceId] = true;
        w.bondAmount = remaining;
        s.totalBonded -= slashedAmount;
        s.totalDeposited += slashedAmount;
        if (remaining == 0) {
            w.isActive = false;
            w.isSlashed = true;
            w.unbondingAt = 0;
        }

        emit WorkerSlashed(worker, evidenceId, slashedAmount, reason);
    }

    function setMinBond(uint256 newMin) external onlyAdmin {
        require(newMin > 0, "WorkerRegistry: zero min bond");
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        uint256 oldMin = s.minBondAmount;
        s.minBondAmount = newMin;
        emit MinBondUpdated(oldMin, newMin);
    }

    function setUnbondingPeriod(uint256 newSeconds) external onlyAdmin {
        require(
            newSeconds == 0
                || (newSeconds >= MIN_CUSTOM_UNBONDING_PERIOD
                    && newSeconds <= MAX_UNBONDING_PERIOD),
            "WorkerRegistry: invalid cooldown"
        );
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        uint256 oldSeconds = s.unbondingPeriodSeconds;
        s.unbondingPeriodSeconds = newSeconds;
        emit UnbondingPeriodUpdated(oldSeconds, newSeconds);
    }

    function getWorker(address worker) external view returns (GridStorage.Worker memory) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        return s.workers[worker];
    }

    /// @notice Number of distinct workers ever enumerated. A worker appears once
    ///         even across unbond/re-register (no duplicate list entries).
    function getWorkerCount() external view returns (uint256) {
        return GridStorage.appStorage().workerList.length;
    }

    function getWorkerAt(uint256 index) external view returns (address) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        require(index < s.workerList.length, "WorkerRegistry: index out of bounds");
        return s.workerList[index];
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

    function isSlashEvidenceUsed(bytes32 evidenceId) external view returns (bool) {
        return GridStorage.appStorage().usedSlashEvidence[evidenceId];
    }

    function unbondingPeriod() external view returns (uint256) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        return s.unbondingPeriodSeconds == 0 ? DEFAULT_UNBONDING_PERIOD : s.unbondingPeriodSeconds;
    }

    function getUnbondInfo(address worker)
        external
        view
        returns (uint256 unbondingAt, uint256 bondAmount, bool withdrawable)
    {
        GridStorage.Worker storage w = GridStorage.appStorage().workers[worker];
        unbondingAt = w.unbondingAt;
        bondAmount = w.bondAmount;
        withdrawable = unbondingAt != 0 && block.timestamp >= unbondingAt && bondAmount > 0;
    }
}
