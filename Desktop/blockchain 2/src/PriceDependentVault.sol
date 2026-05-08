// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PriceFeedConsumer} from "./PriceFeedConsumer.sol";

/// @title PriceDependentVault
/// @notice ETH vault whose deposit limit per user is enforced as a USD ceiling
///         using a Chainlink price feed. Demonstrates the practical use of
///         oracle data in business logic.
contract PriceDependentVault {
    PriceFeedConsumer public immutable priceFeed;
    uint256 public immutable usdDepositCap; // 18-decimal USD value

    address public owner;

    mapping(address => uint256) public deposited; // ETH (wei) per user

    event Deposited(address indexed user, uint256 ethAmount, uint256 usdValue, uint256 priceAtDeposit);
    event Withdrawn(address indexed user, uint256 ethAmount);

    error CapExceeded(uint256 attemptedUsd, uint256 cap);
    error InsufficientBalance();
    error ZeroAmount();
    error TransferFailed();
    error NotOwner();

    constructor(PriceFeedConsumer _priceFeed, uint256 _usdDepositCap) {
        priceFeed = _priceFeed;
        usdDepositCap = _usdDepositCap;
        owner = msg.sender;
    }

    function deposit() external payable {
        if (msg.value == 0) revert ZeroAmount();
        (uint256 price, ) = priceFeed.getLatestPrice();
        uint256 usdValue = (msg.value * price) / 1e18;

        // Cap is checked against the *new total* USD value of this user's holdings,
        // priced at the current oracle rate. This means oracle drift can lock or
        // unlock further deposits — the price is part of the contract semantics.
        uint256 newDepositEth = deposited[msg.sender] + msg.value;
        uint256 newDepositUsd = (newDepositEth * price) / 1e18;
        if (newDepositUsd > usdDepositCap) revert CapExceeded(newDepositUsd, usdDepositCap);

        deposited[msg.sender] = newDepositEth;
        emit Deposited(msg.sender, msg.value, usdValue, price);
    }

    function withdraw(uint256 ethAmount) external {
        if (ethAmount == 0) revert ZeroAmount();
        uint256 bal = deposited[msg.sender];
        if (bal < ethAmount) revert InsufficientBalance();
        unchecked {
            deposited[msg.sender] = bal - ethAmount;
        }
        (bool ok, ) = msg.sender.call{value: ethAmount}("");
        if (!ok) revert TransferFailed();
        emit Withdrawn(msg.sender, ethAmount);
    }

    /// @notice Current USD value of `user`'s position at the latest oracle price.
    function usdValueOf(address user) external view returns (uint256) {
        (uint256 price, ) = priceFeed.getLatestPrice();
        return (deposited[user] * price) / 1e18;
    }

    /// @notice Remaining headroom (in ETH) under the USD cap for `user`.
    function remainingDepositEth(address user) external view returns (uint256) {
        (uint256 price, ) = priceFeed.getLatestPrice();
        uint256 currentUsd = (deposited[user] * price) / 1e18;
        if (currentUsd >= usdDepositCap) return 0;
        uint256 headroomUsd = usdDepositCap - currentUsd;
        return (headroomUsd * 1e18) / price;
    }
}
