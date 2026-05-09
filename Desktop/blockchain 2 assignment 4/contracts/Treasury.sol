// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Treasury
 * @notice Holds ETH and ERC-20 tokens on behalf of the DAO.
 *         Only the TimelockController (owner) can transfer funds or change parameters.
 */
contract Treasury is Ownable {
    using SafeERC20 for IERC20;

    uint256 public feePercentage; // basis points (e.g., 50 = 0.5%)

    event ETHReceived(address indexed sender, uint256 amount);
    event ETHTransferred(address indexed to, uint256 amount);
    event ERC20Transferred(address indexed token, address indexed to, uint256 amount);
    event FeePercentageChanged(uint256 oldFee, uint256 newFee);

    constructor(address timelockController) Ownable(timelockController) {
        feePercentage = 50; // 0.5% default
    }

    receive() external payable {
        emit ETHReceived(msg.sender, msg.value);
    }

    /// @notice Transfer ETH — only governance (via timelock) can call.
    function transferETH(address payable to, uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "Insufficient ETH");
        (bool ok,) = to.call{value: amount}("");
        require(ok, "ETH transfer failed");
        emit ETHTransferred(to, amount);
    }

    /// @notice Transfer ERC-20 tokens — only governance can call.
    function transferERC20(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
        emit ERC20Transferred(token, to, amount);
    }

    /// @notice Change the fee percentage — only governance can call.
    function setFeePercentage(uint256 newFee) external onlyOwner {
        require(newFee <= 10_000, "Fee exceeds 100%");
        emit FeePercentageChanged(feePercentage, newFee);
        feePercentage = newFee;
    }

    function ethBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function tokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
}
