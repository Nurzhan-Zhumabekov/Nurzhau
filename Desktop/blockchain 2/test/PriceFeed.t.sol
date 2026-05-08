// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PriceFeedConsumer} from "../src/PriceFeedConsumer.sol";
import {PriceDependentVault} from "../src/PriceDependentVault.sol";
import {MockAggregator} from "../src/MockAggregator.sol";
import {AggregatorV3Interface} from "../src/interfaces/AggregatorV3Interface.sol";

contract PriceFeedTest is Test {
    MockAggregator internal feed;
    PriceFeedConsumer internal consumer;
    PriceDependentVault internal vault;

    address internal alice = address(0xA11CE);

    uint256 internal constant MAX_STALENESS = 3600; // 1h

    function setUp() public {
        // Chainlink ETH/USD on mainnet uses 8 decimals. 2_000.00000000 USD/ETH.
        feed = new MockAggregator(8, "ETH / USD", 2_000 * 1e8);
        consumer = new PriceFeedConsumer(AggregatorV3Interface(address(feed)), MAX_STALENESS);
        // Cap = 5_000 USD per user.
        vault = new PriceDependentVault(consumer, 5_000 ether);
        vm.deal(alice, 100 ether);
    }

    function test_LatestPriceNormalisedTo18() public view {
        (uint256 p, ) = consumer.getLatestPrice();
        assertEq(p, 2_000 ether);
    }

    function test_EthToUsd() public view {
        // 1 ETH @ $2000 = $2000 (in 18 decimals)
        assertEq(consumer.ethToUsd(1 ether), 2_000 ether);
        assertEq(consumer.ethToUsd(0.5 ether), 1_000 ether);
    }

    function test_UsdToEth() public view {
        // $2000 = 1 ETH
        assertEq(consumer.usdToEth(2_000 ether), 1 ether);
    }

    function test_RevertWhen_StalePrice() public {
        // Push the timestamp far past max staleness.
        vm.warp(block.timestamp + MAX_STALENESS + 10);
        vm.expectRevert();
        consumer.getLatestPrice();
    }

    function test_RevertWhen_NegativePrice() public {
        feed.setAnswer(-1);
        vm.expectRevert();
        consumer.getLatestPrice();
    }

    function test_RevertWhen_IncompleteRound() public {
        feed.setRoundId(50);
        feed.setIncompleteRound(40); // answeredInRound < roundId
        vm.expectRevert(PriceFeedConsumer.IncompleteRound.selector);
        consumer.getLatestPrice();
    }

    function test_VaultDepositRespectsCap() public {
        // Cap is $5000, price is $2000 -> max 2.5 ETH
        vm.prank(alice);
        vault.deposit{value: 2 ether}();
        assertEq(vault.deposited(alice), 2 ether);
        assertEq(vault.usdValueOf(alice), 4_000 ether);
    }

    function test_RevertWhen_DepositExceedsCap() public {
        vm.prank(alice);
        vm.expectRevert(); // CapExceeded
        vault.deposit{value: 3 ether}(); // 3 ETH * $2000 = $6000 > cap
    }

    function test_RemainingDepositTracksPrice() public {
        vm.prank(alice);
        vault.deposit{value: 1 ether}(); // $2000 used of $5000
        // headroom in USD = 3000, in ETH = 1.5
        assertEq(vault.remainingDepositEth(alice), 1.5 ether);

        // Now ETH crashes to $1000 -> headroom in ETH grows.
        feed.setAnswer(1_000 * 1e8);
        // current USD value = 1 * $1000 = $1000, headroom = $4000 = 4 ETH
        assertEq(vault.remainingDepositEth(alice), 4 ether);
    }

    function test_VaultWithdraw() public {
        vm.prank(alice);
        vault.deposit{value: 2 ether}();
        uint256 before_ = alice.balance;
        vm.prank(alice);
        vault.withdraw(1 ether);
        assertEq(vault.deposited(alice), 1 ether);
        assertEq(alice.balance, before_ + 1 ether);
    }

    function test_MockedFeedViaCheatcode() public {
        // Demonstrates Foundry's vm.mockCall against a Chainlink-shaped target.
        address fakeFeed = address(0xC0FFEE);
        vm.mockCall(
            fakeFeed,
            abi.encodeWithSelector(AggregatorV3Interface.decimals.selector),
            abi.encode(uint8(8))
        );
        vm.mockCall(
            fakeFeed,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(7), int256(3_500 * 1e8), uint256(0), block.timestamp, uint80(7))
        );
        PriceFeedConsumer pc = new PriceFeedConsumer(AggregatorV3Interface(fakeFeed), MAX_STALENESS);
        (uint256 p, ) = pc.getLatestPrice();
        assertEq(p, 3_500 ether);
    }

    function test_EighteenDecimalFeed() public {
        // Some feeds are already 18-decimal — make sure normalisation is a no-op.
        MockAggregator f18 = new MockAggregator(18, "FOO / USD", int256(42 ether));
        PriceFeedConsumer pc = new PriceFeedConsumer(AggregatorV3Interface(address(f18)), MAX_STALENESS);
        (uint256 p, ) = pc.getLatestPrice();
        assertEq(p, 42 ether);
    }
}
