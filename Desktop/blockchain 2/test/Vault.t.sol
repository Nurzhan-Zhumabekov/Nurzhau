// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vault} from "../src/Vault.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";

contract VaultTest is Test {
    MockERC20 internal asset;
    Vault internal vault;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal owner;

    function setUp() public {
        owner = address(this);
        asset = new MockERC20("USD Stable", "USDS", 18);
        vault = new Vault(IERC20(address(asset)), "Vault USDS", "vUSDS");

        asset.mint(alice, 10_000 ether);
        asset.mint(bob, 10_000 ether);
        asset.mint(owner, 10_000 ether);

        vm.prank(alice);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        asset.approve(address(vault), type(uint256).max);
        asset.approve(address(vault), type(uint256).max);
    }

    function test_Metadata() public view {
        assertEq(vault.name(), "Vault USDS");
        assertEq(vault.symbol(), "vUSDS");
        assertEq(vault.decimals(), 18);
        assertEq(address(vault.asset()), address(asset));
    }

    function test_Deposit_FirstDepositorOneToOne() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(1_000 ether, alice);
        // With virtual shares/assets initial ratio is ~1:1.
        assertEq(shares, 1_000 ether);
        assertEq(vault.balanceOf(alice), 1_000 ether);
        assertEq(vault.totalAssets(), 1_000 ether);
        assertEq(vault.totalSupply(), 1_000 ether);
    }

    function test_Mint_PullsCorrectAssets() public {
        uint256 sharesWanted = 500 ether;
        uint256 expectedAssets = vault.previewMint(sharesWanted);
        vm.prank(alice);
        uint256 used = vault.mint(sharesWanted, alice);
        assertEq(used, expectedAssets);
        assertEq(vault.balanceOf(alice), sharesWanted);
    }

    function test_Withdraw_BurnsSharesAndPaysAssets() public {
        vm.prank(alice);
        vault.deposit(1_000 ether, alice);

        vm.prank(alice);
        uint256 burned = vault.withdraw(400 ether, alice, alice);
        assertEq(vault.balanceOf(alice), 1_000 ether - burned);
        assertEq(asset.balanceOf(alice), 10_000 ether - 1_000 ether + 400 ether);
    }

    function test_Redeem_PaysExpectedAssets() public {
        vm.prank(alice);
        vault.deposit(1_000 ether, alice);
        uint256 expected = vault.previewRedeem(500 ether);
        vm.prank(alice);
        uint256 paid = vault.redeem(500 ether, alice, alice);
        assertEq(paid, expected);
        assertEq(vault.balanceOf(alice), 500 ether);
    }

    function test_Harvest_BoostsShareValue() public {
        vm.prank(alice);
        vault.deposit(1_000 ether, alice);
        uint256 sharesBefore = vault.balanceOf(alice);
        uint256 assetsBefore = vault.previewRedeem(sharesBefore);

        // owner (this) harvests +100 yield.
        vault.harvest(100 ether);

        uint256 assetsAfter = vault.previewRedeem(sharesBefore);
        assertGt(assetsAfter, assetsBefore);
        // Shares unchanged.
        assertEq(vault.balanceOf(alice), sharesBefore);
    }

    function test_HarvestAffectsConversion() public {
        vm.prank(alice);
        vault.deposit(1_000 ether, alice);
        // Before harvest 1 share ≈ 1 asset
        uint256 sharesFor100 = vault.convertToShares(100 ether);
        vault.harvest(500 ether);
        uint256 sharesFor100After = vault.convertToShares(100 ether);
        assertLt(sharesFor100After, sharesFor100);
    }

    function test_RevertWhen_ZeroDeposit() public {
        vm.prank(alice);
        vm.expectRevert(Vault.ZeroAmount.selector);
        vault.deposit(0, alice);
    }

    function test_RevertWhen_ZeroReceiver() public {
        vm.prank(alice);
        vm.expectRevert(Vault.ZeroAddress.selector);
        vault.deposit(100 ether, address(0));
    }

    function test_RevertWhen_NonOwnerHarvest() public {
        vm.prank(alice);
        vm.expectRevert(Vault.NotOwner.selector);
        vault.harvest(1 ether);
    }

    function test_AllowanceWithdraw() public {
        vm.prank(alice);
        vault.deposit(1_000 ether, alice);
        // Alice gives bob a 200-share allowance.
        vm.prank(alice);
        vault.approve(bob, 200 ether);

        // bob redeems for himself spending alice's shares.
        vm.prank(bob);
        vault.redeem(200 ether, bob, alice);
        assertEq(vault.balanceOf(alice), 800 ether);
        assertEq(vault.allowance(alice, bob), 0);
    }

    function test_RevertWhen_AllowanceTooSmall() public {
        vm.prank(alice);
        vault.deposit(1_000 ether, alice);
        vm.prank(bob);
        vm.expectRevert(Vault.InsufficientAllowance.selector);
        vault.redeem(10 ether, bob, alice);
    }

    function test_PreviewRoundingDirection() public {
        // Build a non-trivial price (1 share = 1.1 assets).
        vm.prank(alice);
        vault.deposit(1_000 ether, alice);
        vault.harvest(100 ether);

        // previewWithdraw must round shares UP (caller pays at least that many).
        uint256 sharesUp = vault.previewWithdraw(7 ether);
        // previewDeposit rounds shares DOWN.
        uint256 sharesDown = vault.previewDeposit(7 ether);
        // For the same asset amount and >1 price, withdraw burns at least
        // as many shares as a deposit of the same amount would mint.
        assertGe(sharesUp, sharesDown);
    }

    function test_MultipleDepositorsShareYield() public {
        vm.prank(alice);
        vault.deposit(1_000 ether, alice);
        vm.prank(bob);
        vault.deposit(1_000 ether, bob);

        vault.harvest(200 ether);

        uint256 aliceAssets = vault.previewRedeem(vault.balanceOf(alice));
        uint256 bobAssets = vault.previewRedeem(vault.balanceOf(bob));
        // Both depositors collect ~half of the yield.
        assertApproxEqAbs(aliceAssets, 1_100 ether, 1);
        assertApproxEqAbs(bobAssets, 1_100 ether, 1);
    }

    function test_TransferShares() public {
        vm.prank(alice);
        vault.deposit(1_000 ether, alice);
        vm.prank(alice);
        vault.transfer(bob, 300 ether);
        assertEq(vault.balanceOf(alice), 700 ether);
        assertEq(vault.balanceOf(bob), 300 ether);
    }

    function test_FuzzDepositRedeem(uint96 amountRaw) public {
        uint256 amount = uint256(amountRaw) % 5_000 ether;
        vm.assume(amount > 0);
        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);
        vm.prank(alice);
        uint256 paid = vault.redeem(shares, alice, alice);
        // Without harvest, depositor should get back ~the same amount (minus virtual rounding dust).
        assertLe(paid, amount);
        assertGe(paid, amount > 1 ? amount - 1 : 0);
    }
}
