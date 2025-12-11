// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../libraries/GridStorage.sol";
import "../libraries/LibGrid.sol";

/**
 * @title ModelVault
 * @dev AI model registry with comprehensive metadata
 */
contract ModelVault {
    using GridStorage for GridStorage.AppStorage;

    // ============ EVENTS ============
    
    event ModelRegistered(uint256 indexed modelId, bytes32 indexed modelHash, string name, address creator);
    event ModelUpdated(uint256 indexed modelId, string ipfsCid, string downloadUrl);
    event ModelVersionUpdated(uint256 indexed modelId, string oldVersion, string newVersion);
    event ModelDeprecated(uint256 indexed modelId);
    event ModelReactivated(uint256 indexed modelId);
    event ConstraintsSet(bytes32 indexed modelHash, uint16 stepsMin, uint16 stepsMax);

    // ============ MODIFIERS ============
    
    modifier onlyRegistrar() {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        require(
            s.roles[GridStorage.REGISTRAR_ROLE][msg.sender] ||
            s.roles[GridStorage.ADMIN_ROLE][msg.sender],
            "ModelVault: not registrar"
        );
        _;
    }

    modifier onlyAdmin() {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        require(s.roles[GridStorage.ADMIN_ROLE][msg.sender], "ModelVault: not admin");
        _;
    }

    modifier notPaused() {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        require(!s.paused, "ModelVault: paused");
        _;
    }

    // ============ REGISTRATION ============
    
    function registerModel(
        bytes32 modelHash,
        GridStorage.ModelType modelType,
        string calldata fileName,
        string calldata name,
        string calldata version,
        string calldata ipfsCid,
        string calldata downloadUrl,
        uint256 sizeBytes,
        string calldata quantization,
        string calldata format,
        uint32 vramMB,
        string calldata baseModel,
        bool inpainting,
        bool img2img,
        bool controlnet,
        bool lora,
        bool isNSFW
    ) external onlyRegistrar notPaused returns (uint256 modelId) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        
        require(modelHash != bytes32(0), "ModelVault: empty hash");
        require(bytes(name).length > 0, "ModelVault: empty name");
        require(s.hashToModelId[modelHash] == 0, "ModelVault: hash exists");

        s.modelIdCounter++;
        modelId = s.modelIdCounter;

        GridStorage.Model storage m = s.models[modelId];
        m.modelHash = modelHash;
        m.modelType = modelType;
        m.fileName = fileName;
        m.name = name;
        m.version = version;
        m.ipfsCid = ipfsCid;
        m.downloadUrl = downloadUrl;
        m.sizeBytes = sizeBytes;
        m.quantization = quantization;
        m.format = format;
        m.vramMB = vramMB;
        m.baseModel = baseModel;
        m.inpainting = inpainting;
        m.img2img = img2img;
        m.controlnet = controlnet;
        m.lora = lora;
        m.isActive = true;
        m.isNSFW = isNSFW;
        m.timestamp = block.timestamp;
        m.creator = msg.sender;

        s.hashToModelId[modelHash] = modelId;

        emit ModelRegistered(modelId, modelHash, name, msg.sender);
    }

    // ============ UPDATES ============
    
    function updateStorageLocations(
        uint256 modelId,
        string calldata ipfsCid,
        string calldata downloadUrl
    ) external onlyRegistrar notPaused {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        require(s.models[modelId].modelHash != bytes32(0), "ModelVault: not found");

        s.models[modelId].ipfsCid = ipfsCid;
        s.models[modelId].downloadUrl = downloadUrl;

        emit ModelUpdated(modelId, ipfsCid, downloadUrl);
    }

    function updateVersion(uint256 modelId, string calldata newVersion) external onlyRegistrar notPaused {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        require(s.models[modelId].modelHash != bytes32(0), "ModelVault: not found");

        string memory oldVersion = s.models[modelId].version;
        s.models[modelId].version = newVersion;

        emit ModelVersionUpdated(modelId, oldVersion, newVersion);
    }

    function deprecateModel(uint256 modelId) external onlyRegistrar {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        require(s.models[modelId].modelHash != bytes32(0), "ModelVault: not found");
        require(s.models[modelId].isActive, "ModelVault: already inactive");

        s.models[modelId].isActive = false;

        emit ModelDeprecated(modelId);
    }

    function reactivateModel(uint256 modelId) external onlyAdmin {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        require(s.models[modelId].modelHash != bytes32(0), "ModelVault: not found");
        require(!s.models[modelId].isActive, "ModelVault: already active");

        s.models[modelId].isActive = true;

        emit ModelReactivated(modelId);
    }

    // ============ CONSTRAINTS ============
    
    function setConstraints(
        bytes32 modelHash,
        uint16 stepsMin,
        uint16 stepsMax,
        uint16 cfgMinTenths,
        uint16 cfgMaxTenths,
        uint8 clipSkip,
        bytes32[] calldata allowedSamplers,
        bytes32[] calldata allowedSchedulers
    ) external onlyRegistrar notPaused {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        require(s.hashToModelId[modelHash] != 0, "ModelVault: model not found");

        GridStorage.ModelConstraints storage c = s.modelConstraints[modelHash];
        c.stepsMin = stepsMin;
        c.stepsMax = stepsMax;
        c.cfgMinTenths = cfgMinTenths;
        c.cfgMaxTenths = cfgMaxTenths;
        c.clipSkip = clipSkip;
        c.allowedSamplers = allowedSamplers;
        c.allowedSchedulers = allowedSchedulers;
        c.exists = true;

        emit ConstraintsSet(modelHash, stepsMin, stepsMax);
    }

    // ============ VIEWS ============
    
    function getModel(uint256 modelId) external view returns (GridStorage.Model memory) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        return s.models[modelId];
    }

    function getModelByHash(bytes32 modelHash) external view returns (GridStorage.Model memory) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        uint256 modelId = s.hashToModelId[modelHash];
        return s.models[modelId];
    }

    function getConstraints(bytes32 modelHash) external view returns (GridStorage.ModelConstraints memory) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        return s.modelConstraints[modelHash];
    }

    function isModelExists(uint256 modelId) external view returns (bool) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        return s.models[modelId].modelHash != bytes32(0);
    }

    function isModelActive(uint256 modelId) external view returns (bool) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        return s.models[modelId].isActive;
    }

    function getModelCount() external view returns (uint256) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        return s.modelIdCounter;
    }

    function validateParams(
        bytes32 modelHash,
        uint16 steps,
        uint16 cfgTenths,
        bytes32 sampler,
        bytes32 scheduler
    ) external view returns (bool) {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        GridStorage.ModelConstraints storage c = s.modelConstraints[modelHash];

        if (!c.exists) return true; // No constraints = all valid

        if (steps < c.stepsMin || steps > c.stepsMax) return false;
        if (cfgTenths < c.cfgMinTenths || cfgTenths > c.cfgMaxTenths) return false;

        bool samplerValid = c.allowedSamplers.length == 0;
        for (uint256 i = 0; i < c.allowedSamplers.length; i++) {
            if (c.allowedSamplers[i] == sampler) {
                samplerValid = true;
                break;
            }
        }
        if (!samplerValid) return false;

        bool schedulerValid = c.allowedSchedulers.length == 0;
        for (uint256 i = 0; i < c.allowedSchedulers.length; i++) {
            if (c.allowedSchedulers[i] == scheduler) {
                schedulerValid = true;
                break;
            }
        }
        if (!schedulerValid) return false;

        return true;
    }
}
