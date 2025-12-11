// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../libraries/GridStorage.sol";
import "../libraries/LibGrid.sol";

/**
 * @title JobAnchor
 * @dev Daily anchoring of job receipts for off-chain verification
 */
contract JobAnchor {
    using GridStorage for GridStorage.AppStorage;

    // ============ EVENTS ============
    
    event DayAnchored(uint256 indexed day, bytes32 merkleRoot, uint256 totalJobs, uint256 totalRewards);
    event JobIdAnchored(bytes32 indexed jobId);

    // ============ MODIFIERS ============
    
    modifier onlyAnchorer() {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        require(
            s.roles[GridStorage.ANCHOR_ROLE][msg.sender] ||
            s.roles[GridStorage.ADMIN_ROLE][msg.sender],
            "JobAnchor: not anchorer"
        );
        _;
    }

    modifier notPaused() {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        require(!s.paused, "JobAnchor: paused");
        _;
    }

    // ============ ANCHORING ============
    
    function anchorDay(
        uint256 day,
        bytes32 merkleRoot,
        uint256 totalJobs,
        uint256 totalRewards
    ) external onlyAnchorer notPaused {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        
        require(merkleRoot != bytes32(0), "JobAnchor: empty root");
        require(s.dailyAnchors[day].merkleRoot == bytes32(0), "JobAnchor: day exists");

        GridStorage.DailyAnchor storage anchor = s.dailyAnchors[day];
        anchor.day = day;
        anchor.merkleRoot = merkleRoot;
        anchor.totalJobs = totalJobs;
        anchor.totalRewards = totalRewards;
        anchor.timestamp = block.timestamp;
        anchor.anchorer = msg.sender;

        s.totalAnchoredJobs += totalJobs;
        s.totalAnchoredRewards += totalRewards;

        emit DayAnchored(day, merkleRoot, totalJobs, totalRewards);
    }

    function anchorJobIds(bytes32[] calldata jobIds) external onlyAnchorer notPaused {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        
        for (uint256 i = 0; i < jobIds.length; i++) {
            if (!s.anchoredJobIds[jobIds[i]]) {
                s.anchoredJobIds[jobIds[i]] = true;
                emit JobIdAnchored(jobIds[i]);
            }
        }
    }

    function recordWorkerJobDay(address worker, uint256 day) external onlyAnchorer notPaused {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        s.workerJobDays[worker].push(day);
    }

    // ============ VIEWS ============
    
    function getDayAnchor(uint256 day) external view returns (GridStorage.DailyAnchor memory) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        return s.dailyAnchors[day];
    }

    function isJobAnchored(bytes32 jobId) external view returns (bool) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        return s.anchoredJobIds[jobId];
    }

    function getWorkerJobDays(address worker) external view returns (uint256[] memory) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        return s.workerJobDays[worker];
    }

    function getTotalAnchoredJobs() external view returns (uint256) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        return s.totalAnchoredJobs;
    }

    function getTotalAnchoredRewards() external view returns (uint256) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        return s.totalAnchoredRewards;
    }

    function getCurrentDay() external view returns (uint256) {
        return block.timestamp / 1 days;
    }

    function verifyJobInDay(
        uint256 day,
        bytes32 jobId,
        bytes32[] calldata proof
    ) external view returns (bool) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        bytes32 root = s.dailyAnchors[day].merkleRoot;
        
        if (root == bytes32(0)) return false;
        
        bytes32 computedHash = jobId;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            if (computedHash <= proofElement) {
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }
        
        return computedHash == root;
    }
}

