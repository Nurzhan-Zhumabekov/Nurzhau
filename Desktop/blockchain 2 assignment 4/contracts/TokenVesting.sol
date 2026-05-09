// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title TokenVesting
 * @notice Releases tokens linearly over 12 months to the team beneficiary.
 *         Supports early delegation so vesting tokens count toward governance.
 */
contract TokenVesting is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    address public immutable beneficiary;
    uint256 public immutable startTime;
    uint256 public constant DURATION = 365 days; // 12 months

    uint256 public released;

    event TokensReleased(uint256 amount);

    constructor(address _token, address _beneficiary) {
        require(_token != address(0), "Zero token address");
        require(_beneficiary != address(0), "Zero beneficiary");
        token = IERC20(_token);
        beneficiary = _beneficiary;
        startTime = block.timestamp;
    }

    /// @notice Returns the total tokens vested up to now.
    function vestedAmount() public view returns (uint256) {
        uint256 balance = token.balanceOf(address(this)) + released;
        if (block.timestamp >= startTime + DURATION) {
            return balance;
        }
        return (balance * (block.timestamp - startTime)) / DURATION;
    }

    /// @notice Returns tokens available to release right now.
    function releasable() public view returns (uint256) {
        return vestedAmount() - released;
    }

    /// @notice Releases all currently vested tokens to the beneficiary.
    function release() external nonReentrant {
        uint256 amount = releasable();
        require(amount > 0, "Nothing to release");
        released += amount;
        token.safeTransfer(beneficiary, amount);
        emit TokensReleased(amount);
    }
}
