// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title GridStorage
 * @dev Shared storage for all Grid modules (EIP-2535 AppStorage pattern)
 */
library GridStorage {
    bytes32 constant STORAGE_POSITION = keccak256("aipg.grid.storage");

    // ============ ENUMS ============
    enum ModelType { TEXT_MODEL, IMAGE_MODEL, VIDEO_MODEL }

    // ============ STRUCTS ============
    
    struct Model {
        bytes32 modelHash;
        ModelType modelType;
        string fileName;
        string name;
        string version;
        string ipfsCid;
        string downloadUrl;
        uint256 sizeBytes;
        string quantization;
        string format;
        uint32 vramMB;
        string baseModel;
        bool inpainting;
        bool img2img;
        bool controlnet;
        bool lora;
        bool isActive;
        bool isNSFW;
        uint256 timestamp;
        address creator;
    }

    struct ModelConstraints {
        uint16 stepsMin;
        uint16 stepsMax;
        uint16 cfgMinTenths;
        uint16 cfgMaxTenths;
        uint8 clipSkip;
        bytes32[] allowedSamplers;
        bytes32[] allowedSchedulers;
        bool exists;
    }

    struct Recipe {
        uint256 recipeId;
        bytes32 recipeRoot;
        bytes workflowData;
        address creator;
        bool canCreateNFTs;
        bool isPublic;
        uint8 compression;
        uint256 createdAt;
        string name;
        string description;
    }

    struct DailyAnchor {
        uint256 day;
        bytes32 merkleRoot;
        uint256 totalJobs;
        uint256 totalRewards;
        uint256 timestamp;
        address anchorer;
    }

    struct Worker {
        address workerAddress;
        uint256 bondAmount;
        uint256 totalJobsCompleted;
        uint256 totalRewardsEarned;
        uint256 registeredAt;
        bool isActive;
        bool isSlashed;
    }

    // ============ APP STORAGE ============
    
    struct AppStorage {
        // === ROLES (shared across all modules) ===
        mapping(bytes32 => mapping(address => bool)) roles;
        mapping(bytes32 => bytes32) roleAdmin;
        
        // === MODEL VAULT ===
        uint256 modelIdCounter;
        mapping(uint256 => Model) models;
        mapping(bytes32 => uint256) hashToModelId;
        mapping(bytes32 => ModelConstraints) modelConstraints;
        
        // === RECIPE VAULT ===
        uint256 nextRecipeId;
        uint256 totalRecipes;
        mapping(uint256 => Recipe) recipes;
        mapping(bytes32 => uint256) recipeRootToId;
        mapping(address => uint256[]) creatorRecipes;
        uint256 maxWorkflowBytes;
        
        // === JOB ANCHOR ===
        mapping(uint256 => DailyAnchor) dailyAnchors;
        mapping(bytes32 => bool) anchoredJobIds;
        mapping(address => uint256[]) workerJobDays;
        uint256 totalAnchoredJobs;
        uint256 totalAnchoredRewards;
        
        // === WORKER REGISTRY ===
        mapping(address => Worker) workers;
        address[] workerList;
        uint256 totalBonded;
        uint256 minBondAmount;
        
        // === SHARED CONFIG ===
        address aipgToken;
        address stakingVault;
        bool paused;
    }

    // ============ STORAGE ACCESS ============
    
    function appStorage() internal pure returns (AppStorage storage s) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }

    // ============ ROLE CONSTANTS ============
    
    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");
    bytes32 constant ANCHOR_ROLE = keccak256("ANCHOR_ROLE");
    bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
}
