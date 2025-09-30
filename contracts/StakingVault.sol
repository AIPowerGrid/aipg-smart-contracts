// Active Contract (Base Mainnet): see docs/ADDRESSES.md
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IStakingVault.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title StakingVault
 * @dev Synthetix-style staking with per-token reward accrual and external reward funding
 * - Stake/withdraw the staking token (AIPG)
 * - Rewards are notified via notifyRewardAmount() by an authorized distributor (EmissionsController)
 * - Rewards are paid in the rewards token (AIPG) held by this contract
 */
contract StakingVault is AccessControl, ReentrancyGuard, Pausable, IStakingVault {
    using SafeERC20 for IERC20;

    // ============ ROLES ============
    bytes32 public constant REWARD_DISTRIBUTOR_ROLE = keccak256("REWARD_DISTRIBUTOR_ROLE");

    // ============ TOKENS ============
    IERC20 public immutable stakingToken;   // token users stake
    IERC20 public immutable rewardsToken;   // token used for rewards (same as staking token in our case)

    // ============ STAKING STATE ============
    uint256 public totalSupply;
    mapping(address => uint256) public balances;

    // ============ REWARD STATE ============
    uint256 public rewardRate;            // reward tokens per second
    uint256 public rewardsDuration = 7 days; // configurable by admin, default 7 days
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public periodFinish;          // timestamp when current reward period ends

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    // ============ EVENTS ============
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardAdded(uint256 reward, uint256 newRate, uint256 periodFinish);
    event RewardsDurationUpdated(uint256 newDuration);

    constructor(IERC20 _stakingToken, IERC20 _rewardsToken) {
        require(address(_stakingToken) != address(0), "staking token is zero");
        require(address(_rewardsToken) != address(0), "rewards token is zero");
        stakingToken = _stakingToken;
        rewardsToken = _rewardsToken;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // ============ MODIFIERS ============
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    // ============ VIEWS ============
    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + ((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) / totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    function earned(address account) public view returns (uint256) {
        return ((balances[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18) + rewards[account];
    }

    // ============ ADMIN ============
    function setRewardsDuration(uint256 _rewardsDuration) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(block.timestamp > periodFinish, "reward period active");
        require(_rewardsDuration > 0, "duration=0");
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(_rewardsDuration);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // ============ REWARD DISTRIBUTION ============
    /**
     * @dev Fund a new reward period. Caller must have already transferred `reward` tokens
     *      to this contract (or mint to this contract beforehand). The reward is streamed linearly
     *      over `rewardsDuration` seconds.
     */
    function notifyRewardAmount(uint256 reward)
        external
        onlyRole(REWARD_DISTRIBUTOR_ROLE)
        updateReward(address(0))
    {
        require(reward > 0, "reward=0");

        if (block.timestamp >= periodFinish) {
            rewardRate = reward / rewardsDuration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / rewardsDuration;
        }

        // Effects
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;

        emit RewardAdded(reward, rewardRate, periodFinish);
    }

    // ============ USER ACTIONS ============
    function stake(uint256 amount) external nonReentrant whenNotPaused updateReward(msg.sender) {
        require(amount > 0, "stake=0");
        totalSupply += amount;
        balances[msg.sender] += amount;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
        require(amount > 0, "withdraw=0");
        require(balances[msg.sender] >= amount, "exceeds balance");
        totalSupply -= amount;
        balances[msg.sender] -= amount;
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardsToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function exit() external {
        withdraw(balances[msg.sender]);
        getReward();
    }
}
