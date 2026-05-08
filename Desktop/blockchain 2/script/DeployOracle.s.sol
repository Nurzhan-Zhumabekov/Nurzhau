// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {PriceFeedConsumer} from "../src/PriceFeedConsumer.sol";
import {PriceDependentVault} from "../src/PriceDependentVault.sol";
import {AggregatorV3Interface} from "../src/interfaces/AggregatorV3Interface.sol";

/// @notice Deploys PriceFeedConsumer + PriceDependentVault wired to a real
///         Chainlink ETH/USD feed on the target testnet.
///
/// Sepolia ETH/USD:           0x694AA1769357215DE4FAC081bf1f309aDC325306
/// Arbitrum Sepolia ETH/USD:  0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165
/// Optimism Sepolia ETH/USD:  0x61Ec26aA57019C486B10502285c5A3D4A4750AD7
/// Base Sepolia ETH/USD:      0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1
contract DeployOracle is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address feedAddr = vm.envAddress("PRICE_FEED");

        vm.startBroadcast(pk);

        PriceFeedConsumer consumer = new PriceFeedConsumer(
            AggregatorV3Interface(feedAddr),
            3600 // max staleness — Chainlink ETH/USD heartbeat
        );
        console2.log("PriceFeedConsumer:", address(consumer));

        PriceDependentVault vault = new PriceDependentVault(consumer, 5_000 ether);
        console2.log("PriceDependentVault:", address(vault));

        vm.stopBroadcast();
    }
}
