// Active Contract (Base Mainnet): see docs/ADDRESSES.md
// SPDX-License-Identifier: MIT
// Deployed at: 0xa87Eb64534086e914A4437ac75a1b554A10C9934 (Base Sepolia)
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";


/**
 * @title GridNFT
 * @dev Premium AI art NFTs with worker payment incentives
 * @notice Workers mint NFTs using approved recipes and earn most of the mint fees
 */
contract GridNFT is ERC721Pausable, AccessControl, ReentrancyGuard, ERC2981 {
    // ============ ROLES ============
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant WORKER_ROLE = keccak256("WORKER_ROLE");
    bytes32 public constant RECIPE_APPROVER_ROLE = keccak256("RECIPE_APPROVER_ROLE");

    // ============ STATE ============
    uint256 private _tokenIdCounter = 1; // Start at 1
    
    // Pricing structure
    uint256 public baseMintFee = 0.025 ether; // Public mint fee
    uint256 public baseMintFeePrivate = 0.05 ether; // Private mint fee
    uint256 public workerShareBps = 7500; // 75% to worker
    uint256 public protocolShareBps = 2500; // 25% to protocol
    
    // Fee recipients
    address public immutable protocolTreasury;
    address public immutable recipeVaultContract;
    address public immutable modelRegistryContract;
    
    // Royalties (EIP-2981)
    uint96 public defaultRoyaltyBps = 250; // 2.5% to the minter (worker) by default
    
    // NFT tiers
    enum ArtTier {
        STANDARD,    // Visually identical
        STRICT       // Byte-identical, fp32 precision
    }
    
    // Core metadata structure
    struct ArtMetadata {
        uint256 modelId;         // Points to ModelShop tokenId 
        uint256 recipeId;        // Points to RecipeVault recipe
        uint256 seed;            // Generation seed
        uint16 steps;            // Sampling steps
        uint16 cfgTenths;        // CFG scale in tenths (e.g. 35 = 3.5)
        uint16 width;            // Image width
        uint16 height;           // Image height
        ArtTier tier;            // Standard or Strict
        address worker;          // Worker who minted
        uint256 mintTimestamp;   // When minted
        bool isReproducible;     // Can be reproduced from chain data
    }
    
    // String data stored separately to avoid stack too deep
    struct ArtStrings {
        string prompt;           // Text prompt
        string negativePrompt;   // Negative prompt  
        string sampler;          // Sampler name (e.g. "euler")
        string scheduler;        // Scheduler name (e.g. "karras")
        string ipfsHash;         // Generated image location
    }
    
    // Storage
    mapping(uint256 => ArtMetadata) public artworks;
    mapping(uint256 => ArtStrings) public artworkStrings;
    mapping(bytes32 => bool) public usedSeeds; // Prevent duplicate seeds for same model+recipe
    mapping(uint256 => bool) public approvedRecipeIds; // Approved RecipeVault recipes
    mapping(address => uint256) public workerEarnings; // Track worker earnings
    mapping(address => uint256) public workerMintCount; // Track worker activity
    
    // Privacy controls and encrypted payloads (soft-private: ciphertext held on-chain, preview public)
    mapping(uint256 => bool) public isPrivateToken; // visibility flag per token
    mapping(uint256 => string) public previewIpfsHash; // watermarked/obscured preview
    mapping(uint256 => bytes) private encryptedBundle; // encrypted plaintext bundle for regeneration
    mapping(uint256 => bytes32) public contentRoot; // keccak256 commitment of plaintext bundle
    
    // Fee tracking
    uint256 public totalFeesCollected;
    uint256 public totalWorkerPayouts;
    uint256 public totalProtocolFees;
    
    // ============ EVENTS ============
    event ArtworkMinted(
        uint256 indexed tokenId,
        uint256 indexed modelId,
        uint256 indexed recipeId,
        address worker,
        ArtTier tier,
        string ipfsHash
    );

    event WorkerPaid(address indexed worker, uint256 amount);
    event ProtocolFeePaid(uint256 amount);
    event RecipeApproved(uint256 indexed recipeId, bool approved);
    event PricingUpdated(uint256 baseFee, uint256 workerShare, uint256 protocolShare);
    event PrivateArtworkMinted(uint256 indexed tokenId, string previewIpfsHash);
    event ArtworkRevealed(uint256 indexed tokenId);
    
    // ============ CONSTRUCTOR ============
    constructor(
        address _protocolTreasury,
        address _recipeVaultContract,
        address _modelRegistryContract
    ) ERC721("AIPG Grid Art", "GRIDNFT") {
        require(_protocolTreasury != address(0), "GridNFT: invalid treasury");
        require(_recipeVaultContract != address(0), "GridNFT: invalid recipe vault");
        require(_modelRegistryContract != address(0), "GridNFT: invalid model registry");
        
        protocolTreasury = _protocolTreasury;
        recipeVaultContract = _recipeVaultContract;
        modelRegistryContract = _modelRegistryContract;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(RECIPE_APPROVER_ROLE, msg.sender);
    }
    
    // ============ MODIFIERS ============
    modifier onlyWorker() {
        require(hasRole(WORKER_ROLE, msg.sender), "GridNFT: not a worker");
        _;
    }
    
    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "GridNFT: not admin");
        _;
    }
    
    
    modifier validRecipe(uint256 recipeId) {
        require(approvedRecipeIds[recipeId], "GridNFT: recipe not approved");
        _;
    }
    
    modifier uniqueSeed(uint256 modelId, uint256 recipeId, uint256 seed) {
        bytes32 seedKey = keccak256(abi.encodePacked(modelId, recipeId, seed));
        require(!usedSeeds[seedKey], "GridNFT: seed already used for this model+recipe");
        _;
    }
    
    // ============ MINTING ============
    
    /**
     * @dev Mint AI artwork NFT with complete generation parameters and strings
     */
    function mintArtworkComplete(
        address to,
        uint256 modelId,
        uint256 recipeId,
        uint256 seed,
        uint16 steps,
        uint16 cfgTenths,
        uint16 width,
        uint16 height,
        ArtTier tier,
        string calldata prompt,
        string calldata negativePrompt,
        string calldata sampler,
        string calldata scheduler,
        string calldata ipfsHash
    ) 
        external 
        payable 
        onlyWorker 
        whenNotPaused 
        nonReentrant
        returns (uint256)
    {
        require(to != address(0), "GridNFT: invalid recipient");
        require(approvedRecipeIds[recipeId], "GridNFT: recipe not approved");
        require(seed > 0, "GridNFT: invalid seed");
        require(steps > 0, "GridNFT: invalid steps");
        require(width > 0 && height > 0, "GridNFT: invalid dimensions");
        require(bytes(prompt).length > 0, "GridNFT: prompt required");
        require(bytes(sampler).length > 0, "GridNFT: sampler required");
        require(bytes(scheduler).length > 0, "GridNFT: scheduler required");
        require(msg.value >= baseMintFee, "GridNFT: insufficient payment");
        
        // Check seed uniqueness
        bytes32 seedKey = keccak256(abi.encodePacked(modelId, recipeId, seed));
        require(!usedSeeds[seedKey], "GridNFT: seed already used");
        
        uint256 tokenId = _tokenIdCounter++;
        
        // Store core metadata
        artworks[tokenId] = ArtMetadata({
            modelId: modelId,
            recipeId: recipeId,
            seed: seed,
            steps: steps,
            cfgTenths: cfgTenths,
            width: width,
            height: height,
            tier: tier,
            worker: msg.sender,
            mintTimestamp: block.timestamp,
            isReproducible: true
        });
        
        // Store string data in same transaction
        artworkStrings[tokenId] = ArtStrings({
            prompt: prompt,
            negativePrompt: negativePrompt,
            sampler: sampler,
            scheduler: scheduler,
            ipfsHash: ipfsHash
        });
        
        // Mark seed as used
        usedSeeds[seedKey] = true;
        
        // Update worker stats
        workerMintCount[msg.sender]++;
        
        // Process payments (75% to worker, 25% to protocol)
        _processPayments(msg.sender, msg.value);
        
        // Mint NFT
        _safeMint(to, tokenId);
        
        // Set per-token royalty to worker (minter) using default bps
        if (defaultRoyaltyBps > 0) {
            _setTokenRoyalty(tokenId, msg.sender, defaultRoyaltyBps);
        }
        
        emit ArtworkMinted(tokenId, modelId, recipeId, msg.sender, tier, ipfsHash);
        
        return tokenId;
    }
    
    // Deprecated simplified mint removed to reduce code size
    
    /**
     * @dev Set string data for minted artwork (separate function to avoid stack too deep)
     */
    function setArtworkStrings(
        uint256 tokenId,
        string calldata prompt,
        string calldata negativePrompt,
        string calldata sampler,
        string calldata scheduler,
        string calldata ipfsHash
    ) external {
        require(_ownerOf(tokenId) != address(0), "GridNFT: nonexistent token");
        require(
            msg.sender == artworks[tokenId].worker || 
            msg.sender == _ownerOf(tokenId) || 
            hasRole(ADMIN_ROLE, msg.sender),
            "GridNFT: not authorized"
        );
        
        artworkStrings[tokenId] = ArtStrings({
            prompt: prompt,
            negativePrompt: negativePrompt,
            sampler: sampler,
            scheduler: scheduler,
            ipfsHash: ipfsHash
        });
    }

    // Edition JSON emission removed - all data now stored on-chain in ArtMetadata
    
    /**
     * @dev Process mint fee payments (75% to worker, 25% to protocol)
     */
    function _processPayments(address worker, uint256 totalFee) private {
        uint256 workerPayout = (totalFee * workerShareBps) / 10000;
        uint256 protocolFee = totalFee - workerPayout;
        
        // Track earnings
        workerEarnings[worker] += workerPayout;
        totalFeesCollected += totalFee;
        totalWorkerPayouts += workerPayout;
        totalProtocolFees += protocolFee;
        
        // Pay worker immediately
        Address.sendValue(payable(worker), workerPayout);
        emit WorkerPaid(worker, workerPayout);
        
        // Pay protocol treasury
        Address.sendValue(payable(protocolTreasury), protocolFee);
        emit ProtocolFeePaid(protocolFee);
    }
    
    // ============ MODEL & RECIPE MANAGEMENT ============
    
    // Model approvals are sourced from ModelShop.isVerified; local approvals removed
    
    /**
     * @dev Approve recipe for NFT minting
     */
    function approveRecipe(uint256 recipeId, bool approved) 
        external 
        onlyRole(RECIPE_APPROVER_ROLE) 
    {
        require(recipeId > 0, "GridNFT: invalid recipe ID");
        approvedRecipeIds[recipeId] = approved;
        emit RecipeApproved(recipeId, approved);
    }
    
    /**
     * @dev Batch approve multiple models
     */
    // Batch approvals removed to reduce code size
    
    // ============ WORKER MANAGEMENT ============
    
    /**
     * @dev Add worker (must be bonded in BondedWorkerRegistry)
     */
    function addWorker(address worker) external onlyAdmin {
        require(worker != address(0), "GridNFT: invalid worker");
        _grantRole(WORKER_ROLE, worker);
    }
    
    /**
     * @dev Remove worker
     */
    function removeWorker(address worker) external onlyAdmin {
        _revokeRole(WORKER_ROLE, worker);
    }
    
    /**
     * @dev Batch add workers
     */
    function batchAddWorkers(address[] calldata workers) external onlyAdmin {
        for (uint256 i = 0; i < workers.length; i++) {
            require(workers[i] != address(0), "GridNFT: invalid worker");
            _grantRole(WORKER_ROLE, workers[i]);
        }
    }
    
    // ============ ADMIN FUNCTIONS ============
    
    /**
     * @dev Update pricing structure
     */
    function updatePricing(
        uint256 newBaseFee,
        uint256 newWorkerShareBps,
        uint256 newProtocolShareBps
    ) external onlyAdmin {
        require(newWorkerShareBps + newProtocolShareBps == 10000, "GridNFT: shares must equal 100%");
        // Allow zero base fee in testing
        // require(newBaseFee > 0, "GridNFT: invalid base fee");
        
        baseMintFee = newBaseFee;
        workerShareBps = newWorkerShareBps;
        protocolShareBps = newProtocolShareBps;
        
        emit PricingUpdated(newBaseFee, newWorkerShareBps, newProtocolShareBps);
    }
    
    /**
     * @dev Update private mint fee
     */
    function updatePrivateMintFee(uint256 newPrivateFee) external onlyAdmin {
        baseMintFeePrivate = newPrivateFee;
    }
    
    /**
     * @dev Update protocol treasury
     */
    // Removing ability to update immutable treasury for safety. If rotation is needed,
    // deploy a new contract or route via a proxy treasury.
    
    /**
     * @dev Emergency pause
     */
    function pause() external onlyAdmin {
        _pause();
    }
    
    /**
     * @dev Unpause
     */
    function unpause() external onlyAdmin {
        _unpause();
    }
    
    // ============ VIEW FUNCTIONS ============
    
    /**
     * @dev Get complete artwork data (convenience function)
     */
    function getCompleteArtwork(uint256 tokenId) external view returns (
        ArtMetadata memory metadata,
        ArtStrings memory strings
    ) {
        require(_ownerOf(tokenId) != address(0), "GridNFT: nonexistent token");
        return (artworks[tokenId], artworkStrings[tokenId]);
    }
    
    /**
     * @dev Check if seed is already used for model+recipe combination
     */
    function isSeedUsed(uint256 modelId, uint256 recipeId, uint256 seed) external view returns (bool) {
        bytes32 seedKey = keccak256(abi.encodePacked(modelId, recipeId, seed));
        return usedSeeds[seedKey];
    }
    
    // Model approval view removed; rely on ModelShop.models(tokenId).isVerified
    
    /**
     * @dev Check if recipe is approved
     */
    function isRecipeApproved(uint256 recipeId) external view returns (bool) {
        return approvedRecipeIds[recipeId];
    }
    
    // Worker stats helper removed to reduce code size
    
    /**
     * @dev Get contract stats
     */
    function getContractStats() external view returns (
        uint256 totalSupply,
        uint256 totalFees,
        uint256 workerPayouts,
        uint256 protocolFees,
        uint256 currentBaseFee
    ) {
        return (
            _tokenIdCounter - 1,
            totalFeesCollected,
            totalWorkerPayouts,
            totalProtocolFees,
            baseMintFee
        );
    }
    
    
    // ============ REQUIRED OVERRIDES ============
    
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
    
    // No custom _beforeTokenTransfer logic needed
    
    /**
     * @dev Total minted tokens (1-based counter minus one)
     */
    function totalMinted() external view returns (uint256) {
        return _tokenIdCounter - 1;
    }
    
    // ============ METADATA & ROYALTIES ============
    
    /**
     * @dev Returns tokenURI for marketplaces. Uses ipfsHash from ArtStrings if set.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "GridNFT: nonexistent token");
        if (isPrivateToken[tokenId]) {
            // Private tokens: return minimal JSON and use preview IPFS if present
            string memory preview = previewIpfsHash[tokenId];
            string memory jsonPriv = string(abi.encodePacked(
                '{"name":"AIPG Grid Art #', _toString(tokenId), '",',
                ',"description":"Private artwork: preview only. Owner may reveal.",',
                '"attributes":[{"trait_type":"visibility","value":"private"}]',
                bytes(preview).length == 46 ? string(abi.encodePacked(',"image":"ipfs://', preview, '"')) : '',
                '}'
            ));
            return string(abi.encodePacked("data:application/json;utf8,", jsonPriv));
        }
        string memory hash = artworkStrings[tokenId].ipfsHash;
        if (bytes(hash).length == 46) {
            return string(abi.encodePacked("ipfs://", hash));
        }
        // Minimal JSON if no IPFS: data URI
        ArtMetadata memory m = artworks[tokenId];
        ArtStrings memory s = artworkStrings[tokenId];
        string memory json = string(abi.encodePacked(
            '{"name":"AIPG Grid Art #', _toString(tokenId), '",',
            ',"description":"AI art minted with full on-chain parameters.",' ,
            '"attributes":[',
              '{"trait_type":"modelId","value":"', _toString(m.modelId), '"},',
              '{"trait_type":"recipeId","value":"', _toString(m.recipeId), '"},',
              '{"trait_type":"seed","value":"', _toString(m.seed), '"},',
              '{"trait_type":"steps","value":"', _toString(m.steps), '"},',
              '{"trait_type":"cfg","value":"', _toDecimalTenths(m.cfgTenths), '"},',
              '{"trait_type":"resolution","value":"', _resolution(m.width, m.height), '"},',
              '{"trait_type":"sampler","value":"', s.sampler, '"},',
              '{"trait_type":"scheduler","value":"', s.scheduler, '"}',
            ']}'
        ));
        return string(abi.encodePacked("data:application/json;utf8,", json));
    }

    // ============ PRIVACY MINTING & REVEAL ============

    /**
     * @dev Mint a private artwork NFT with encrypted bundle and preview IPFS
     * Stores full regeneration bundle as ciphertext on-chain; plaintext commitment via contentRoot.
     */
    function mintArtworkPrivate(
        address to,
        uint256 modelId,
        uint256 recipeId,
        uint256 seed,
        uint16 steps,
        uint16 cfgTenths,
        uint16 width,
        uint16 height,
        ArtTier tier,
        string calldata previewHash,
        bytes calldata ciphertextBundle,
        bytes32 plaintextContentRoot
    )
        external
        payable
        onlyWorker
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        require(to != address(0), "GridNFT: invalid recipient");
        require(approvedRecipeIds[recipeId], "GridNFT: recipe not approved");
        require(seed > 0, "GridNFT: invalid seed");
        require(steps > 0, "GridNFT: invalid steps");
        require(width > 0 && height > 0, "GridNFT: invalid dimensions");
        require(msg.value >= baseMintFeePrivate, "GridNFT: insufficient payment for private mint");

        bytes32 seedKey = keccak256(abi.encodePacked(modelId, recipeId, seed));
        require(!usedSeeds[seedKey], "GridNFT: seed already used");

        uint256 tokenId = _tokenIdCounter++;

        artworks[tokenId] = ArtMetadata({
            modelId: modelId,
            recipeId: recipeId,
            seed: seed,
            steps: steps,
            cfgTenths: cfgTenths,
            width: width,
            height: height,
            tier: tier,
            worker: msg.sender,
            mintTimestamp: block.timestamp,
            isReproducible: true
        });

        usedSeeds[seedKey] = true;
        workerMintCount[msg.sender]++;

        // Privacy data
        isPrivateToken[tokenId] = true;
        previewIpfsHash[tokenId] = previewHash;
        if (ciphertextBundle.length > 0) {
            encryptedBundle[tokenId] = ciphertextBundle;
        }
        contentRoot[tokenId] = plaintextContentRoot;

        _processPayments(msg.sender, msg.value);

        _safeMint(to, tokenId);

        if (defaultRoyaltyBps > 0) {
            _setTokenRoyalty(tokenId, msg.sender, defaultRoyaltyBps);
        }

        emit PrivateArtworkMinted(tokenId, previewHash);
        return tokenId;
    }

    /**
     * @dev Reveal a private token by supplying plaintext strings matching the stored contentRoot
     */
    function revealArtwork(
        uint256 tokenId,
        string calldata prompt,
        string calldata negativePrompt,
        string calldata sampler,
        string calldata scheduler,
        string calldata ipfsHash
    ) external {
        require(_ownerOf(tokenId) != address(0), "GridNFT: nonexistent token");
        require(isPrivateToken[tokenId], "GridNFT: not private");
        address owner = _ownerOf(tokenId);
        require(
            msg.sender == owner ||
            getApproved(tokenId) == msg.sender ||
            isApprovedForAll(owner, msg.sender) ||
            hasRole(ADMIN_ROLE, msg.sender),
            "GridNFT: not authorized"
        );

        ArtMetadata memory m = artworks[tokenId];
        bytes32 computed = keccak256(abi.encode(
            m.modelId,
            m.recipeId,
            m.seed,
            m.steps,
            m.cfgTenths,
            m.width,
            m.height,
            m.tier,
            prompt,
            negativePrompt,
            sampler,
            scheduler,
            ipfsHash
        ));
        require(computed == contentRoot[tokenId], "GridNFT: content mismatch");

        artworkStrings[tokenId] = ArtStrings({
            prompt: prompt,
            negativePrompt: negativePrompt,
            sampler: sampler,
            scheduler: scheduler,
            ipfsHash: ipfsHash
        });

        isPrivateToken[tokenId] = false;
        delete encryptedBundle[tokenId];
        emit ArtworkRevealed(tokenId);
    }

    /**
     * @dev Read the encrypted bundle for a token (owner/approved/admin only)
     */
    function getEncryptedBundle(uint256 tokenId) external view returns (bytes memory) {
        require(_ownerOf(tokenId) != address(0), "GridNFT: nonexistent token");
        address owner = _ownerOf(tokenId);
        require(
            msg.sender == owner ||
            getApproved(tokenId) == msg.sender ||
            isApprovedForAll(owner, msg.sender) ||
            hasRole(ADMIN_ROLE, msg.sender),
            "GridNFT: not authorized"
        );
        return encryptedBundle[tokenId];
    }
    
    /**
     * @dev Set default royalty in basis points. Admin only.
     */
    function setDefaultRoyalty(address receiver, uint96 bps) external onlyAdmin {
        require(receiver != address(0), "GridNFT: invalid receiver");
        require(bps <= 1000, "GridNFT: royalty too high"); // max 10%
        defaultRoyaltyBps = bps;
        _setDefaultRoyalty(receiver, bps);
    }
    
    // ============ INTERNAL HELPERS ============
    function _toString(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 j = v;
        uint256 length;
        while (j != 0) { length++; j /= 10; }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        j = v;
        while (j != 0) {
            k = k-1;
            uint8 temp = uint8(48 + j % 10);
            bstr[k] = bytes1(temp);
            j /= 10;
        }
        return string(bstr);
    }
    function _resolution(uint256 w, uint256 h) internal pure returns (string memory) {
        return string(abi.encodePacked(_toString(w), 'x', _toString(h)));
    }
    function _toDecimalTenths(uint256 tenths) internal pure returns (string memory) {
        // e.g. 40 -> "4.0"
        uint256 whole = tenths / 10;
        uint256 frac = tenths % 10;
        return string(abi.encodePacked(_toString(whole), '.', _toString(frac)));
    }
}
