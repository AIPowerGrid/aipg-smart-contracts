// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../contracts/grid/GridRewardDistributor.sol";

/**
 * @dev Full settle cycle against REAL native USDC on a Base mainnet fork.
 *      Runs only when BASE_RPC_URL is set; otherwise it no-ops so the normal
 *      `forge test` stays offline.
 *
 *      forge test --match-contract GridRewardDistributorForkTest -vv
 *      (with BASE_RPC_URL exported)
 */
contract GridRewardDistributorForkTest is Test {
    address constant BASE_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    GridRewardDistributor dist;
    IERC20 usdc;

    address admin = address(0xA11CE);
    address reporter = address(0xB0B);
    address alice = address(0xA1);
    address bob = address(0xB2);

    uint256 constant USDC = 1e6;
    bool active;

    function setUp() public {
        string memory rpc = vm.envOr("BASE_RPC_URL", string(""));
        if (bytes(rpc).length == 0) return; // skip when not forking
        vm.createSelectFork(rpc);
        active = true;

        usdc = IERC20(BASE_USDC);
        dist = new GridRewardDistributor(usdc, admin);
        bytes32 rr = dist.REPORTER_ROLE();
        vm.prank(admin);
        dist.grantRole(rr, reporter);

        // Mint real-USDC balance to this test via storage cheat.
        deal(BASE_USDC, address(this), 1_000 * USDC);
    }

    function _leaf(address w, uint256 den) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(w, den));
    }

    function _pair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a <= b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function test_fork_fullSettleCycleWithRealUSDC() public {
        if (!active) {
            emit log("BASE_RPC_URL not set; skipping fork test");
            return;
        }

        // Fund 100 USDC, allocate 100 USDC for the period.
        usdc.approve(address(dist), 100 * USDC);
        dist.fund(100 * USDC);
        vm.prank(admin);
        dist.setPeriodAllocation(100 * USDC, "fork-test");

        // Report a 2-worker root: alice 60% / bob 40%.
        bytes32 la = _leaf(alice, 60e6);
        bytes32 lb = _leaf(bob, 40e6);
        vm.prank(reporter);
        dist.reportPeriod(1, _pair(la, lb), 100e6, "ipfs://fork");

        bytes32[] memory proofA = new bytes32[](1);
        proofA[0] = lb;
        bytes32[] memory proofB = new bytes32[](1);
        proofB[0] = la;

        // Assert payout DELTAS — these are real Base addresses that may already
        // hold USDC on the forked state.
        uint256 aliceBefore = usdc.balanceOf(alice);
        uint256 bobBefore = usdc.balanceOf(bob);

        // Anyone relays; payout lands on the worker in real USDC.
        dist.claim(1, alice, 60e6, proofA);
        dist.claim(1, bob, 40e6, proofB);

        assertEq(usdc.balanceOf(alice) - aliceBefore, 60 * USDC, "alice +60 USDC");
        assertEq(usdc.balanceOf(bob) - bobBefore, 40 * USDC, "bob +40 USDC");
        assertEq(usdc.balanceOf(address(dist)), 0, "pool drained");
        emit log("fork settle cycle OK: real USDC paid to workers");
    }
}
