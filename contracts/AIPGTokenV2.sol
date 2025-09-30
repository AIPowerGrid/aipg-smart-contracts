// Deployed (Base Mainnet): AIPGTokenV2 at 0xa1c0deCaFE3E9Bf06A5F29B7015CD373a9854608
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title AIPGTokenV2
 * @dev ERC20 token for AI Power Grid with minting, burning, pausing, and bridge functionality
 * Includes proper mint() function for emissions and improved security
 */
contract AIPGTokenV2 is
    ERC20Capped,
    ERC20Permit,
    ERC20Burnable,
    ERC20Pausable,    
    AccessControl,
    ReentrancyGuard
{
    using ECDSA for bytes32;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 private constant MINT_TYPEHASH = keccak256("MintRequest(address to,uint256 amount,uint256 uuid,uint256 deadline)");
    
    // UUID tracking for replay protection
    mapping(bytes32 => bool) private usedUUIDs;

    // Events
    event BridgeMinted(address indexed to, uint256 amount, uint256 uuid, uint256 deadline);
    event RescuedERC20(address indexed token, address indexed to, uint256 amount);

    struct MintRequest {
        address to;
        uint256 amount;
        uint256 uuid;
        uint256 deadline;
    }

    constructor(address treasury)
        ERC20("AI Power Grid", "AIPG")
        ERC20Permit("AI Power Grid")
        ERC20Capped(150_000_000 ether)              // 150M cap to match UTXO economics
    {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);

        _mint(treasury, 15_000_000 ether);          // genesis supply
    }

    /**
     * @dev Mint new tokens (for emissions)
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) 
        external 
        onlyRole(MINTER_ROLE) 
        whenNotPaused 
    {
        _mint(to, amount);
    }

    /**
     * @dev Bridge minting function with EIP-712 signature verification
     * @param request MintRequest containing recipient, amount, uuid and deadline
     * @param v ECDSA signature v
     * @param r ECDSA signature r
     * @param s ECDSA signature s
     */
    function bridgeMint(MintRequest calldata request, uint8 v, bytes32 r, bytes32 s) 
        external 
        whenNotPaused 
    {
        require(block.timestamp <= request.deadline, "Expired deadline");
        
        bytes32 structHash = keccak256(abi.encode(MINT_TYPEHASH, request.to, request.amount, request.uuid, request.deadline));
        bytes32 digest = _hashTypedDataV4(structHash);
        
        // Use OpenZeppelin's ECDSA instead of raw ecrecover
        address signer = digest.recover(v, r, s);
        require(hasRole(MINTER_ROLE, signer), "Invalid signature or unauthorized");

        // Check if the UUID has already been used (include chainId for cross-chain safety)
        bytes32 transactionHash = keccak256(abi.encodePacked(request.to, request.amount, request.uuid, block.chainid));
        require(!usedUUIDs[transactionHash], "UUID already used");

        // Mark this UUID as used
        usedUUIDs[transactionHash] = true;

        _mint(request.to, request.amount);
        
        emit BridgeMinted(request.to, request.amount, request.uuid, request.deadline);
    }

    /**
     * @dev Check if a UUID has been used
     * @param to Recipient address
     * @param amount Amount to mint
     * @param uuid Unique identifier
     * @return True if UUID has been used
     */
    function isUUIDUsed(address to, uint256 amount, uint256 uuid) external view returns (bool) {
        bytes32 transactionHash = keccak256(abi.encodePacked(to, amount, uuid, block.chainid));
        return usedUUIDs[transactionHash];
    }

    /**
     * @dev Pause token transfers and minting
     */
    function pause() external onlyRole(PAUSER_ROLE) { 
        _pause(); 
    }
    
    /**
     * @dev Unpause token transfers and minting
     */
    function unpause() external onlyRole(PAUSER_ROLE) { 
        _unpause(); 
    }

    /**
     * @dev Rescue ERC20 tokens accidentally sent to this contract
     * @param tokenAddress Address of the ERC20 token
     * @param to Recipient address
     * @param amount Amount to rescue
     */
    function rescueERC20(address tokenAddress, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        // Prevent rescuing the token itself
        require(tokenAddress != address(this), "Cannot rescue AIPG");
        
        IERC20 token = IERC20(tokenAddress);
        require(token.transfer(to, amount), "Transfer failed");
        
        emit RescuedERC20(tokenAddress, to, amount);
    }

    /**
     * @dev Override required by Solidity for multiple inheritance
     */
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Capped, ERC20Pausable)
    {
        super._update(from, to, value);
    }
}
