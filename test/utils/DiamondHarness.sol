// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "../../contracts/grid/Grid.sol";
import "../../contracts/grid/modules/ModuleManager.sol";
import "../../contracts/grid/modules/ModuleInspector.sol";
import "../../contracts/grid/modules/Ownership.sol";
import "../../contracts/grid/modules/RoleManager.sol";
import "../../contracts/grid/modules/WorkerRegistry.sol";
import "../../contracts/grid/modules/RewardPool.sol";
import "../../contracts/grid/modules/DenReporter.sol";
import "../../contracts/grid/modules/PaymentRouter.sol";
import "../../contracts/grid/libraries/GridStorage.sol";
import "../../contracts/grid/interfaces/IModuleManager.sol";

import "./MockAIPG.sol";

/**
 * @title DiamondHarness
 * @dev Test base that deploys a fresh Grid Diamond with the reward facets cut
 *      in and roles wired up. Most tests should inherit this and call the
 *      `grid` address through the facet's contract interface to exercise the
 *      production routing path (delegatecall through the proxy).
 *
 *      Why a harness: facets use AppStorage and can't be tested in isolation
 *      meaningfully — they assume they're delegatecalled with the Diamond's
 *      storage slot. Testing through the Diamond catches selector clashes,
 *      role wiring, and storage layout bugs that unit tests would miss.
 */
