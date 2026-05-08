// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";

/// @title PriceFeedConsumer
/// @notice Reads ETH/USD from a Chainlink aggregator and exposes it in a
///         normalised 18-decimal scale, with stale-price protection.
contract PriceFeedConsumer {
    AggregatorV3Interface public immutable feed;
    uint256 public immutable maxStaleness;

    error StalePrice(uint256 updatedAt, uint256 maxStaleness);
    error NegativePrice(int256 answer);
    error IncompleteRound();

    constructor(AggregatorV3Interface _feed, uint256 _maxStaleness) {
        feed = _feed;
        maxStaleness = _maxStaleness;
    }

    /// @notice Latest price normalised to 18 decimals. Reverts on stale,
    ///         negative, or incomplete-round answers.
    function getLatestPrice() public view returns (uint256 price, uint256 updatedAt) {
        (uint80 roundId, int256 answer, , uint256 _updatedAt, uint80 answeredInRound) = feed.latestRoundData();
        if (_updatedAt == 0 || answeredInRound < roundId) revert IncompleteRound();
        if (block.timestamp - _updatedAt > maxStaleness) revert StalePrice(_updatedAt, maxStaleness);
        if (answer <= 0) revert NegativePrice(answer);

        uint8 d = feed.decimals();
        // Normalise to 1e18 regardless of feed precision.
        if (d == 18) {
            price = uint256(answer);
        } else if (d < 18) {
            price = uint256(answer) * (10 ** (18 - d));
        } else {
            price = uint256(answer) / (10 ** (d - 18));
        }
        updatedAt = _updatedAt;
    }

    /// @notice Convert an ETH amount (wei, 18 decimals) into a USD value
    ///         (also expressed with 18 decimals).
    function ethToUsd(uint256 ethAmount) external view returns (uint256) {
        (uint256 price, ) = getLatestPrice();
        return (ethAmount * price) / 1e18;
    }

    /// @notice Convert a USD amount (18 decimals) into ETH (wei).
    function usdToEth(uint256 usdAmount) external view returns (uint256) {
        (uint256 price, ) = getLatestPrice();
        return (usdAmount * 1e18) / price;
    }
}
