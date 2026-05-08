// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {GameItems} from "../src/GameItems.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {Vault} from "../src/Vault.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";

/// @notice One-shot deployment script for the assignment's L2 deployment task.
///         Forge run:
///             forge script script/Deploy.s.sol:Deploy \
///               --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
///               --private-key $PRIVATE_KEY --broadcast --verify
contract Deploy is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        // 1. ERC-1155 game items
        GameItems items = new GameItems("https://game.example/api/{id}.json");
        console2.log("GameItems:", address(items));

        // 2. Underlying for the vault
        MockERC20 usds = new MockERC20("USD Stable", "USDS", 18);
        console2.log("MockERC20 USDS:", address(usds));

        // 3. ERC-4626 vault
        Vault vault = new Vault(IERC20(address(usds)), "Vault USDS", "vUSDS");
        console2.log("Vault:", address(vault));

        // Initial mint so we can immediately exercise the L2 deployment.
        usds.mint(msg.sender, 100_000 ether);
        items.mint(msg.sender, items.GOLD(), 1_000, "");
        items.mint(msg.sender, items.GEM(), 50, "");
        items.mint(msg.sender, items.WOOD(), 500, "");

        vm.stopBroadcast();
    }
}