abstract contract DiamondHarness is Test {
    // Actors. Use distinct addresses so role gating is exercised.
    address internal admin = makeAddr("admin");
    address internal pricingAdmin = makeAddr("pricingAdmin");
    address internal reporter = makeAddr("reporter");
    address internal pauser = makeAddr("pauser");
    address internal user = makeAddr("user");
    address internal worker1 = makeAddr("worker1");
    address internal worker2 = makeAddr("worker2");
    address internal worker3 = makeAddr("worker3");

    // Diamond + facet addresses (post-cut, callable through `grid`)
    address payable internal grid;
    MockAIPG internal aipg;

    // Convenience interfaces for calling facet selectors on the Diamond
    RoleManager internal roles;
    RewardPool internal pool;
    DenReporter internal reporterFacet;
    PaymentRouter internal payments;
    WorkerRegistry internal workerReg;

    function setUp() public virtual {
        // Deploy mock token
        aipg = new MockAIPG();

        // Deploy facets
        ModuleManager mm = new ModuleManager();
        ModuleInspector mi = new ModuleInspector();
        Ownership own = new Ownership();
        RoleManager rm = new RoleManager();
        WorkerRegistry wr = new WorkerRegistry();
        RewardPool rp = new RewardPool();
        DenReporter dr = new DenReporter();
        PaymentRouter pr = new PaymentRouter();

        // Build the initial module cut. Each entry advertises which selectors
        // it serves.
        IModuleManager.ModuleCut[] memory cut = new IModuleManager.ModuleCut[](8);
        cut[0] = _cut(address(mm), _selectorsModuleManager());
        cut[1] = _cut(address(mi), _selectorsModuleInspector());
        cut[2] = _cut(address(own), _selectorsOwnership());
        cut[3] = _cut(address(rm), _selectorsRoleManager());
        cut[4] = _cut(address(wr), _selectorsWorkerRegistry());
        cut[5] = _cut(address(rp), _selectorsRewardPool());
        cut[6] = _cut(address(dr), _selectorsDenReporter());
        cut[7] = _cut(address(pr), _selectorsPaymentRouter());

        Grid.GridArgs memory args = Grid.GridArgs({
            owner: admin,
            aipgToken: address(aipg),
            stakingVault: address(0)
        });

        // Deploy the Diamond with the initial cut applied in the constructor.
        Grid g = new Grid(cut, args);
        grid = payable(address(g));

        // The AppStorage `aipgToken` field is read by RewardPool / PaymentRouter
        // but the Grid constructor doesn't set it. Wire it explicitly via a
        // small init facet that pokes storage. For tests, we set it through a
        // privileged call we add to a test-only helper. To keep things simple,
        // assign it via vm.store on the canonical slot.
        _setAipgTokenInDiamondStorage(address(aipg));

        // Grant admin role to `admin` so we can grant other roles.
        _grantRoleAtDiamondStorage(GridStorage.ADMIN_ROLE, admin);

        roles = RoleManager(grid);
        pool = RewardPool(grid);
        reporterFacet = DenReporter(grid);
        payments = PaymentRouter(grid);
        workerReg = WorkerRegistry(grid);

        // Wire the remaining roles via the public RoleManager surface to
        // exercise the production path.
        vm.startPrank(admin);
        roles.grantRole(GridStorage.REWARD_ADMIN_ROLE, pricingAdmin);
        roles.grantRole(GridStorage.REPORTER_ROLE, reporter);
        roles.grantRole(GridStorage.PAUSER_ROLE, pauser);
        vm.stopPrank();
    }

    // -------- selector lists --------
    // Hand-built rather than computed to keep test compile times short.

    function _selectorsModuleManager() private pure returns (bytes4[] memory s) {
        s = new bytes4[](1);
        s[0] = IModuleManager.updateModules.selector;
    }

    function _selectorsModuleInspector() private pure returns (bytes4[] memory s) {
        s = new bytes4[](4);
        s[0] = ModuleInspector.modules.selector;
        s[1] = ModuleInspector.moduleFunctionSelectors.selector;
        s[2] = ModuleInspector.moduleAddresses.selector;
        s[3] = ModuleInspector.moduleAddress.selector;
    }

    function _selectorsOwnership() private pure returns (bytes4[] memory s) {
        s = new bytes4[](2);
        s[0] = Ownership.transferOwnership.selector;
        s[1] = Ownership.owner.selector;
    }

    function _selectorsRoleManager() private pure returns (bytes4[] memory s) {
        s = new bytes4[](11);
        s[0] = RoleManager.grantRole.selector;
        s[1] = RoleManager.revokeRole.selector;
        s[2] = RoleManager.hasRole.selector;
        s[3] = RoleManager.pause.selector;
        s[4] = RoleManager.unpause.selector;
        s[5] = RoleManager.isPaused.selector;
        s[6] = RoleManager.ADMIN_ROLE.selector;
        s[7] = RoleManager.PAUSER_ROLE.selector;
        s[8] = RoleManager.REWARD_ADMIN_ROLE.selector;
        s[9] = RoleManager.REPORTER_ROLE.selector;
        s[10] = RoleManager.ANCHOR_ROLE.selector;
    }

    function _selectorsWorkerRegistry() private pure returns (bytes4[] memory s) {
        s = new bytes4[](5);
        s[0] = WorkerRegistry.registerWorker.selector;
        s[1] = WorkerRegistry.unbond.selector;
        s[2] = WorkerRegistry.getWorker.selector;
        s[3] = WorkerRegistry.isWorkerActive.selector;
        s[4] = WorkerRegistry.getTotalBonded.selector;
    }

    function _selectorsRewardPool() private pure returns (bytes4[] memory s) {
        s = new bytes4[](9);
        s[0] = RewardPool.depositRewards.selector;
        s[1] = RewardPool.setPeriodAllocation.selector;
        s[2] = RewardPool.setPeriodLength.selector;
        s[3] = RewardPool.poolBalance.selector;
        s[4] = RewardPool.totalDeposited.selector;
        s[5] = RewardPool.totalPaidOut.selector;
        s[6] = RewardPool.periodAllocation.selector;
        s[7] = RewardPool.currentPeriodId.selector;
        s[8] = RewardPool.periodLengthSeconds.selector;
    }

    function _selectorsDenReporter() private pure returns (bytes4[] memory s) {
        s = new bytes4[](3);
        s[0] = DenReporter.reportPeriod.selector;
        s[1] = DenReporter.getReport.selector;
        s[2] = DenReporter.isReported.selector;
    }

    function _selectorsPaymentRouter() private pure returns (bytes4[] memory s) {
        s = new bytes4[](4);
        s[0] = PaymentRouter.claim.selector;
        s[1] = PaymentRouter.claimBatch.selector;
        s[2] = PaymentRouter.previewClaim.selector;
        s[3] = PaymentRouter.isClaimed.selector;
    }

    function _cut(address addr, bytes4[] memory sels)
        private
        pure
        returns (IModuleManager.ModuleCut memory)
    {
        return IModuleManager.ModuleCut({
            moduleAddress: addr,
            action: IModuleManager.ModuleAction.Add,
            functionSelectors: sels
        });
    }

    /**
     * @dev Direct storage poke for AppStorage.aipgToken. The Diamond
     *      constructor doesn't take this, and the production deploy path
     *      sets it via an init function on a real ModelVault deploy script.
     *      Tests don't need that surface, so we write directly.
     */
    function _setAipgTokenInDiamondStorage(address token) internal {
        bytes32 base = keccak256("aipg.grid.storage");
        // AppStorage struct layout (from GridStorage.sol):
        //   slot 0:  mapping roles
        //   slot 1:  mapping roleAdmin
        //   slot 2:  uint modelIdCounter
        //   slot 3:  mapping models
        //   slot 4:  mapping hashToModelId
        //   slot 5:  mapping modelConstraints
        //   slot 6:  uint nextRecipeId
        //   slot 7:  uint totalRecipes
        //   slot 8:  mapping recipes
        //   slot 9:  mapping recipeRootToId
        //   slot 10: mapping creatorRecipes
        //   slot 11: uint maxWorkflowBytes
        //   slot 12: mapping dailyAnchors
        //   slot 13: mapping anchoredJobIds
        //   slot 14: mapping workerJobDays
        //   slot 15: uint totalAnchoredJobs
        //   slot 16: uint totalAnchoredRewards
        //   slot 17: mapping workers
        //   slot 18: array workerList
        //   slot 19: uint totalBonded
        //   slot 20: uint minBondAmount
        //   slot 21: uint totalDeposited
        //   slot 22: uint totalPaidOut
        //   slot 23: uint periodAllocation
        //   slot 24: uint periodLengthSeconds
        //   slot 25: mapping periodReports
        //   slot 26: mapping periodClaimed
        //   slot 27: address aipgToken
        //   slot 28: address stakingVault
        //   slot 29: bool paused
        vm.store(grid, bytes32(uint256(base) + 27), bytes32(uint256(uint160(token))));
    }

    function _grantRoleAtDiamondStorage(bytes32 role, address account) internal {
        // roles is mapping(bytes32 => mapping(address => bool)) at slot 0 of AppStorage.
        bytes32 base = keccak256("aipg.grid.storage");
        bytes32 outerSlot = bytes32(uint256(base) + 0);
        bytes32 innerSlot = keccak256(abi.encode(role, outerSlot));
        bytes32 finalSlot = keccak256(abi.encode(account, innerSlot));
        vm.store(grid, finalSlot, bytes32(uint256(1)));
    }

    // -------- merkle helpers used by PaymentRouter tests --------

    /// Leaf format must match contract: keccak256(abi.encodePacked(worker, den))
    function _leaf(address worker, uint256 den) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(worker, den));
    }

    /// Ordered pair hash matching PaymentRouter._verify
    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a <= b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }
}
