// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "./interfaces/IERC20.sol";

/// @title Vault — ERC-4626 tokenized vault
/// @notice Accepts a single ERC-20 `asset`, mints share tokens to depositors,
///         and supports a manual `harvest()` that simulates accrued yield.
/// @dev Implements ERC-4626 view + mutating surface. Share token is the vault
///      contract itself (it implements ERC-20 internally), as required by
///      the standard.
contract Vault is IERC20 {
    // -----------------------------------------------------------------
    // Immutable / config
    // -----------------------------------------------------------------
    IERC20 public immutable asset;
    uint8 public immutable decimals;

    string public name;
    string public symbol;

    address public owner;

    // Virtual shares mitigation against the classic "first-depositor" inflation
    // attack. We initialise the share/asset ratio with phantom 1 share + 1 asset
    // so that `convertToShares` and `convertToAssets` are well-defined and
    // donation attacks cost the attacker much more than they could steal.
    uint256 internal constant VIRTUAL_SHARES = 1;
    uint256 internal constant VIRTUAL_ASSETS = 1;

    // -----------------------------------------------------------------
    // ERC-20 storage (share token)
    // -----------------------------------------------------------------
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // -----------------------------------------------------------------
    // ERC-4626 events
    // -----------------------------------------------------------------
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event Harvest(uint256 yieldAmount, uint256 totalAssetsAfter);

    // -----------------------------------------------------------------
    // Errors
    // -----------------------------------------------------------------
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientBalance();
    error InsufficientAllowance();
    error NotOwner();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(IERC20 asset_, string memory name_, string memory symbol_) {
        if (address(asset_) == address(0)) revert ZeroAddress();
        asset = asset_;
        name = name_;
        symbol = symbol_;
        decimals = asset_.decimals();
        owner = msg.sender;
    }

    // =================================================================
    // ERC-4626 — view
    // =================================================================

    /// @notice Total managed assets (idle balance held by the vault).
    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        return _convertToShares(assets, false);
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        return _convertToAssets(shares, false);
    }

    function maxDeposit(address) external pure returns (uint256) {return type(uint256).max;}
    function maxMint(address) external pure returns (uint256) {return type(uint256).max;}

    function maxWithdraw(address ownerAddr) external view returns (uint256) {
        return _convertToAssets(balanceOf[ownerAddr], false);
    }

    function maxRedeem(address ownerAddr) external view returns (uint256) {
        return balanceOf[ownerAddr];
    }

    // Per ERC-4626: previewDeposit must round shares DOWN; previewMint must round
    // assets UP (caller has to bring at least that many); previewWithdraw must
    // round shares UP (caller has to burn at least that many); previewRedeem
    // rounds assets DOWN.
    function previewDeposit(uint256 assets) public view returns (uint256) {
        return _convertToShares(assets, false);
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        return _convertToAssets(shares, true);
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        return _convertToShares(assets, true);
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        return _convertToAssets(shares, false);
    }

    // =================================================================
    // ERC-4626 — mutating
    // =================================================================

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        if (assets == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        shares = previewDeposit(assets);
        if (shares == 0) revert ZeroAmount();
        _pullAssets(msg.sender, assets);
        _mintShares(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function mint(uint256 shares, address receiver) external returns (uint256 assets) {
        if (shares == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        assets = previewMint(shares);
        _pullAssets(msg.sender, assets);
        _mintShares(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function withdraw(uint256 assets, address receiver, address ownerAddr) external returns (uint256 shares) {
        if (assets == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        shares = previewWithdraw(assets);
        _spendShareAllowance(ownerAddr, msg.sender, shares);
        _burnShares(ownerAddr, shares);
        _pushAssets(receiver, assets);
        emit Withdraw(msg.sender, receiver, ownerAddr, assets, shares);
    }

    function redeem(uint256 shares, address receiver, address ownerAddr) external returns (uint256 assets) {
        if (shares == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        assets = previewRedeem(shares);
        if (assets == 0) revert ZeroAmount();
        _spendShareAllowance(ownerAddr, msg.sender, shares);
        _burnShares(ownerAddr, shares);
        _pushAssets(receiver, assets);
        emit Withdraw(msg.sender, receiver, ownerAddr, assets, shares);
    }

    // =================================================================
    // Yield simulation
    // =================================================================

    /// @notice Simulate strategy yield by pulling `yieldAmount` of underlying
    ///         from the owner into the vault. Existing share holders see their
    ///         redemption value go up (more assets backing the same shares).
    function harvest(uint256 yieldAmount) external onlyOwner {
        if (yieldAmount == 0) revert ZeroAmount();
        _pullAssets(msg.sender, yieldAmount);
        emit Harvest(yieldAmount, totalAssets());
    }

    // =================================================================
    // ERC-20 — share token surface
    // =================================================================

    function approve(address spender, uint256 amount) external returns (bool) {
        if (spender == address(0)) revert ZeroAddress();
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transferShares(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        _spendShareAllowance(from, msg.sender, amount);
        _transferShares(from, to, amount);
        return true;
    }

    // =================================================================
    // Internal — share + asset bookkeeping
    // =================================================================

    function _convertToShares(uint256 assets, bool roundUp) internal view returns (uint256) {
        uint256 supply = totalSupply + VIRTUAL_SHARES;
        uint256 totalA = totalAssets() + VIRTUAL_ASSETS;
        return roundUp ? _mulDivUp(assets, supply, totalA) : (assets * supply) / totalA;
    }

    function _convertToAssets(uint256 shares, bool roundUp) internal view returns (uint256) {
        uint256 supply = totalSupply + VIRTUAL_SHARES;
        uint256 totalA = totalAssets() + VIRTUAL_ASSETS;
        return roundUp ? _mulDivUp(shares, totalA, supply) : (shares * totalA) / supply;
    }

    function _mulDivUp(uint256 a, uint256 b, uint256 d) internal pure returns (uint256) {
        uint256 prod = a * b;
        return prod == 0 ? 0 : (prod - 1) / d + 1;
    }

    function _pullAssets(address from, uint256 amount) internal {
        bool ok = asset.transferFrom(from, address(this), amount);
        require(ok, "Vault: transferFrom failed");
    }

    function _pushAssets(address to, uint256 amount) internal {
        bool ok = asset.transfer(to, amount);
        require(ok, "Vault: transfer failed");
    }

    function _mintShares(address to, uint256 amount) internal {
        if (to == address(0)) revert ZeroAddress();
        totalSupply += amount;
        unchecked {
            balanceOf[to] += amount;
        }
        emit Transfer(address(0), to, amount);
    }

    function _burnShares(address from, uint256 amount) internal {
        uint256 bal = balanceOf[from];
        if (bal < amount) revert InsufficientBalance();
        unchecked {
            balanceOf[from] = bal - amount;
            totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }

    function _transferShares(address from, address to, uint256 amount) internal {
        if (to == address(0)) revert ZeroAddress();
        uint256 bal = balanceOf[from];
        if (bal < amount) revert InsufficientBalance();
        unchecked {
            balanceOf[from] = bal - amount;
            balanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);
    }

    function _spendShareAllowance(address ownerAddr, address spender, uint256 amount) internal {
        if (ownerAddr == spender) return;
        uint256 allowed = allowance[ownerAddr][spender];
        if (allowed != type(uint256).max) {
            if (allowed < amount) revert InsufficientAllowance();
            unchecked {
                allowance[ownerAddr][spender] = allowed - amount;
            }
        }
    }
}
