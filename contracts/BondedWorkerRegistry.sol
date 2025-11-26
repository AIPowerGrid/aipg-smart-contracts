// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title BondedWorkerRegistry
 * @dev Registry for bonded workers who stake AIPG tokens
 * @notice Only bonded workers are registered on-chain for slashing/trust mechanisms
 */
contract BondedWorkerRegistry is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ============ ROLES ============
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant REWARD_MANAGER_ROLE = keccak256("REWARD_MANAGER_ROLE");

    // ============ STATE ============
    IERC20 public immutable aipgToken;
    
    // Worker information
    struct WorkerInfo {
        uint256 stakeAmount;           // Amount of AIPG staked
        bytes32[] supportedModels;     // Array of model hashes this worker supports
        bool isActive;                 // Whether worker is active
        uint256 registrationTime;      // When worker registered
        uint256 lastActivity;          // Last activity timestamp
        string workerId;               // Off-chain worker ID
        uint256 totalJobsCompleted;    // Total jobs completed
        uint256 totalRewardsEarned;    // Total AIPG rewards earned
    }

    // Storage
    mapping(address => WorkerInfo) public workers;
    mapping(address => bool) public isBondedWorker;
    mapping(bytes32 => address[]) public modelToWorkers;  // modelHash => worker addresses
    mapping(string => address) public workerIdToAddress;  // workerId => address
    
    address[] public allWorkers;
    uint256 public totalStaked;
    uint256 public minimumStake;
    uint256 public maximumStake;

    // ============ EVENTS ============
    event WorkerRegistered(
        address indexed worker,
        uint256 stakeAmount,
        bytes32[] supportedModels,
        string workerId
    );
    
    event WorkerUnregistered(address indexed worker);
    event StakeIncreased(address indexed worker, uint256 additionalAmount);
    event StakeDecreased(address indexed worker, uint256 decreasedAmount);
    event ModelsUpdated(address indexed worker, bytes32[] newModels);
    event WorkerSlashed(address indexed worker, uint256 slashedAmount, string reason);
    event ActivityUpdated(address indexed worker, uint256 timestamp);
    event JobCompleted(address indexed worker, uint256 rewardAmount);
    event MinimumStakeUpdated(uint256 oldValue, uint256 newValue);
    event MaximumStakeUpdated(uint256 oldValue, uint256 newValue);

    // ============ MODIFIERS ============
    modifier onlyBondedWorker() {
        require(isBondedWorker[msg.sender], "BondedWorkerRegistry: not a bonded worker");
        _;
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "BondedWorkerRegistry: caller is not an admin");
        _;
    }

    modifier onlyRewardManager() {
        require(hasRole(REWARD_MANAGER_ROLE, msg.sender), "BondedWorkerRegistry: caller is not reward manager");
        _;
    }

    // ============ CONSTRUCTOR ============
    constructor(address _aipgToken, uint256 _minimumStake, uint256 _maximumStake) {
        require(_aipgToken != address(0), "BondedWorkerRegistry: invalid token address");
        require(_minimumStake > 0, "BondedWorkerRegistry: invalid minimum stake");
        require(_maximumStake >= _minimumStake, "BondedWorkerRegistry: invalid maximum stake");
        
        aipgToken = IERC20(_aipgToken);
        minimumStake = _minimumStake;
        maximumStake = _maximumStake;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    // ============ REGISTRATION FUNCTIONS ============
    
    /**
     * @dev Register a bonded worker
     * @param supportedModels Array of model hashes this worker supports
     * @param workerId Off-chain worker identifier
     */
    function registerBondedWorker(
        bytes32[] calldata supportedModels,
        string calldata workerId
    ) external whenNotPaused nonReentrant {
        require(!isBondedWorker[msg.sender], "BondedWorkerRegistry: already registered");
        require(supportedModels.length > 0, "BondedWorkerRegistry: must support at least one model");
        require(bytes(workerId).length > 0, "BondedWorkerRegistry: worker ID required");
        require(workerIdToAddress[workerId] == address(0), "BondedWorkerRegistry: worker ID already exists");
        
        // Check for duplicate models
        for (uint256 i = 0; i < supportedModels.length; i++) {
            for (uint256 j = i + 1; j < supportedModels.length; j++) {
                require(supportedModels[i] != supportedModels[j], "BondedWorkerRegistry: duplicate models");
            }
        }

        // Transfer stake from worker
        aipgToken.safeTransferFrom(msg.sender, address(this), minimumStake);

        // Register worker
        WorkerInfo storage worker = workers[msg.sender];
        worker.stakeAmount = minimumStake;
        worker.supportedModels = supportedModels;
        worker.isActive = true;
        worker.registrationTime = block.timestamp;
        worker.lastActivity = block.timestamp;
        worker.workerId = workerId;
        worker.totalJobsCompleted = 0;
        worker.totalRewardsEarned = 0;

        isBondedWorker[msg.sender] = true;
        workerIdToAddress[workerId] = msg.sender;
        allWorkers.push(msg.sender);
        totalStaked += minimumStake;

        // Update model mappings
        for (uint256 i = 0; i < supportedModels.length; i++) {
            modelToWorkers[supportedModels[i]].push(msg.sender);
        }

        emit WorkerRegistered(msg.sender, minimumStake, supportedModels, workerId);
    }

    /**
     * @dev Unregister a bonded worker and withdraw stake
     */
    function unregisterBondedWorker() external onlyBondedWorker whenNotPaused nonReentrant {
        WorkerInfo storage worker = workers[msg.sender];
        require(worker.isActive, "BondedWorkerRegistry: worker not active");

        uint256 stakeAmount = worker.stakeAmount;
        
        // Update state
        worker.isActive = false;
        isBondedWorker[msg.sender] = false;
        totalStaked -= stakeAmount;

        // Remove from model mappings
        for (uint256 i = 0; i < worker.supportedModels.length; i++) {
            bytes32 modelHash = worker.supportedModels[i];
            address[] storage workersForModel = modelToWorkers[modelHash];
            
            for (uint256 j = 0; j < workersForModel.length; j++) {
                if (workersForModel[j] == msg.sender) {
                    workersForModel[j] = workersForModel[workersForModel.length - 1];
                    workersForModel.pop();
                    break;
                }
            }
        }

        // Transfer stake back to worker
        aipgToken.safeTransfer(msg.sender, stakeAmount);

        emit WorkerUnregistered(msg.sender);
    }

    // ============ STAKE MANAGEMENT ============
    
    /**
     * @dev Increase stake amount
     * @param additionalAmount Additional amount to stake
     */
    function increaseStake(uint256 additionalAmount) external onlyBondedWorker whenNotPaused nonReentrant {
        require(additionalAmount > 0, "BondedWorkerRegistry: invalid amount");
        
        WorkerInfo storage worker = workers[msg.sender];
        uint256 newTotal = worker.stakeAmount + additionalAmount;
        require(newTotal <= maximumStake, "BondedWorkerRegistry: exceeds maximum stake");

        // Transfer additional stake
        aipgToken.safeTransferFrom(msg.sender, address(this), additionalAmount);

        // Update state
        worker.stakeAmount = newTotal;
        totalStaked += additionalAmount;

        emit StakeIncreased(msg.sender, additionalAmount);
    }

    /**
     * @dev Decrease stake amount (partial withdrawal)
     * @param decreaseAmount Amount to withdraw
     */
    function decreaseStake(uint256 decreaseAmount) external onlyBondedWorker whenNotPaused nonReentrant {
        WorkerInfo storage worker = workers[msg.sender];
        require(worker.isActive, "BondedWorkerRegistry: worker not active");
        require(decreaseAmount > 0, "BondedWorkerRegistry: invalid amount");
        require(decreaseAmount < worker.stakeAmount, "BondedWorkerRegistry: cannot withdraw all stake");
        
        uint256 newAmount = worker.stakeAmount - decreaseAmount;
        require(newAmount >= minimumStake, "BondedWorkerRegistry: below minimum stake");

        // Update state
        worker.stakeAmount = newAmount;
        totalStaked -= decreaseAmount;

        // Transfer stake back to worker
        aipgToken.safeTransfer(msg.sender, decreaseAmount);

        emit StakeDecreased(msg.sender, decreaseAmount);
    }

    // ============ MODEL MANAGEMENT ============
    
    /**
     * @dev Update supported models for a worker
     * @param newModels Array of new model hashes
     */
    function updateSupportedModels(bytes32[] calldata newModels) external onlyBondedWorker whenNotPaused {
        require(newModels.length > 0, "BondedWorkerRegistry: must support at least one model");
        
        WorkerInfo storage worker = workers[msg.sender];
        require(worker.isActive, "BondedWorkerRegistry: worker not active");

        // Remove from old model mappings
        for (uint256 i = 0; i < worker.supportedModels.length; i++) {
            bytes32 modelHash = worker.supportedModels[i];
            address[] storage workersForModel = modelToWorkers[modelHash];
            
            for (uint256 j = 0; j < workersForModel.length; j++) {
                if (workersForModel[j] == msg.sender) {
                    workersForModel[j] = workersForModel[workersForModel.length - 1];
                    workersForModel.pop();
                    break;
                }
            }
        }

        // Add to new model mappings
        for (uint256 i = 0; i < newModels.length; i++) {
            modelToWorkers[newModels[i]].push(msg.sender);
        }

        // Update worker's supported models
        worker.supportedModels = newModels;

        emit ModelsUpdated(msg.sender, newModels);
    }

    // ============ REWARD FUNCTIONS ============
    
    /**
     * @dev Record job completion and reward (called by reward manager/treasury)
     * @param worker Worker address
     * @param rewardAmount AIPG reward amount (for tracking - actual transfer happens off-chain or via separate tx)
     */
    function recordJobCompletion(address worker, uint256 rewardAmount) external onlyRewardManager {
        require(isBondedWorker[worker], "BondedWorkerRegistry: not a bonded worker");
        
        WorkerInfo storage workerInfo = workers[worker];
        workerInfo.totalJobsCompleted += 1;
        workerInfo.totalRewardsEarned += rewardAmount;
        workerInfo.lastActivity = block.timestamp;

        emit JobCompleted(worker, rewardAmount);
    }

    /**
     * @dev Batch record multiple job completions (gas efficient for multiple workers)
     * @param workerAddresses Array of worker addresses
     * @param rewardAmounts Array of reward amounts
     */
    function batchRecordJobCompletions(
        address[] calldata workerAddresses,
        uint256[] calldata rewardAmounts
    ) external onlyRewardManager {
        require(workerAddresses.length == rewardAmounts.length, "BondedWorkerRegistry: arrays length mismatch");
        
        for (uint256 i = 0; i < workerAddresses.length; i++) {
            address worker = workerAddresses[i];
            if (isBondedWorker[worker]) {
                WorkerInfo storage workerInfo = workers[worker];
                workerInfo.totalJobsCompleted += 1;
                workerInfo.totalRewardsEarned += rewardAmounts[i];
                workerInfo.lastActivity = block.timestamp;
                emit JobCompleted(worker, rewardAmounts[i]);
            }
        }
    }

    /**
     * @dev Update worker activity timestamp
     */
    function updateActivity() external onlyBondedWorker {
        workers[msg.sender].lastActivity = block.timestamp;
        emit ActivityUpdated(msg.sender, block.timestamp);
    }

    // ============ SLASHING FUNCTIONS ============
    
    /**
     * @dev Slash a worker's stake (admin only)
     * @param worker Worker address
     * @param slashedAmount Amount to slash
     * @param reason Reason for slashing
     */
    function slashWorker(
        address worker,
        uint256 slashedAmount,
        string calldata reason
    ) external onlyAdmin {
        require(isBondedWorker[worker], "BondedWorkerRegistry: not a bonded worker");
        
        WorkerInfo storage workerInfo = workers[worker];
        require(slashedAmount <= workerInfo.stakeAmount, "BondedWorkerRegistry: insufficient stake to slash");
        
        // Update state
        workerInfo.stakeAmount -= slashedAmount;
        totalStaked -= slashedAmount;
        
        // If stake falls below minimum, deactivate worker
        if (workerInfo.stakeAmount < minimumStake) {
            workerInfo.isActive = false;
            isBondedWorker[worker] = false;
        }

        // Transfer slashed amount to admin (or burn)
        aipgToken.safeTransfer(msg.sender, slashedAmount);

        emit WorkerSlashed(worker, slashedAmount, reason);
    }

    // ============ ADMIN FUNCTIONS ============
    
    /**
     * @dev Set minimum stake amount
     * @param newMinimum New minimum stake
     */
    function setMinimumStake(uint256 newMinimum) external onlyAdmin {
        require(newMinimum > 0, "BondedWorkerRegistry: invalid minimum stake");
        uint256 oldValue = minimumStake;
        minimumStake = newMinimum;
        emit MinimumStakeUpdated(oldValue, newMinimum);
    }

    /**
     * @dev Set maximum stake amount
     * @param newMaximum New maximum stake
     */
    function setMaximumStake(uint256 newMaximum) external onlyAdmin {
        require(newMaximum >= minimumStake, "BondedWorkerRegistry: invalid maximum stake");
        uint256 oldValue = maximumStake;
        maximumStake = newMaximum;
        emit MaximumStakeUpdated(oldValue, newMaximum);
    }

    /**
     * @dev Pause contract
     */
    function pause() external onlyAdmin {
        _pause();
    }

    /**
     * @dev Unpause contract
     */
    function unpause() external onlyAdmin {
        _unpause();
    }

    // ============ VIEW FUNCTIONS ============
    
    /**
     * @dev Get worker information
     * @param worker Worker address
     * @return Worker information struct
     */
    function getWorkerInfo(address worker) external view returns (WorkerInfo memory) {
        return workers[worker];
    }

    /**
     * @dev Get workers supporting a specific model
     * @param modelHash Model hash
     * @return Array of worker addresses
     */
    function getWorkersForModel(bytes32 modelHash) external view returns (address[] memory) {
        return modelToWorkers[modelHash];
    }

    /**
     * @dev Get all registered workers
     * @return Array of all worker addresses
     */
    function getAllWorkers() external view returns (address[] memory) {
        return allWorkers;
    }

    /**
     * @dev Get total number of workers
     * @return Total worker count
     */
    function getTotalWorkers() external view returns (uint256) {
        return allWorkers.length;
    }

    /**
     * @dev Check if worker supports a model
     * @param worker Worker address
     * @param modelHash Model hash
     * @return Whether worker supports the model
     */
    function workerSupportsModel(address worker, bytes32 modelHash) external view returns (bool) {
        bytes32[] memory supportedModels = workers[worker].supportedModels;
        for (uint256 i = 0; i < supportedModels.length; i++) {
            if (supportedModels[i] == modelHash) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Get worker address by worker ID
     * @param workerId Worker ID string
     * @return Worker address (address(0) if not found)
     */
    function getWorkerByID(string calldata workerId) external view returns (address) {
        return workerIdToAddress[workerId];
    }
}
