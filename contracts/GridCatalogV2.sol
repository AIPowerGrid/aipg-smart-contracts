// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/AccessControlDefaultAdminRules.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title GridCatalogV2
 * @notice Versioned, content-addressed registry for AI Power Grid model
 *         manifests and executable generation recipes.
 *
 * @dev The catalog stores commitments and bounded metadata, not model weights or
 *      workflow blobs. Clients fetch `manifestURI` / `contentURI` off-chain and
 *      must verify the canonical bytes against the corresponding bytes32 hash.
 *      Inference services consume a cached, last-known-good view; this contract
 *      is never read in a request hot path.
 *
 *      Records are immutable except for their active status and a separately
 *      governed NFT-approval bit. Corrections create a new versioned record.
 */
contract GridCatalogV2 is AccessControlDefaultAdminRules, Pausable {
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant NFT_APPROVER_ROLE = keccak256("NFT_APPROVER_ROLE");

    uint32 public constant MODALITY_TEXT = 1 << 0;
    uint32 public constant MODALITY_IMAGE = 1 << 1;
    uint32 public constant MODALITY_VIDEO = 1 << 2;
    uint32 public constant MODALITY_AUDIO = 1 << 3;
    uint32 public constant MODALITY_THREE_D = 1 << 4;
    uint32 public constant KNOWN_MODALITIES =
        MODALITY_TEXT | MODALITY_IMAGE | MODALITY_VIDEO | MODALITY_AUDIO | MODALITY_THREE_D;

    uint256 public constant MAX_URI_BYTES = 256;
    uint256 public constant MAX_RECIPE_MODELS = 8;
    uint256 public constant MAX_PAGE_SIZE = 100;
    uint48 public constant DEFAULT_ADMIN_TRANSFER_DELAY = 2 days;

    struct ModelInput {
        bytes32 manifestHash;
        bytes32 artifactRoot;
        bytes32 slug;
        bytes32 versionHash;
        uint32 modalityMask;
        uint32 minVramMiB;
        address publisher;
        string manifestURI;
    }

    struct ModelRecord {
        bytes32 manifestHash;
        bytes32 artifactRoot;
        bytes32 slug;
        bytes32 versionHash;
        uint32 modalityMask;
        uint32 minVramMiB;
        uint64 createdAt;
        address publisher;
        bool active;
        string manifestURI;
    }

    struct RecipeInput {
        bytes32 contentHash;
        bytes32 slug;
        bytes32 versionHash;
        uint32 outputModality;
        address publisher;
        string contentURI;
        bytes32[] requiredModelIds;
    }

    struct RecipeRecord {
        bytes32 contentHash;
        bytes32 slug;
        bytes32 versionHash;
        bytes32 requirementsHash;
        uint32 outputModality;
        uint64 createdAt;
        address publisher;
        bool active;
        bool canCreateNfts;
        string contentURI;
    }

    mapping(bytes32 => ModelRecord) private _models;
    mapping(bytes32 => RecipeRecord) private _recipes;
    mapping(bytes32 => bytes32[]) private _recipeRequirements;
    mapping(bytes32 => bytes32) private _modelByRelease;
    mapping(bytes32 => bytes32) private _recipeByRelease;
    bytes32[] private _modelIds;
    bytes32[] private _recipeIds;

    error ZeroAddress();
    error EmptyValue();
    error InvalidModality();
    error URITooLong();
    error RecordExists();
    error ReleaseExists();
    error RecordNotFound();
    error InvalidRequirementCount();
    error RequirementsNotSorted();
    error InactiveRequiredModel();
    error InvalidPageSize();
    error StateUnchanged();

    event ModelRegistered(
        bytes32 indexed modelId,
        bytes32 indexed slug,
        bytes32 indexed versionHash,
        bytes32 artifactRoot,
        uint32 modalityMask,
        address publisher,
        string manifestURI
    );
    event ModelStatusChanged(bytes32 indexed modelId, bool active);
    event RecipeRegistered(
        bytes32 indexed recipeId,
        bytes32 indexed slug,
        bytes32 indexed versionHash,
        bytes32 requirementsHash,
        uint32 outputModality,
        address publisher,
        string contentURI
    );
    event RecipeStatusChanged(bytes32 indexed recipeId, bool active);
    event RecipeNftPermissionChanged(bytes32 indexed recipeId, bool canCreateNfts);

    constructor(address admin, address registrar, address pauser, address nftApprover)
        AccessControlDefaultAdminRules(DEFAULT_ADMIN_TRANSFER_DELAY, admin)
    {
        if (
            admin == address(0) || registrar == address(0) || pauser == address(0)
                || nftApprover == address(0)
        ) revert ZeroAddress();

        _grantRole(REGISTRAR_ROLE, registrar);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(NFT_APPROVER_ROLE, nftApprover);
    }

    function registerModel(ModelInput calldata input)
        external
        onlyRole(REGISTRAR_ROLE)
        whenNotPaused
        returns (bytes32 modelId)
    {
        if (
            input.manifestHash == bytes32(0) || input.artifactRoot == bytes32(0)
                || input.slug == bytes32(0) || input.versionHash == bytes32(0)
        ) revert EmptyValue();
        if (input.modalityMask == 0 || input.modalityMask & ~KNOWN_MODALITIES != 0) {
            revert InvalidModality();
        }
        if (input.publisher == address(0)) revert ZeroAddress();
        _validateUri(input.manifestURI);

        modelId = input.manifestHash;
        if (_models[modelId].manifestHash != bytes32(0)) revert RecordExists();

        bytes32 releaseKey = _releaseKey(input.slug, input.versionHash);
        if (_modelByRelease[releaseKey] != bytes32(0)) revert ReleaseExists();

        _models[modelId] = ModelRecord({
            manifestHash: input.manifestHash,
            artifactRoot: input.artifactRoot,
            slug: input.slug,
            versionHash: input.versionHash,
            modalityMask: input.modalityMask,
            minVramMiB: input.minVramMiB,
            createdAt: uint64(block.timestamp),
            publisher: input.publisher,
            active: true,
            manifestURI: input.manifestURI
        });
        _modelByRelease[releaseKey] = modelId;
        _modelIds.push(modelId);

        emit ModelRegistered(
            modelId,
            input.slug,
            input.versionHash,
            input.artifactRoot,
            input.modalityMask,
            input.publisher,
            input.manifestURI
        );
    }

    function registerRecipe(RecipeInput calldata input)
        external
        onlyRole(REGISTRAR_ROLE)
        whenNotPaused
        returns (bytes32 recipeId)
    {
        if (
            input.contentHash == bytes32(0) || input.slug == bytes32(0)
                || input.versionHash == bytes32(0)
        ) revert EmptyValue();
        if (input.outputModality == 0 || input.outputModality & ~KNOWN_MODALITIES != 0) {
            revert InvalidModality();
        }
        if (input.publisher == address(0)) revert ZeroAddress();
        _validateUri(input.contentURI);

        uint256 requirementCount = input.requiredModelIds.length;
        if (requirementCount == 0 || requirementCount > MAX_RECIPE_MODELS) {
            revert InvalidRequirementCount();
        }

        recipeId = input.contentHash;
        if (_recipes[recipeId].contentHash != bytes32(0)) revert RecordExists();

        bytes32 releaseKey = _releaseKey(input.slug, input.versionHash);
        if (_recipeByRelease[releaseKey] != bytes32(0)) revert ReleaseExists();

        bytes32 previousModelId = bytes32(0);
        for (uint256 i = 0; i < requirementCount;) {
            bytes32 modelId = input.requiredModelIds[i];
            if (i != 0) {
                if (uint256(modelId) <= uint256(previousModelId)) {
                    revert RequirementsNotSorted();
                }
            }
            if (!_models[modelId].active) revert InactiveRequiredModel();
            previousModelId = modelId;
            unchecked {
                ++i;
            }
        }

        bytes32 requirementsHash = keccak256(abi.encode(input.requiredModelIds));
        _recipes[recipeId] = RecipeRecord({
            contentHash: input.contentHash,
            slug: input.slug,
            versionHash: input.versionHash,
            requirementsHash: requirementsHash,
            outputModality: input.outputModality,
            createdAt: uint64(block.timestamp),
            publisher: input.publisher,
            active: true,
            canCreateNfts: false,
            contentURI: input.contentURI
        });
        _recipeRequirements[recipeId] = input.requiredModelIds;
        _recipeByRelease[releaseKey] = recipeId;
        _recipeIds.push(recipeId);

        emit RecipeRegistered(
            recipeId,
            input.slug,
            input.versionHash,
            requirementsHash,
            input.outputModality,
            input.publisher,
            input.contentURI
        );
    }

    function setModelActive(bytes32 modelId, bool active) external onlyRole(REGISTRAR_ROLE) {
        ModelRecord storage model = _models[modelId];
        if (model.manifestHash == bytes32(0)) revert RecordNotFound();
        if (model.active == active) revert StateUnchanged();
        if (active) _requireNotPaused();
        model.active = active;
        emit ModelStatusChanged(modelId, active);
    }

    function setRecipeActive(bytes32 recipeId, bool active) external onlyRole(REGISTRAR_ROLE) {
        RecipeRecord storage recipe = _recipes[recipeId];
        if (recipe.contentHash == bytes32(0)) revert RecordNotFound();
        if (recipe.active == active) revert StateUnchanged();
        if (active) _requireNotPaused();
        recipe.active = active;
        emit RecipeStatusChanged(recipeId, active);
    }

    function setRecipeNftPermission(bytes32 recipeId, bool canCreateNfts)
        external
        onlyRole(NFT_APPROVER_ROLE)
    {
        RecipeRecord storage recipe = _recipes[recipeId];
        if (recipe.contentHash == bytes32(0)) revert RecordNotFound();
        if (recipe.canCreateNfts == canCreateNfts) revert StateUnchanged();
        if (canCreateNfts) _requireNotPaused();
        recipe.canCreateNfts = canCreateNfts;
        emit RecipeNftPermissionChanged(recipeId, canCreateNfts);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function getModel(bytes32 modelId) external view returns (ModelRecord memory) {
        ModelRecord memory model = _models[modelId];
        if (model.manifestHash == bytes32(0)) revert RecordNotFound();
        return model;
    }

    function getRecipe(bytes32 recipeId) external view returns (RecipeRecord memory) {
        RecipeRecord memory recipe = _recipes[recipeId];
        if (recipe.contentHash == bytes32(0)) revert RecordNotFound();
        return recipe;
    }

    function getRecipeRequirements(bytes32 recipeId) external view returns (bytes32[] memory) {
        if (_recipes[recipeId].contentHash == bytes32(0)) revert RecordNotFound();
        return _recipeRequirements[recipeId];
    }

    function getModelIdByRelease(bytes32 slug, bytes32 versionHash)
        external
        view
        returns (bytes32)
    {
        return _modelByRelease[_releaseKey(slug, versionHash)];
    }

    function getRecipeIdByRelease(bytes32 slug, bytes32 versionHash)
        external
        view
        returns (bytes32)
    {
        return _recipeByRelease[_releaseKey(slug, versionHash)];
    }

    function isModelActive(bytes32 modelId) external view returns (bool) {
        return _models[modelId].active;
    }

    function isRecipeExecutable(bytes32 recipeId) external view returns (bool) {
        return _isRecipeExecutable(recipeId);
    }

    function isRecipeNftEligible(bytes32 recipeId) external view returns (bool) {
        return _recipes[recipeId].canCreateNfts && _isRecipeExecutable(recipeId);
    }

    function _isRecipeExecutable(bytes32 recipeId) private view returns (bool) {
        RecipeRecord storage recipe = _recipes[recipeId];
        if (!recipe.active) return false;
        bytes32[] storage requirements = _recipeRequirements[recipeId];
        uint256 requirementCount = requirements.length;
        for (uint256 i = 0; i < requirementCount;) {
            if (!_models[requirements[i]].active) return false;
            unchecked {
                ++i;
            }
        }
        return requirementCount > 0;
    }

    function modelCount() external view returns (uint256) {
        return _modelIds.length;
    }

    function recipeCount() external view returns (uint256) {
        return _recipeIds.length;
    }

    function listModelIds(uint256 offset, uint256 limit) external view returns (bytes32[] memory) {
        return _page(_modelIds, offset, limit);
    }

    function listRecipeIds(uint256 offset, uint256 limit) external view returns (bytes32[] memory) {
        return _page(_recipeIds, offset, limit);
    }

    function _validateUri(string calldata uri) private pure {
        uint256 length = bytes(uri).length;
        if (length == 0) revert EmptyValue();
        if (length > MAX_URI_BYTES) revert URITooLong();
    }

    function _releaseKey(bytes32 slug, bytes32 versionHash) private pure returns (bytes32) {
        return keccak256(abi.encode(slug, versionHash));
    }

    function _page(bytes32[] storage source, uint256 offset, uint256 limit)
        private
        view
        returns (bytes32[] memory result)
    {
        if (limit == 0 || limit > MAX_PAGE_SIZE) revert InvalidPageSize();
        uint256 sourceLength = source.length;
        if (offset >= sourceLength) return new bytes32[](0);

        uint256 count = limit;
        uint256 remaining = sourceLength - offset;
        if (count > remaining) count = remaining;
        result = new bytes32[](count);
        uint256 sourceIndex = offset;
        for (uint256 i = 0; i < count;) {
            result[i] = source[sourceIndex];
            unchecked {
                ++i;
                ++sourceIndex;
            }
        }
    }
}
