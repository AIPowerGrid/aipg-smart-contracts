// Active Contract (Base Mainnet): see docs/ADDRESSES.md
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "./interfaces/IAIPGToken.sol";
import "./interfaces/IStakingVault.sol";

/**
 * @title EmissionsControllerV2
 * @dev Controls AIPG emissions by era, supports worker self-claims via EIP-712,
 *      and streams staker rewards via StakingVault.notifyRewardAmount().
 */
contract EmissionsControllerV2 is AccessControl, ReentrancyGuard, Pausable, EIP712 {
    using ECDSA for bytes32;

    // ============ ROLES ============
    bytes32 public constant EMISSIONS_MANAGER_ROLE = keccak256("EMISSIONS_MANAGER_ROLE");
    bytes32 public constant WORKER_ROLE = keccak256("WORKER_ROLE");
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE"); // authorized offchain signers

    // ============ ECONOMICS ============
    uint256 public constant MAX_SUPPLY = 150_000_000e18;
    uint256 public constant BPS_DENOM = 10000;

    // Configurable shares (BPS)
    uint16 public workerBps = 6000;   // 60%
    uint16 public stakerBps = 3000;   // 30%
    uint16 public treasuryBps = 1000; // 10%

    IAIPGToken public immutable token;
    IStakingVault public stakingVault;
    address public treasury;

    // ============ ERA SCHEDULE ============
    struct EraConfig { uint64 length; uint256 rewardPerHour; }
    EraConfig[] private _schedule;
    uint8 public era;              // index in schedule
    uint64 public nextEraTs;       // timestamp for next era
    uint256 public rewardPerHour;  // current era reward

    bool public emissionsPaused;
    uint64 public migrationStartTime;

    // ============ EIP-712 ============
    // keccak256("WorkerClaim(address worker,uint256 hoursWorked,uint256 nonce,uint256 deadline)")
    bytes32 private constant WORKER_CLAIM_TYPEHASH = 0xaf951ae13436754b4e70e550c82e28aab8397a6632b944a5e339bab92dc4e38f;
    mapping(address => uint256) public nonces; // worker => nonce

    // ============ EVENTS ============
    event EraStarted(uint8 indexed era, uint256 rewardPerHour, uint64 nextEraTs);
    event RewardEmitted(address indexed worker, uint256 workerAmt, uint256 stakerAmt, uint256 treasuryAmt, uint8 era);
    event EmissionsPaused(bool paused);
    event MigrationStarted(uint64 startTime);
    event SharesUpdated(uint16 workerBps, uint16 stakerBps, uint16 treasuryBps);
    event TreasuryUpdated(address treasury);
    event VaultUpdated(address vault);
    event DailyPayout(uint256 indexed epochId, string uri, uint256 workerCount, uint256 totalAmount, uint256 workerShare, uint256 stakerShare, uint256 treasuryShare);

    constructor(IAIPGToken _token, IStakingVault _vault, address _treasury)
        EIP712("AIPG-Emissions", "1")
    {
        require(address(_token) != address(0) && address(_vault) != address(0) && _treasury != address(0), "zero addr");
        token = _token;
        stakingVault = _vault;
        treasury = _treasury;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(EMISSIONS_MANAGER_ROLE, msg.sender);

        emissionsPaused = true;
        _schedule.push(EraConfig(1736 days, 9375e17));
        _schedule.push(EraConfig(365 days, 46875e16));
        _schedule.push(EraConfig(365 days, 234375e15));
        _schedule.push(EraConfig(365 days, 1171875e14));
        _schedule.push(EraConfig(362 days, 5859375e13));
        _schedule.push(EraConfig(2604 days, 5859375e13));
        _schedule.push(EraConfig(730 days, 29296875e12));

        rewardPerHour = _schedule[0].rewardPerHour;
        nextEraTs = uint64(block.timestamp) + _schedule[0].length;
        emit EraStarted(0, rewardPerHour, nextEraTs);
    }

    // ============ ADMIN ============
    function setEmissionsPaused(bool newPaused) external onlyRole(EMISSIONS_MANAGER_ROLE) {
        emissionsPaused = newPaused;
        emit EmissionsPaused(newPaused);
    }

    function setShares(uint16 _workerBps, uint16 _stakerBps, uint16 _treasuryBps) external onlyRole(EMISSIONS_MANAGER_ROLE) {
        require(uint256(_workerBps) + _stakerBps + _treasuryBps == BPS_DENOM, "shares!=100%");
        workerBps = _workerBps;
        stakerBps = _stakerBps;
        treasuryBps = _treasuryBps;
        emit SharesUpdated(_workerBps, _stakerBps, _treasuryBps);
    }

    function setTreasury(address _treasury) external onlyRole(EMISSIONS_MANAGER_ROLE) {
        require(_treasury != address(0), "treasury=0");
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    function setVault(address _vault) external onlyRole(EMISSIONS_MANAGER_ROLE) {
        require(_vault != address(0), "vault=0");
        stakingVault = IStakingVault(_vault);
        emit VaultUpdated(_vault);
    }

    function startMigration() external onlyRole(EMISSIONS_MANAGER_ROLE) {
        require(emissionsPaused, "already started");
        emissionsPaused = false;
        migrationStartTime = uint64(block.timestamp);
        emit MigrationStarted(migrationStartTime);
    }

    function startNextEra() external onlyRole(EMISSIONS_MANAGER_ROLE) {
        require(!emissionsPaused, "paused");
        require(block.timestamp >= nextEraTs + 15, "too early");
        require(token.totalSupply() < MAX_SUPPLY, "cap");

        era += 1;
        if (era < _schedule.length) {
            rewardPerHour = _schedule[era].rewardPerHour;
            nextEraTs += _schedule[era].length;
        } else {
            rewardPerHour = rewardPerHour / 2;
            nextEraTs += 730 days;
        }
        emit EraStarted(era, rewardPerHour, nextEraTs);
    }

    // ============ WORKER CLAIMS (EIP-712) ============
    function claimWithSignature(
        uint256 hoursWorked,
        uint256 deadline,
        bytes calldata signature
    ) external nonReentrant whenNotPaused {
        require(!emissionsPaused, "paused");
        require(hasRole(WORKER_ROLE, msg.sender), "not worker");
        require(hoursWorked > 0, "hours=0");
        require(block.timestamp <= deadline, "expired");

        uint256 nonce = nonces[msg.sender]++;
        bytes32 structHash = keccak256(abi.encode(
            WORKER_CLAIM_TYPEHASH,
            msg.sender,
            hoursWorked,
            nonce,
            deadline
        ));
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(digest, signature);
        require(hasRole(SIGNER_ROLE, signer), "bad sig");

        _emitRewards(msg.sender, hoursWorked);
    }

    // ============ MANAGER CLAIMS (no signature) ============
    function mintWorker(address worker, uint256 hoursWorked)
        external
        onlyRole(EMISSIONS_MANAGER_ROLE)
        nonReentrant
    {
        require(!emissionsPaused, "paused");
        require(worker != address(0) && hoursWorked > 0, "bad params");
        _emitRewards(worker, hoursWorked);
    }

    // ============ BATCH PAYOUT (manager) ============
    function batchMintWorkers(
        address[] calldata workers,
        uint256[] calldata amounts,
        uint256 epochId,
        string calldata uri
    ) external onlyRole(EMISSIONS_MANAGER_ROLE) nonReentrant {
        require(!emissionsPaused, "paused");
        require(workers.length == amounts.length, "len mismatch");
        uint256 n = workers.length;
        require(n > 0, "empty");

        uint256 totalAmount = 0;
        uint256 totalWorker = 0;
        uint256 totalStaker = 0;
        uint256 totalTreasury = 0;

        for (uint256 i = 0; i < n; i++) {
            address w = workers[i];
            uint256 a = amounts[i];
            require(w != address(0) && a > 0, "bad row");
            totalAmount += a;
        }
        require(token.totalSupply() + totalAmount <= MAX_SUPPLY, "exceeds cap");

        for (uint256 i = 0; i < n; i++) {
            address w = workers[i];
            uint256 a = amounts[i];
            uint256 wShare = (a * workerBps) / BPS_DENOM;
            uint256 sShare = (a * stakerBps) / BPS_DENOM;
            uint256 tShare = a - wShare - sShare;

            if (wShare > 0) token.mint(w, wShare);
            totalWorker += wShare;
            totalStaker += sShare;
            totalTreasury += tShare;
        }

        if (totalStaker > 0) {
            token.mint(address(stakingVault), totalStaker);
            stakingVault.notifyRewardAmount(totalStaker);
        }
        if (totalTreasury > 0) {
            token.mint(treasury, totalTreasury);
        }

        emit DailyPayout(epochId, uri, n, totalAmount, totalWorker, totalStaker, totalTreasury);
    }

    // ============ INTERNAL EMISSION ============
    function _emitRewards(address worker, uint256 hoursWorked) internal {
        uint256 total = hoursWorked * rewardPerHour;
        require(total > 0, "zero");
        require(token.totalSupply() + total <= MAX_SUPPLY, "exceeds cap");

        uint256 w = (total * workerBps) / BPS_DENOM;
        uint256 s = (total * stakerBps) / BPS_DENOM;
        uint256 t = total - w - s;

        // Mint tokens
        token.mint(worker, w);
        token.mint(address(stakingVault), s);
        token.mint(treasury, t);

        // Stream staker rewards via vault
        stakingVault.notifyRewardAmount(s);

        emit RewardEmitted(worker, w, s, t, era);
    }

    // ============ VIEWS ============
    function getRewardRatePerHour() external view returns (uint256) {
        return emissionsPaused ? 0 : rewardPerHour;
    }

    function getMigrationStatus() external view returns (bool paused_, uint64 startTime_, uint256 daysSinceStart_) {
        paused_ = emissionsPaused;
        startTime_ = migrationStartTime;
        daysSinceStart_ = startTime_ > 0 ? (block.timestamp - startTime_) / 1 days : 0;
    }
}
