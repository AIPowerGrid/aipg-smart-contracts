// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "../contracts/grid/Grid.sol";
import "../contracts/grid/interfaces/IModuleManager.sol";
import "../contracts/grid/libraries/GridStorage.sol";
import "../contracts/grid/modules/ModuleInspector.sol";
import "../contracts/grid/modules/ModuleManager.sol";
import "../contracts/grid/modules/Ownership.sol";
import "../contracts/grid/modules/WorkerRegistry.sol";
import "./utils/MockAIPG.sol";

/// @dev Reproduces the six-selector WorkerRegistry currently routed on Base.
/// It intentionally keeps immediate withdrawal so the test proves the cut
/// changes behavior without moving legacy AppStorage.
contract LegacyWorkerRegistry {
    function registerWorker(uint256 bondAmount) external {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        require(!s.workers[msg.sender].isActive, "legacy: already registered");
        require(bondAmount >= s.minBondAmount, "legacy: insufficient bond");
        require(
            MockAIPG(s.aipgToken).transferFrom(msg.sender, address(this), bondAmount),
            "legacy: transfer failed"
        );

        GridStorage.Worker storage worker = s.workers[msg.sender];
        bool firstRegistration = worker.workerAddress == address(0);
        worker.workerAddress = msg.sender;
        worker.bondAmount = bondAmount;
        worker.registeredAt = block.timestamp;
        worker.isActive = true;
        if (firstRegistration) s.workerList.push(msg.sender);
        s.totalBonded += bondAmount;
    }

    function unbond() external {
        GridStorage.AppStorage storage s = GridStorage.appStorage();
        GridStorage.Worker storage worker = s.workers[msg.sender];
        require(worker.isActive, "legacy: not registered");
        uint256 amount = worker.bondAmount;
        worker.bondAmount = 0;
        worker.isActive = false;
        s.totalBonded -= amount;
        require(MockAIPG(s.aipgToken).transfer(msg.sender, amount), "legacy: transfer failed");
    }

    function getWorker(address worker) external view returns (GridStorage.Worker memory) {
        return GridStorage.appStorage().workers[worker];
    }

    function isWorkerActive(address worker) external view returns (bool) {
        return GridStorage.appStorage().workers[worker].isActive;
    }

    function getTotalBonded() external view returns (uint256) {
        return GridStorage.appStorage().totalBonded;
    }

    function getMinBond() external view returns (uint256) {
        return GridStorage.appStorage().minBondAmount;
    }
}

