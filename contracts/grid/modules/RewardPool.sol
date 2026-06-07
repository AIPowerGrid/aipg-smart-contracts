// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../libraries/GridStorage.sol";

interface IERC20RewardPool {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title RewardPool
 * @dev Holds AIPG that funds worker payouts. Treasury / paid users / slashing all
 *      deposit here. PaymentRouter pulls from here when workers claim.
 *
 *      The per-period allocation is set separately — pool balance and payout rate
 *      are intentionally decoupled so the team can pre-fund and let the contract
 *      drip out at whatever cadence makes sense.
 */
contract RewardPool {
    using GridStorage for GridStorage.AppStorage;

    event Deposited(address indexed from, uint256 amount, uint256 newBalance);
    event PeriodAllocationUpdated(uint256 oldAllocation, uint256 newAllocation, string reason);
    event PeriodLengthUpdated(uint256 oldSeconds, uint256 newSeconds);

    modifier onlyRewardAdmin() {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        require(
            s.roles[GridStorage.REWARD_ADMIN_ROLE][msg.sender] ||
            s.roles[GridStorage.ADMIN_ROLE][msg.sender],
            "RewardPool: not reward admin"
        );
        _;
    }

    modifier notPaused() {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        require(!s.paused, "RewardPool: paused");
        _;
    }

    /**
     * @dev Anyone can fund the pool. Treasury wallet, paid users routing fees,
     *      slashed validator bonds — same plumbing.
     */
    function depositRewards(uint256 amount) external notPaused {
        require(amount > 0, "RewardPool: zero amount");
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        require(s.aipgToken != address(0), "RewardPool: token not set");

        require(
            IERC20RewardPool(s.aipgToken).transferFrom(msg.sender, address(this), amount),
            "RewardPool: transfer failed"
        );

        s.totalDeposited += amount;
        emit Deposited(msg.sender, amount, _poolBalance(s));
    }

    /**
     * @dev Set the per-period AIPG allocation. Takes effect for periods reported
     *      AFTER this call — already-reported periods keep their snapshotted allocation.
     *
     * @param newAllocation New AIPG amount to release per period.
     * @param reason        Short human-readable reason for the change (event-logged).
     */
    function setPeriodAllocation(uint256 newAllocation, string calldata reason) external onlyRewardAdmin {
        GridStorage.AppStorage storage s = GridStorage.appStorage();

        // Sanity bound: don't allow more than 10x change in a single call.
        // Forces a multi-step ramp if the team wants a big move. Cheap guardrail
        // against fat-finger / compromised-key disasters.
        //
        // Two exceptions skip the bound:
        //   - First-ever set (current == 0): no prior rate to compare to.
        //   - Halt (newAllocation == 0): emergency stop is always allowed.
        //     Re-enabling from zero is also unbounded — same as a fresh start.
        uint256 current = s.periodAllocation;
        if (current > 0 && newAllocation > 0) {
            require(newAllocation <= current * 10, "RewardPool: change too large");
            require(newAllocation * 10 >= current, "RewardPool: change too small");
        }

        s.periodAllocation = newAllocation;
        emit PeriodAllocationUpdated(current, newAllocation, reason);
    }

    /**
     * @dev Period length in seconds. Default 3600 (1 hour). Changing this affects
     *      future periods only.
     */
    function setPeriodLength(uint256 newSeconds) external onlyRewardAdmin {
        require(newSeconds >= 60 && newSeconds <= 7 days, "RewardPool: bad period");
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        uint256 old = s.periodLengthSeconds;
        s.periodLengthSeconds = newSeconds;
        emit PeriodLengthUpdated(old, newSeconds);
    }

    // ============ VIEWS ============

    function poolBalance() external view returns (uint256) {
        return _poolBalance(GridStorage.appStorage());
    }

    function totalDeposited() external view returns (uint256) {
        return GridStorage.appStorage().totalDeposited;
    }

    function totalPaidOut() external view returns (uint256) {
        return GridStorage.appStorage().totalPaidOut;
    }

    function periodAllocation() external view returns (uint256) {
        return GridStorage.appStorage().periodAllocation;
    }

    function periodLengthSeconds() external view returns (uint256) {
        uint256 length = GridStorage.appStorage().periodLengthSeconds;
        return length == 0 ? 86400 : length;
    }

    function currentPeriodId() external view returns (uint256) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        uint256 length = s.periodLengthSeconds == 0 ? 86400 : s.periodLengthSeconds;
        return block.timestamp / length;
    }

    function _poolBalance(GridStorage.AppStorage storage s) internal view returns (uint256) {
        return IERC20RewardPool(s.aipgToken).balanceOf(address(this));
    }
}
