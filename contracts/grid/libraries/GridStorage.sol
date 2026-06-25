// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title GridStorage
 * @dev Shared storage for all Grid modules (EIP-2535 AppStorage pattern)
 */
library GridStorage {
    bytes32 constant STORAGE_POSITION = keccak256("aipg.grid.storage");

    // ============ ENUMS ============
    enum ModelType {
        TEXT_MODEL,
        IMAGE_MODEL,
        VIDEO_MODEL
    }

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
        // APPEND-ONLY (added 2026-06): timestamp at which a requested unbond can
        // be withdrawn. 0 = no unbond in progress. Appended to the END of the
        // struct so existing workers (whose slot for this field is zero) and the
        // already-deployed facets that read the 7-field struct are unaffected —
        // each Worker lives at its own keccak-spaced region, so a trailing field
        // just consumes the next, previously-zero slot. NEVER reorder.
        uint256 unbondingAt;
    }

    struct DenReport {
        uint256 periodId;
        bytes32 denRoot;
        uint256 totalDen;
        uint256 poolAllocation;
        uint256 timestamp;
        address reporter;
        string ipfsUri; // ipfs://<cid> pointing to full [worker, den] JSON for off-chain audit
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

        // ====================================================================
        // APPEND-ONLY ZONE (EIP-2535)
        // Everything below was added AFTER the Diamond was deployed to Base
        // mainnet. The live facets were compiled against the layout ending at
        // `paused` above, so new fields MUST be appended here and NEVER
        // inserted earlier — inserting earlier shifts every subsequent slot
        // and corrupts state the live facets read/write. Same rule for any
        // future additions: append at the bottom, never reorder.
        // ====================================================================

        // === REWARD POOL (added 2026-06) ===
        uint256 totalDeposited;
        uint256 totalPaidOut;
        uint256 periodAllocation; // AIPG released per period
        uint256 periodLengthSeconds; // default 86400 (1 day) if zero

        // === DEN REPORTS (added 2026-06) ===
        mapping(uint256 => DenReport) periodReports;
        mapping(uint256 => mapping(address => bool)) periodClaimed;

        // === MODEL DEN MULTIPLIER (added 2026-06) ===
        // Per-model reward "size" multiplier, scaled x1000 (e.g. a 27B model
        // => 27000). Sourced on-chain so den pricing is transparent and
        // governable; the off-chain grid caches this on an interval and never
        // derives a multiplier from the model name. 0 = unset (grid applies its
        // conservative DEFAULT_MULTIPLIER). Appended per the rule above.
        mapping(uint256 => uint256) denMultiplierE3;

        // === WORKER UNBONDING COOLDOWN (added 2026-06) ===
        // Seconds a worker must wait between requesting an unbond and being able
        // to withdraw their bond. The cooldown is what makes bonds slashable:
        // misbehavior detected after a worker quits can still be punished while
        // funds sit in the cooldown. 0 = use DEFAULT_UNBONDING_PERIOD. Appended.
        uint256 unbondingPeriodSeconds;

        // === PAYMENT ROUTER PER-PERIOD CAPS (added 2026-06) ===
        // Tracks how much each den report has paid so a corrupt or compromised
        // report cannot pay more than its snapshotted poolAllocation.
        mapping(uint256 => uint256) paidPerPeriod;
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
    bytes32 constant REWARD_ADMIN_ROLE = keccak256("REWARD_ADMIN_ROLE");
    bytes32 constant REPORTER_ROLE = keccak256("REPORTER_ROLE");
    // Can slash bonded workers (forged receipts, repeated bad results). Held by
    // the grid's settlement/enforcement key, never by the hot request path.
    bytes32 constant SLASHER_ROLE = keccak256("SLASHER_ROLE");
}
