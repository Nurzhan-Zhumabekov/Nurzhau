// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title GovernanceToken
 * @notice ERC-20 governance token with voting power delegation and gasless approvals.
 *
 * Token distribution (1,000,000 total supply):
 *   40% — team     (vested via TokenVesting)
 *   30% — treasury (held by TimelockController)
 *   20% — community airdrop
 *   10% — liquidity
 */
contract GovernanceToken is ERC20, ERC20Permit, ERC20Votes, Ownable {
    uint256 public constant TOTAL_SUPPLY = 1_000_000 * 10 ** 18;

    // Distribution percentages (basis points)
    uint256 public constant TEAM_BP       = 4000; // 40%
    uint256 public constant TREASURY_BP   = 3000; // 30%
    uint256 public constant COMMUNITY_BP  = 2000; // 20%
    uint256 public constant LIQUIDITY_BP  = 1000; // 10%

    constructor(
        address teamVesting,
        address treasury,
        address community,
        address liquidity
    )
        ERC20("GovernanceToken", "GOV")
        ERC20Permit("GovernanceToken")
        Ownable(msg.sender)
    {
        _mint(teamVesting, (TOTAL_SUPPLY * TEAM_BP)      / 10_000);
        _mint(treasury,    (TOTAL_SUPPLY * TREASURY_BP)  / 10_000);
        _mint(community,   (TOTAL_SUPPLY * COMMUNITY_BP) / 10_000);
        _mint(liquidity,   (TOTAL_SUPPLY * LIQUIDITY_BP) / 10_000);
    }

    // Required overrides for ERC20Votes ----------------------------------------

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}