contract WorkerRegistryUpgradeTest is Test {
    uint256 private constant MIN_BOND = 100 ether;
    uint256 private constant BOND = 1_000 ether;

    address private admin = makeAddr("admin");
    address private worker = makeAddr("legacy-worker");
    address payable private grid;
    MockAIPG private token;
    LegacyWorkerRegistry private legacy;
    ModuleManager private manager;
    ModuleInspector private inspector;

    function setUp() public {
        token = new MockAIPG();
        manager = new ModuleManager();
        inspector = new ModuleInspector();
        Ownership ownership = new Ownership();
        legacy = new LegacyWorkerRegistry();

        IModuleManager.ModuleCut[] memory initialCut = new IModuleManager.ModuleCut[](4);
        initialCut[0] = _cut(address(manager), _one(IModuleManager.updateModules.selector));
        initialCut[1] = _cut(address(inspector), _inspectorSelectors());
        initialCut[2] = _cut(address(ownership), _ownershipSelectors());
        initialCut[3] = _cut(address(legacy), _legacySelectors());

        Grid.GridArgs memory args =
            Grid.GridArgs({owner: admin, aipgToken: address(token), stakingVault: address(0)});
        grid = payable(address(new Grid(initialCut, args)));
        _storeAppValue(20, bytes32(MIN_BOND));
        _storeAppValue(21, bytes32(uint256(uint160(address(token)))));

        token.mint(worker, BOND);
        vm.startPrank(worker);
        token.approve(grid, BOND);
        LegacyWorkerRegistry(grid).registerWorker(BOND);
        vm.stopPrank();
    }

    function test_upgradePreservesLegacyBondAndMovesEverySelector() public {
        GridStorage.Worker memory beforeWorker = LegacyWorkerRegistry(grid).getWorker(worker);
        assertEq(beforeWorker.workerAddress, worker);
        assertEq(beforeWorker.bondAmount, BOND);
        assertEq(beforeWorker.unbondingAt, 0);
        assertEq(LegacyWorkerRegistry(grid).getTotalBonded(), BOND);
        assertEq(token.balanceOf(grid), BOND);

        WorkerRegistry candidate = new WorkerRegistry();
        IModuleManager.ModuleCut[] memory upgrade = new IModuleManager.ModuleCut[](2);
        upgrade[0] = IModuleManager.ModuleCut({
            moduleAddress: address(candidate),
            action: IModuleManager.ModuleAction.Replace,
            functionSelectors: _legacySelectors()
        });
        upgrade[1] = IModuleManager.ModuleCut({
            moduleAddress: address(candidate),
            action: IModuleManager.ModuleAction.Add,
            functionSelectors: _newSelectors()
        });

        vm.prank(admin);
        ModuleManager(grid).updateModules(upgrade, address(0), "");

        bytes4[] memory oldRoutes = ModuleInspector(grid).moduleFunctionSelectors(address(legacy));
        bytes4[] memory newRoutes =
            ModuleInspector(grid).moduleFunctionSelectors(address(candidate));
        assertEq(oldRoutes.length, 0, "legacy facet retained a routed selector");
        assertEq(newRoutes.length, 16, "candidate did not receive the full reviewed surface");
        for (uint256 i; i < newRoutes.length; i++) {
            assertEq(ModuleInspector(grid).moduleAddress(newRoutes[i]), address(candidate));
        }

        WorkerRegistry registry = WorkerRegistry(grid);
        GridStorage.Worker memory afterWorker = registry.getWorker(worker);
        assertEq(afterWorker.workerAddress, beforeWorker.workerAddress);
        assertEq(afterWorker.bondAmount, beforeWorker.bondAmount);
        assertEq(afterWorker.registeredAt, beforeWorker.registeredAt);
        assertEq(afterWorker.unbondingAt, 0);
        assertTrue(afterWorker.isActive);
        assertFalse(afterWorker.isSlashed);
        assertEq(registry.getWorkerCount(), 1);
        assertEq(registry.getWorkerAt(0), worker);
        assertEq(registry.getTotalBonded(), BOND);
        assertEq(token.balanceOf(grid), BOND);

        vm.prank(worker);
        registry.unbond();
        assertFalse(registry.isWorkerActive(worker));
        assertEq(registry.getTotalBonded(), BOND, "new unbond returned legacy collateral early");
        assertEq(token.balanceOf(grid), BOND);

        vm.warp(block.timestamp + 7 days);
        vm.prank(worker);
        registry.withdrawBond();
        assertEq(registry.getTotalBonded(), 0);
        assertEq(token.balanceOf(worker), BOND);
    }

    function _storeAppValue(uint256 offset, bytes32 value) private {
        bytes32 base = keccak256("aipg.grid.storage");
        vm.store(grid, bytes32(uint256(base) + offset), value);
    }

    function _cut(address facet, bytes4[] memory selectors)
        private
        pure
        returns (IModuleManager.ModuleCut memory)
    {
        return IModuleManager.ModuleCut({
            moduleAddress: facet,
            action: IModuleManager.ModuleAction.Add,
            functionSelectors: selectors
        });
    }

    function _one(bytes4 selector) private pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = selector;
    }

    function _inspectorSelectors() private pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = ModuleInspector.modules.selector;
        selectors[1] = ModuleInspector.moduleFunctionSelectors.selector;
        selectors[2] = ModuleInspector.moduleAddresses.selector;
        selectors[3] = ModuleInspector.moduleAddress.selector;
    }

    function _ownershipSelectors() private pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = Ownership.transferOwnership.selector;
        selectors[1] = Ownership.owner.selector;
    }

    function _legacySelectors() private pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](6);
        selectors[0] = LegacyWorkerRegistry.getMinBond.selector;
        selectors[1] = LegacyWorkerRegistry.getTotalBonded.selector;
        selectors[2] = LegacyWorkerRegistry.getWorker.selector;
        selectors[3] = LegacyWorkerRegistry.isWorkerActive.selector;
        selectors[4] = LegacyWorkerRegistry.registerWorker.selector;
        selectors[5] = LegacyWorkerRegistry.unbond.selector;
    }

    function _newSelectors() private pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](10);
        selectors[0] = WorkerRegistry.cancelUnbond.selector;
        selectors[1] = WorkerRegistry.getUnbondInfo.selector;
        selectors[2] = WorkerRegistry.getWorkerAt.selector;
        selectors[3] = WorkerRegistry.getWorkerCount.selector;
        selectors[4] = WorkerRegistry.isSlashEvidenceUsed.selector;
        selectors[5] = WorkerRegistry.setMinBond.selector;
        selectors[6] = WorkerRegistry.setUnbondingPeriod.selector;
        selectors[7] = WorkerRegistry.slash.selector;
        selectors[8] = WorkerRegistry.unbondingPeriod.selector;
        selectors[9] = WorkerRegistry.withdrawBond.selector;
    }
}
