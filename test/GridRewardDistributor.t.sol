// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "../contracts/grid/GridRewardDistributor.sol";

/// @dev USDC-like token: 6 decimals.
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract GridRewardDistributorTest is Test {
    GridRewardDistributor dist;
    MockUSDC usdc;

    address admin = address(0xA11CE);
    address reporter = address(0xB0B);
    address relayer = address(0xCAFE);

    // Workers
    address alice = address(0xA1);
    address bob = address(0xB2);
    address carol = address(0xC3);

    uint256 constant USDC = 1e6; // 1 USDC in base units (6 decimals)

    function setUp() public {
        usdc = new MockUSDC();
        dist = new GridRewardDistributor(IERC20(address(usdc)), admin);
        bytes32 reporterRole = dist.REPORTER_ROLE(); // resolve before prank (nested call would consume it)
        vm.prank(admin);
        dist.grantRole(reporterRole, reporter);
        usdc.mint(address(this), 1_000_000 * USDC);
    }

    // ---------- merkle helpers (match the contract's leaf + sorted-pair) ----------

    function _leaf(address w, uint256 den) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(w, den));
    }

    function _pair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a <= b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    // Two-leaf tree
    function _root2(bytes32 la, bytes32 lb) internal pure returns (bytes32) {
        return _pair(la, lb);
    }

    function _fund(uint256 amount) internal {
        usdc.approve(address(dist), amount);
        dist.fund(amount);
    }

    function _setAlloc(uint256 amount) internal {
        vm.prank(admin);
        dist.setPeriodAllocation(amount, "test");
    }

    function _report(uint256 periodId, bytes32 root, uint256 totalDen) internal {
        vm.prank(reporter);
        dist.reportPeriod(periodId, root, totalDen, "ipfs://x");
    }

    // ---------- funding ----------

    function test_fund_incrementsBalance() public {
        _fund(500 * USDC);
        assertEq(dist.poolBalance(), 500 * USDC);
    }

    // ---------- access control ----------

    function test_setAllocation_onlyAdmin() public {
        vm.prank(relayer);
        vm.expectRevert();
        dist.setPeriodAllocation(100 * USDC, "nope");
    }

    function test_report_onlyReporter() public {
        _fund(100 * USDC);
        _setAlloc(100 * USDC);
        vm.prank(relayer);
        vm.expectRevert();
        dist.reportPeriod(1, _root2(_leaf(alice, 1), _leaf(bob, 1)), 2, "");
    }

    // ---------- reporting guards ----------

    function test_report_revertsIfUnderfunded() public {
        _setAlloc(100 * USDC);
        _fund(99 * USDC); // less than allocation
        bytes32 root = _root2(_leaf(alice, 60e6), _leaf(bob, 40e6));
        vm.prank(reporter);
        vm.expectRevert("Distributor: pool underfunded");
        dist.reportPeriod(1, root, 100e6, "");
    }

    // Regression (P0): a second period must not re-commit funds already owed to an
    // earlier reported-but-unpaid period. Funding for ONE period, reporting TWO,
    // the second report must revert — otherwise both promise the same USDC.
    function test_report_cannotOvercommitAcrossPeriods() public {
        _setAlloc(100 * USDC);
        _fund(100 * USDC); // exactly one period's worth
        bytes32 root = _root2(_leaf(alice, 60e6), _leaf(bob, 40e6));
        _report(1, root, 100e6); // commits all 100 USDC
        // Period 2 has no free balance behind it (committed 100, paid 0).
        vm.prank(reporter);
        vm.expectRevert("Distributor: pool underfunded");
        dist.reportPeriod(2, root, 100e6, "");
    }

    // Positive: funding for TWO periods lets both report (and stay fully covered).
    function test_report_twoPeriodsWhenFullyFunded() public {
        _setAlloc(100 * USDC);
        _fund(200 * USDC);
        bytes32 root = _root2(_leaf(alice, 60e6), _leaf(bob, 40e6));
        _report(1, root, 100e6);
        _report(2, root, 100e6); // 200 balance covers 100 committed + 100 new
        assertEq(dist.totalCommitted(), 200 * USDC);
    }

    function test_report_revertsZeroAllocation() public {
        _fund(100 * USDC);
        bytes32 root = _root2(_leaf(alice, 60e6), _leaf(bob, 40e6));
        vm.prank(reporter);
        vm.expectRevert("Distributor: zero allocation");
        dist.reportPeriod(1, root, 100e6, "");
    }

    function test_report_noDoubleReport() public {
        _fund(200 * USDC);
        _setAlloc(100 * USDC);
        bytes32 root = _root2(_leaf(alice, 60e6), _leaf(bob, 40e6));
        _report(1, root, 100e6);
        vm.prank(reporter);
        vm.expectRevert("Distributor: period exists");
        dist.reportPeriod(1, root, 100e6, "");
    }

    // ---------- happy path claims ----------

    function test_claim_paysCorrectShares() public {
        _fund(100 * USDC);
        _setAlloc(100 * USDC);
        bytes32 la = _leaf(alice, 60e6);
        bytes32 lb = _leaf(bob, 40e6);
        _report(1, _root2(la, lb), 100e6);

        bytes32[] memory proofA = new bytes32[](1);
        proofA[0] = lb;
        bytes32[] memory proofB = new bytes32[](1);
        proofB[0] = la;

        vm.prank(relayer);
        dist.claim(1, alice, 60e6, proofA);
        vm.prank(relayer);
        dist.claim(1, bob, 40e6, proofB);

        assertEq(usdc.balanceOf(alice), 60 * USDC); // 60% of 100 USDC
        assertEq(usdc.balanceOf(bob), 40 * USDC);
        assertEq(dist.totalPaidOut(), 100 * USDC);
        assertEq(dist.poolBalance(), 0);
    }

    function test_claim_doubleClaimReverts() public {
        _fund(100 * USDC);
        _setAlloc(100 * USDC);
        bytes32 la = _leaf(alice, 60e6);
        bytes32 lb = _leaf(bob, 40e6);
        _report(1, _root2(la, lb), 100e6);
        bytes32[] memory proofA = new bytes32[](1);
        proofA[0] = lb;

        dist.claim(1, alice, 60e6, proofA);
        vm.expectRevert("Distributor: already claimed");
        dist.claim(1, alice, 60e6, proofA);
    }

    function test_claim_badProofReverts() public {
        _fund(100 * USDC);
        _setAlloc(100 * USDC);
        bytes32 la = _leaf(alice, 60e6);
        bytes32 lb = _leaf(bob, 40e6);
        _report(1, _root2(la, lb), 100e6);
        bytes32[] memory bad = new bytes32[](1);
        bad[0] = keccak256("garbage");
        vm.expectRevert("Distributor: bad proof");
        dist.claim(1, alice, 60e6, bad);
    }

    function test_claim_wrongDenReverts() public {
        _fund(100 * USDC);
        _setAlloc(100 * USDC);
        bytes32 la = _leaf(alice, 60e6);
        bytes32 lb = _leaf(bob, 40e6);
        _report(1, _root2(la, lb), 100e6);
        bytes32[] memory proofA = new bytes32[](1);
        proofA[0] = lb;
        // Claim alice with bob's den -> leaf mismatch -> bad proof.
        vm.expectRevert("Distributor: bad proof");
        dist.claim(1, alice, 40e6, proofA);
    }

    // ---------- batch ----------

    function test_claimBatch_paysAllAndSkipsClaimed() public {
        _fund(100 * USDC);
        _setAlloc(100 * USDC);
        bytes32 la = _leaf(alice, 60e6);
        bytes32 lb = _leaf(bob, 40e6);
        _report(1, _root2(la, lb), 100e6);

        // Pre-claim alice individually.
        bytes32[] memory proofA = new bytes32[](1);
        proofA[0] = lb;
        dist.claim(1, alice, 60e6, proofA);

        // Batch both: alice skipped (already claimed), bob paid.
        address[] memory ws = new address[](2);
        ws[0] = alice;
        ws[1] = bob;
        uint256[] memory ds = new uint256[](2);
        ds[0] = 60e6;
        ds[1] = 40e6;
        bytes32[][] memory ps = new bytes32[][](2);
        ps[0] = proofA;
        bytes32[] memory proofB = new bytes32[](1);
        proofB[0] = la;
        ps[1] = proofB;

        vm.prank(relayer);
        dist.claimBatch(1, ws, ds, ps);

        assertEq(usdc.balanceOf(alice), 60 * USDC);
        assertEq(usdc.balanceOf(bob), 40 * USDC);
    }

    function test_claimBatch_lengthMismatchReverts() public {
        _fund(100 * USDC);
        _setAlloc(100 * USDC);
        _report(1, _root2(_leaf(alice, 60e6), _leaf(bob, 40e6)), 100e6);
        address[] memory ws = new address[](2);
        uint256[] memory ds = new uint256[](1);
        bytes32[][] memory ps = new bytes32[][](2);
        vm.expectRevert("Distributor: length mismatch");
        dist.claimBatch(1, ws, ds, ps);
    }

    // ---------- SECURITY: overpay cap bounds a corrupt report ----------

    // A malicious/buggy reporter understates totalDen so each claimer's share is
    // inflated. The per-period cap must stop the period from paying out more than
    // its allocation, protecting OTHER periods' funds sitting in the same pool.
    function test_overpayCap_boundsBadReportToItsAllocation() public {
        // Fund TWO periods' worth.
        _fund(200 * USDC);
        _setAlloc(100 * USDC);

        // Period 1: two workers, each den=100e6 (true total 200e6), but the
        // reporter LIES totalDen=100e6 so each computes a 100-USDC (whole-alloc) share.
        bytes32 la = _leaf(alice, 100e6);
        bytes32 lb = _leaf(bob, 100e6);
        _report(1, _root2(la, lb), 100e6); // <-- understated totalDen

        bytes32[] memory proofA = new bytes32[](1);
        proofA[0] = lb;
        bytes32[] memory proofB = new bytes32[](1);
        proofB[0] = la;

        // Alice drains the period's whole 100-USDC allocation.
        dist.claim(1, alice, 100e6, proofA);
        assertEq(usdc.balanceOf(alice), 100 * USDC);

        // Bob's claim would exceed period 1's allocation -> hard revert, so the
        // other period's 100 USDC is untouched.
        vm.expectRevert("Distributor: period overpay");
        dist.claim(1, bob, 100e6, proofB);

        assertEq(dist.poolBalance(), 100 * USDC); // period 2's funds safe
    }

    // ---------- SECURITY: admin cannot withdraw committed worker funds ----------

    function test_withdraw_cannotTouchCommittedFunds() public {
        _fund(150 * USDC);
        _setAlloc(100 * USDC);
        _report(1, _root2(_leaf(alice, 60e6), _leaf(bob, 40e6)), 100e6);

        // 100 is committed to period 1; only 50 is free.
        vm.prank(admin);
        vm.expectRevert("Distributor: committed funds");
        dist.withdraw(admin, 51 * USDC, "too much");

        // Exactly the free 50 is withdrawable.
        vm.prank(admin);
        dist.withdraw(admin, 50 * USDC, "excess");
        assertEq(usdc.balanceOf(admin), 50 * USDC);
        assertEq(dist.poolBalance(), 100 * USDC); // still covers the claim
    }

    function test_withdraw_onlyAdmin() public {
        _fund(100 * USDC);
        vm.prank(relayer);
        vm.expectRevert();
        dist.withdraw(relayer, 1 * USDC, "nope");
    }

    // ---------- pause ----------

    function test_pause_blocksClaimAndReport() public {
        _fund(100 * USDC);
        _setAlloc(100 * USDC);
        _report(1, _root2(_leaf(alice, 60e6), _leaf(bob, 40e6)), 100e6);

        vm.prank(admin);
        dist.pause();

        bytes32[] memory proofA = new bytes32[](1);
        proofA[0] = _leaf(bob, 40e6);
        vm.expectRevert("Pausable: paused");
        dist.claim(1, alice, 60e6, proofA);

        vm.prank(reporter);
        vm.expectRevert("Pausable: paused");
        dist.reportPeriod(2, _root2(_leaf(alice, 1), _leaf(bob, 1)), 2, "");
    }
}
