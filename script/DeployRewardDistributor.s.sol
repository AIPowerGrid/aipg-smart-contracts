// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/grid/GridRewardDistributor.sol";

/**
 * @title DeployRewardDistributor
 * @notice Deploys the standalone USDC worker-payout distributor on Base.
 *
 * Env:
 *   PAYOUT_TOKEN   ERC20 to pay workers (default = native USDC on Base mainnet)
 *   DIST_ADMIN     DEFAULT_ADMIN + PAUSER (USE A SAFE MULTISIG). Defaults to broadcaster.
 *   DIST_REPORTER  optional: address granted REPORTER_ROLE (the settlement bot)
 *   DIST_ALLOCATION optional: initial per-period allocation in USDC base units (6 dp)
 *
 * Dry-run against a Base mainnet fork (no broadcast, spends nothing):
 *   forge script script/DeployRewardDistributor.s.sol --fork-url $BASE_RPC_URL
 *
 * Real deploy with a Ledger:
 *   forge script script/DeployRewardDistributor.s.sol \
 *     --rpc-url base --ledger --sender 0xYourAdmin --broadcast --verify
 */
contract DeployRewardDistributor is Script {
    // Native USDC on Base mainnet.
    address constant BASE_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    function run() external {
        address token = vm.envOr("PAYOUT_TOKEN", BASE_USDC);
        address admin = vm.envOr("DIST_ADMIN", msg.sender);
        address reporter = vm.envOr("DIST_REPORTER", address(0));
        uint256 allocation = vm.envOr("DIST_ALLOCATION", uint256(0));

        require(token != address(0), "token required");
        require(admin != address(0), "admin required");

        vm.startBroadcast();

        GridRewardDistributor dist = new GridRewardDistributor(IERC20(token), admin);
        console2.log("GridRewardDistributor:", address(dist));
        console2.log("  payoutToken:", token);
        console2.log("  admin:", admin);

        // These only succeed if the broadcaster holds DEFAULT_ADMIN_ROLE — i.e.
        // the broadcaster == admin. With a separate Safe admin, run them from the Safe.
        if (reporter != address(0) && admin == msg.sender) {
            dist.grantRole(dist.REPORTER_ROLE(), reporter);
            console2.log("  REPORTER_ROLE ->", reporter);
        }
        if (allocation > 0 && admin == msg.sender) {
            dist.setPeriodAllocation(allocation, "initial");
            console2.log("  periodAllocation:", allocation);
        }

        vm.stopBroadcast();
    }
}
