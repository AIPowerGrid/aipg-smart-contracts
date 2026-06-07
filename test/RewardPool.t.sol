// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "./utils/DiamondHarness.sol";

contract RewardPoolTest is DiamondHarness {
    function test_depositRewards_pullsTokensAndIncrementsTotals() public {
        aipg.mint(user, 10_000 ether);

        vm.startPrank(user);
        aipg.approve(grid, 1_000 ether);
        pool.depositRewards(1_000 ether);
        vm.stopPrank();

        assertEq(pool.poolBalance(), 1_000 ether);
        assertEq(pool.totalDeposited(), 1_000 ether);
        assertEq(aipg.balanceOf(grid), 1_000 ether);
    }

    function test_depositRewards_zeroReverts() public {
        vm.expectRevert(bytes("RewardPool: zero amount"));
        pool.depositRewards(0);
    }

    function test_setPeriodAllocation_requiresRewardAdmin() public {
        vm.prank(user);
        vm.expectRevert(bytes("RewardPool: not reward admin"));
        pool.setPeriodAllocation(100 ether, "user is not admin");
    }

    function test_setPeriodAllocation_initialSetIsUnbounded() public {
        vm.prank(pricingAdmin);
        pool.setPeriodAllocation(4_080 ether, "launch");
        assertEq(pool.periodAllocation(), 4_080 ether);
    }

    function test_setPeriodAllocation_cap10xUpward() public {
        // initial 100
        vm.prank(pricingAdmin);
        pool.setPeriodAllocation(100 ether, "init");

        // 10x ok
        vm.prank(pricingAdmin);
        pool.setPeriodAllocation(1_000 ether, "ramp 10x");
        assertEq(pool.periodAllocation(), 1_000 ether);

        // 10x + 1 wei not ok
        vm.prank(pricingAdmin);
        vm.expectRevert(bytes("RewardPool: change too large"));
        pool.setPeriodAllocation(10_000 ether + 1, "too big");
    }

    function test_setPeriodAllocation_cap10xDownward() public {
        vm.prank(pricingAdmin);
        pool.setPeriodAllocation(1_000 ether, "init");

        // 1/10 ok
        vm.prank(pricingAdmin);
        pool.setPeriodAllocation(100 ether, "ramp down 10x");
        assertEq(pool.periodAllocation(), 100 ether);

        // 1/11 not ok (would be smaller than current/10)
        vm.prank(pricingAdmin);
        vm.expectRevert(bytes("RewardPool: change too small"));
        pool.setPeriodAllocation(9 ether, "too small");
    }

    function test_setPeriodAllocation_canBeRaisedFromZero() public {
        // After dropping to 0, the next set is unbounded.
        vm.prank(pricingAdmin);
        pool.setPeriodAllocation(100 ether, "init");

        // 0 is allowed (it's <= current * 10 and current * 10 >= 0 is true).
        vm.prank(pricingAdmin);
        pool.setPeriodAllocation(0, "halt");

        // From zero, the bounds short-circuit (current == 0).
        vm.prank(pricingAdmin);
        pool.setPeriodAllocation(50_000 ether, "restart big");
        assertEq(pool.periodAllocation(), 50_000 ether);
    }

    function test_setPeriodLength_bounds() public {
        vm.prank(pricingAdmin);
        vm.expectRevert(bytes("RewardPool: bad period"));
        pool.setPeriodLength(59);

        vm.prank(pricingAdmin);
        vm.expectRevert(bytes("RewardPool: bad period"));
        pool.setPeriodLength(8 days);

        vm.prank(pricingAdmin);
        pool.setPeriodLength(60);
        assertEq(pool.periodLengthSeconds(), 60);

        vm.prank(pricingAdmin);
        pool.setPeriodLength(7 days);
        assertEq(pool.periodLengthSeconds(), 7 days);
    }

    function test_defaultPeriodIsOneDay() public {
        // Without a setPeriodLength call, currentPeriodId divides by 86400.
        assertEq(pool.currentPeriodId(), block.timestamp / 86400);
        assertEq(pool.periodLengthSeconds(), 86400);
    }

    function test_pauseBlocksDeposits() public {
        vm.prank(pauser);
        roles.pause();

        aipg.mint(user, 1_000 ether);
        vm.startPrank(user);
        aipg.approve(grid, 1_000 ether);
        vm.expectRevert(bytes("RewardPool: paused"));
        pool.depositRewards(1_000 ether);
        vm.stopPrank();
    }
}
