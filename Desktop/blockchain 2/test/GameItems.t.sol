// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {GameItems} from "../src/GameItems.sol";
import {IERC1155Receiver} from "../src/interfaces/IERC1155Receiver.sol";

contract ReceiverMock is IERC1155Receiver {
    bool public reject;
    function setReject(bool v) external {reject = v;}

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        view
        returns (bytes4)
    {
        if (reject) return 0xdeadbeef;
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        view
        returns (bytes4)
    {
        if (reject) return 0xdeadbeef;
        return this.onERC1155BatchReceived.selector;
    }
}

contract NonReceiverMock {}

contract GameItemsTest is Test {
    GameItems internal items;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    uint256 internal GOLD;
    uint256 internal GEM;
    uint256 internal WOOD;
    uint256 internal SWORD;
    uint256 internal SHIELD;

    function setUp() public {
        items = new GameItems("https://game.example/api/{id}.json");
        GOLD = items.GOLD();
        GEM = items.GEM();
        WOOD = items.WOOD();
        SWORD = items.SWORD();
        SHIELD = items.SHIELD();
    }

    function test_MintFungible() public {
        items.mint(alice, GOLD, 1_000, "");
        assertEq(items.balanceOf(alice, GOLD), 1_000);
        assertEq(items.totalSupply(GOLD), 1_000);
    }

    function test_MintBatchFungible() public {
        uint256[] memory ids = new uint256[](3);
        ids[0] = GOLD;
        ids[1] = GEM;
        ids[2] = WOOD;
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 500;
        amounts[1] = 10;
        amounts[2] = 200;
        items.mintBatch(alice, ids, amounts, "");
        assertEq(items.balanceOf(alice, GOLD), 500);
        assertEq(items.balanceOf(alice, GEM), 10);
        assertEq(items.balanceOf(alice, WOOD), 200);
    }

    function test_RevertWhen_NFTMintedTwice() public {
        items.mint(alice, SWORD, 1, "");
        vm.expectRevert(GameItems.NFTAlreadyMinted.selector);
        items.mint(bob, SWORD, 1, "");
    }

    function test_RevertWhen_NFTAmountNotOne() public {
        vm.expectRevert(GameItems.NFTAmountMustBeOne.selector);
        items.mint(alice, SWORD, 5, "");
    }

    function test_SafeTransferFrom() public {
        items.mint(alice, GOLD, 100, "");
        vm.prank(alice);
        items.safeTransferFrom(alice, bob, GOLD, 40, "");
        assertEq(items.balanceOf(alice, GOLD), 60);
        assertEq(items.balanceOf(bob, GOLD), 40);
    }

    function test_SafeBatchTransferFrom() public {
        items.mint(alice, GOLD, 100, "");
        items.mint(alice, GEM, 5, "");
        uint256[] memory ids = new uint256[](2);
        ids[0] = GOLD;
        ids[1] = GEM;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 30;
        amounts[1] = 2;
        vm.prank(alice);
        items.safeBatchTransferFrom(alice, bob, ids, amounts, "");
        assertEq(items.balanceOf(bob, GOLD), 30);
        assertEq(items.balanceOf(bob, GEM), 2);
    }

    function test_OperatorApproval() public {
        items.mint(alice, GOLD, 100, "");
        vm.prank(alice);
        items.setApprovalForAll(bob, true);
        assertTrue(items.isApprovedForAll(alice, bob));
        vm.prank(bob);
        items.safeTransferFrom(alice, bob, GOLD, 50, "");
        assertEq(items.balanceOf(bob, GOLD), 50);
    }

    function test_RevertWhen_TransferWithoutApproval() public {
        items.mint(alice, GOLD, 100, "");
        vm.prank(bob);
        vm.expectRevert(GameItems.NotAuthorized.selector);
        items.safeTransferFrom(alice, bob, GOLD, 1, "");
    }

    function test_CraftSword() public {
        items.mint(alice, GOLD, 200, "");
        items.mint(alice, WOOD, 100, "");
        vm.prank(alice);
        items.craftSword();
        assertEq(items.balanceOf(alice, SWORD), 1);
        assertEq(items.balanceOf(alice, GOLD), 100);
        assertEq(items.balanceOf(alice, WOOD), 50);
    }

    function test_RevertWhen_CraftWithoutMaterials() public {
        vm.prank(alice);
        vm.expectRevert(GameItems.InsufficientBalance.selector);
        items.craftSword();
    }

    function test_URI() public view {
        assertEq(items.uri(GOLD), "https://game.example/api/{id}.json");
    }

    function test_SupportsInterface() public view {
        assertTrue(items.supportsInterface(0x01ffc9a7));
        assertTrue(items.supportsInterface(0xd9b67a26));
        assertTrue(items.supportsInterface(0x0e89341c));
        assertFalse(items.supportsInterface(0xffffffff));
    }

    function test_RevertWhen_TransferToNonReceiver() public {
        NonReceiverMock victim = new NonReceiverMock();
        items.mint(alice, GOLD, 10, "");
        address victimAddr = address(victim);
        vm.prank(alice);
        vm.expectRevert(GameItems.NonERC1155Receiver.selector);
        items.safeTransferFrom(alice, victimAddr, GOLD, 1, "");
    }

    function test_TransferToReceiver() public {
        ReceiverMock recv = new ReceiverMock();
        items.mint(alice, GOLD, 10, "");
        vm.prank(alice);
        items.safeTransferFrom(alice, address(recv), GOLD, 1, "");
        assertEq(items.balanceOf(address(recv), GOLD), 1);
    }

    function test_RevertWhen_NonOwnerMints() public {
        vm.prank(alice);
        vm.expectRevert(GameItems.NotOwner.selector);
        items.mint(alice, GOLD, 1, "");
    }

    function test_BalanceOfBatch() public {
        items.mint(alice, GOLD, 50, "");
        items.mint(bob, GEM, 7, "");
        address[] memory accs = new address[](2);
        accs[0] = alice;
        accs[1] = bob;
        uint256[] memory ids = new uint256[](2);
        ids[0] = GOLD;
        ids[1] = GEM;
        uint256[] memory bals = items.balanceOfBatch(accs, ids);
        assertEq(bals[0], 50);
        assertEq(bals[1], 7);
    }
}
