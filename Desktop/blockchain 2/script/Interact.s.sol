// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {GameItems} from "../src/GameItems.sol";
import {Vault} from "../src/Vault.sol";
import {MockERC20} from "../src/MockERC20.sol";

/// @notice Sends 5+ on-chain transactions against an already-deployed pair of
///         contracts to satisfy the assignment's "execute meaningful
///         transactions" requirement. Reads addresses from environment.
contract Interact is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address sender = vm.addr(pk);

        GameItems items = GameItems(vm.envAddress("GAME_ITEMS"));
        Vault vault = Vault(vm.envAddress("VAULT"));
        MockERC20 usds = MockERC20(vm.envAddress("USDS"));

        vm.startBroadcast(pk);

        // Tx 1: mint 500 GOLD (already have starter balance, top up).
        items.mint(sender, items.GOLD(), 500, "");

        // Tx 2: batch transfer 100 GOLD + 10 GEM to a friend address (we use
        // sender as receiver here to keep the script self-contained).
        uint256[] memory ids = new uint256[](2);
        ids[0] = items.GOLD();
        ids[1] = items.GEM();
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100;
        amounts[1] = 10;
        items.safeBatchTransferFrom(sender, sender, ids, amounts, "");

        // Tx 3: approve the vault to pull our USDS, then deposit.
        usds.approve(address(vault), type(uint256).max);
        vault.deposit(1_000 ether, sender);

        // Tx 4: simulate a yield harvest of 50 USDS.
        vault.harvest(50 ether);

        // Tx 5: redeem 200 vault shares.
        vault.redeem(200 ether, sender, sender);

        // Tx 6: craft a sword (burns GOLD + WOOD, mints SWORD NFT).
        items.craftSword();

        vm.stopBroadcast();

        console2.log("Sender:", sender);
        console2.log("Final GOLD balance:", items.balanceOf(sender, items.GOLD()));
        console2.log("Final SWORD balance:", items.balanceOf(sender, items.SWORD()));
        console2.log("Final vault shares:", vault.balanceOf(sender));
    }
}
