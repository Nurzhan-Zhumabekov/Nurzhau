// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";

/// @notice Test double for Chainlink's AggregatorV3 — lets tests inject any
///         price, staleness, or round state.
contract MockAggregator is AggregatorV3Interface {
    uint8 private _decimals;
    string private _description;
    uint256 private _version;

    uint80 private _roundId;
    int256 private _answer;
    uint256 private _startedAt;
    uint256 private _updatedAt;
    uint80 private _answeredInRound;

    constructor(uint8 decimals_, string memory description_, int256 initialAnswer) {
        _decimals = decimals_;
        _description = description_;
        _version = 1;
        _roundId = 1;
        _answer = initialAnswer;
        _startedAt = block.timestamp;
        _updatedAt = block.timestamp;
        _answeredInRound = 1;
    }

    function setAnswer(int256 newAnswer) external {
        _answer = newAnswer;
        _roundId += 1;
        _answeredInRound = _roundId;
        _startedAt = block.timestamp;
        _updatedAt = block.timestamp;
    }

    function setUpdatedAt(uint256 newTimestamp) external {_updatedAt = newTimestamp;}
    function setIncompleteRound(uint80 newAnsweredInRound) external {_answeredInRound = newAnsweredInRound;}
    function setRoundId(uint80 newRoundId) external {_roundId = newRoundId;}

    function decimals() external view returns (uint8) {return _decimals;}
    function description() external view returns (string memory) {return _description;}
    function version() external view returns (uint256) {return _version;}

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (_roundId, _answer, _startedAt, _updatedAt, _answeredInRound);
    }
}
