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
 * @dev Worker registration, bonding, and job tracking
 */
contract WorkerRegistry {
    using GridStorage for GridStorage.AppStorage;

    event WorkerRegistered(address indexed worker, uint256 bondAmount);
    event WorkerBondIncreased(address indexed worker, uint256 additionalBond);
    event WorkerUnbonded(address indexed worker, uint256 amountReturned);
    event WorkerSlashed(address indexed worker, uint256 slashedAmount);
    event JobCompleted(address indexed worker, uint256 jobCount, uint256 rewardAmount);
    event MinBondUpdated(uint256 oldMin, uint256 newMin);

    modifier onlyAdmin() {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        require(s.roles[GridStorage.ADMIN_ROLE][msg.sender], "WorkerRegistry: not admin");
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

        require(
            IERC20(s.aipgToken).transferFrom(msg.sender, address(this), bondAmount),
            "WorkerRegistry: transfer failed"
        );

        GridStorage.Worker storage w = s.workers[msg.sender];
        w.workerAddress = msg.sender;
        w.bondAmount = bondAmount;
        w.registeredAt = block.timestamp;
        w.isActive = true;

        s.workerList.push(msg.sender);
        s.totalBonded += bondAmount;

        emit WorkerRegistered(msg.sender, bondAmount);
    }

    function unbond() external notPaused {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        GridStorage.Worker storage w = s.workers[msg.sender];
        require(w.isActive, "WorkerRegistry: not registered");
        require(!w.isSlashed, "WorkerRegistry: slashed");

        uint256 returnAmount = w.bondAmount;
        w.bondAmount = 0;
        w.isActive = false;
        s.totalBonded -= returnAmount;

        require(
            IERC20(s.aipgToken).transfer(msg.sender, returnAmount),
            "WorkerRegistry: transfer failed"
        );

        emit WorkerUnbonded(msg.sender, returnAmount);
    }

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
}

