// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC1155Receiver} from "./interfaces/IERC1155Receiver.sol";

/// @title GameItems
/// @notice ERC-1155 multi-token contract used for an in-game economy.
/// @dev Implements 3 fungible currencies (GOLD, GEM, WOOD), 2 non-fungible items
///      (SWORD, SHIELD), plus a crafting routine that burns inputs and mints an output.
contract GameItems {
    // -----------------------------------------------------------------
    // Token IDs
    // -----------------------------------------------------------------
    uint256 public constant GOLD = 1;
    uint256 public constant GEM = 2;
    uint256 public constant WOOD = 3;
    uint256 public constant SWORD = 100;
    uint256 public constant SHIELD = 101;

    // -----------------------------------------------------------------
    // ERC-1155 storage
    // -----------------------------------------------------------------
    mapping(uint256 => mapping(address => uint256)) private _balances;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    // Per-token accounting (helpful for NFT enforcement and analytics).
    mapping(uint256 => uint256) public totalSupply;

    // Base URI used when uri(id) is queried. The literal "{id}" placeholder
    // must remain so off-chain clients can substitute the hex token id.
    string private _baseURI;

    address public owner;

    // -----------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------
    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 value
    );

    event TransferBatch(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256[] ids,
        uint256[] values
    );

    event ApprovalForAll(address indexed account, address indexed operator, bool approved);

    event URI(string value, uint256 indexed id);

    event Crafted(address indexed crafter, uint256 indexed outputId, uint256 amount);

    // -----------------------------------------------------------------
    // Errors
    // -----------------------------------------------------------------
    error NotOwner();
    error ZeroAddress();
    error ArrayLengthMismatch();
    error InsufficientBalance();
    error NotAuthorized();
    error NonERC1155Receiver();
    error NFTAmountMustBeOne();
    error NFTAlreadyMinted();
    error UnknownToken();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(string memory baseURI_) {
        owner = msg.sender;
        _baseURI = baseURI_;
    }

    // -----------------------------------------------------------------
    // Metadata
    // -----------------------------------------------------------------

    /// @notice Returns the metadata URI for a token ID. Per ERC-1155, clients
    ///         substitute "{id}" with the lowercase hex representation of `id`.
    function uri(uint256) external view returns (string memory) {
        return _baseURI;
    }

    function setBaseURI(string calldata newURI) external onlyOwner {
        _baseURI = newURI;
    }

    // -----------------------------------------------------------------
    // ERC-1155 core view
    // -----------------------------------------------------------------

    function balanceOf(address account, uint256 id) public view returns (uint256) {
        if (account == address(0)) revert ZeroAddress();
        return _balances[id][account];
    }

    function balanceOfBatch(address[] calldata accounts, uint256[] calldata ids)
        external
        view
        returns (uint256[] memory)
    {
        if (accounts.length != ids.length) revert ArrayLengthMismatch();
        uint256[] memory out = new uint256[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            out[i] = balanceOf(accounts[i], ids[i]);
        }
        return out;
    }

    function isApprovedForAll(address account, address operator) public view returns (bool) {
        return _operatorApprovals[account][operator];
    }

    function setApprovalForAll(address operator, bool approved) external {
        if (operator == msg.sender) revert NotAuthorized();
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    // -----------------------------------------------------------------
    // Transfers
    // -----------------------------------------------------------------

    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external {
        if (from != msg.sender && !isApprovedForAll(from, msg.sender)) revert NotAuthorized();
        _safeTransferFrom(from, to, id, amount, data);
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external {
        if (from != msg.sender && !isApprovedForAll(from, msg.sender)) revert NotAuthorized();
        _safeBatchTransferFrom(from, to, ids, amounts, data);
    }

    function _safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes memory data) internal {
        if (to == address(0)) revert ZeroAddress();
        uint256 fromBal = _balances[id][from];
        if (fromBal < amount) revert InsufficientBalance();
        unchecked {
            _balances[id][from] = fromBal - amount;
            _balances[id][to] += amount;
        }
        emit TransferSingle(msg.sender, from, to, id, amount);
        _doSafeTransferAcceptanceCheck(msg.sender, from, to, id, amount, data);
    }

    function _safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes memory data
    ) internal {
        if (to == address(0)) revert ZeroAddress();
        if (ids.length != amounts.length) revert ArrayLengthMismatch();
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 id = ids[i];
            uint256 amount = amounts[i];
            uint256 fromBal = _balances[id][from];
            if (fromBal < amount) revert InsufficientBalance();
            unchecked {
                _balances[id][from] = fromBal - amount;
                _balances[id][to] += amount;
            }
        }
        emit TransferBatch(msg.sender, from, to, ids, amounts);
        _doSafeBatchTransferAcceptanceCheck(msg.sender, from, to, ids, amounts, data);
    }

    // -----------------------------------------------------------------
    // Mint / burn
    // -----------------------------------------------------------------

    function mint(address to, uint256 id, uint256 amount, bytes calldata data) external onlyOwner {
        _mint(to, id, amount, data);
    }

    function mintBatch(address to, uint256[] calldata ids, uint256[] calldata amounts, bytes calldata data)
        external
        onlyOwner
    {
        _mintBatch(to, ids, amounts, data);
    }

    function burn(address from, uint256 id, uint256 amount) external {
        if (from != msg.sender && !isApprovedForAll(from, msg.sender)) revert NotAuthorized();
        _burn(from, id, amount);
    }

    function _mint(address to, uint256 id, uint256 amount, bytes memory data) internal {
        if (to == address(0)) revert ZeroAddress();
        if (_isNFT(id)) {
            if (amount != 1) revert NFTAmountMustBeOne();
            if (totalSupply[id] != 0) revert NFTAlreadyMinted();
        } else if (!_isFungible(id)) {
            revert UnknownToken();
        }
        _balances[id][to] += amount;
        totalSupply[id] += amount;
        emit TransferSingle(msg.sender, address(0), to, id, amount);
        _doSafeTransferAcceptanceCheck(msg.sender, address(0), to, id, amount, data);
    }

    function _mintBatch(address to, uint256[] calldata ids, uint256[] calldata amounts, bytes memory data) internal {
        if (to == address(0)) revert ZeroAddress();
        if (ids.length != amounts.length) revert ArrayLengthMismatch();
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 id = ids[i];
            uint256 amount = amounts[i];
            if (_isNFT(id)) {
                if (amount != 1) revert NFTAmountMustBeOne();
                if (totalSupply[id] != 0) revert NFTAlreadyMinted();
            } else if (!_isFungible(id)) {
                revert UnknownToken();
            }
            _balances[id][to] += amount;
            totalSupply[id] += amount;
        }
        emit TransferBatch(msg.sender, address(0), to, ids, amounts);
        _doSafeBatchTransferAcceptanceCheck(msg.sender, address(0), to, ids, amounts, data);
    }

    function _burn(address from, uint256 id, uint256 amount) internal {
        uint256 bal = _balances[id][from];
        if (bal < amount) revert InsufficientBalance();
        unchecked {
            _balances[id][from] = bal - amount;
            totalSupply[id] -= amount;
        }
        emit TransferSingle(msg.sender, from, address(0), id, amount);
    }

    // -----------------------------------------------------------------
    // Crafting
    // -----------------------------------------------------------------

    /// @notice Burn 100 GOLD + 50 WOOD to mint 1 SWORD.
    /// @dev Demonstrates a fungible -> NFT crafting recipe.
    function craftSword() external {
        if (totalSupply[SWORD] != 0) revert NFTAlreadyMinted();
        _burn(msg.sender, GOLD, 100);
        _burn(msg.sender, WOOD, 50);
        // Inline NFT mint without acceptance check loop (msg.sender is EOA in the typical case;
        // for contract crafters we still call the receiver hook).
        _balances[SWORD][msg.sender] += 1;
        totalSupply[SWORD] += 1;
        emit TransferSingle(msg.sender, address(0), msg.sender, SWORD, 1);
        _doSafeTransferAcceptanceCheck(msg.sender, address(0), msg.sender, SWORD, 1, "");
        emit Crafted(msg.sender, SWORD, 1);
    }

    /// @notice Burn 200 GOLD + 5 GEM to mint 1 SHIELD.
    function craftShield() external {
        if (totalSupply[SHIELD] != 0) revert NFTAlreadyMinted();
        _burn(msg.sender, GOLD, 200);
        _burn(msg.sender, GEM, 5);
        _balances[SHIELD][msg.sender] += 1;
        totalSupply[SHIELD] += 1;
        emit TransferSingle(msg.sender, address(0), msg.sender, SHIELD, 1);
        _doSafeTransferAcceptanceCheck(msg.sender, address(0), msg.sender, SHIELD, 1, "");
        emit Crafted(msg.sender, SHIELD, 1);
    }

    // -----------------------------------------------------------------
    // ERC-165
    // -----------------------------------------------------------------
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 // ERC-165
            || interfaceId == 0xd9b67a26 // ERC-1155
            || interfaceId == 0x0e89341c; // ERC-1155 Metadata URI
    }

    // -----------------------------------------------------------------
    // Internal helpers
    // -----------------------------------------------------------------

    function _isFungible(uint256 id) internal pure returns (bool) {
        return id == GOLD || id == GEM || id == WOOD;
    }

    function _isNFT(uint256 id) internal pure returns (bool) {
        return id == SWORD || id == SHIELD;
    }

    function _doSafeTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) private {
        if (to.code.length == 0) return;
        try IERC1155Receiver(to).onERC1155Received(operator, from, id, amount, data) returns (bytes4 retval) {
            if (retval != IERC1155Receiver.onERC1155Received.selector) revert NonERC1155Receiver();
        } catch {
            revert NonERC1155Receiver();
        }
    }

    function _doSafeBatchTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes memory data
    ) private {
        if (to.code.length == 0) return;
        try IERC1155Receiver(to).onERC1155BatchReceived(operator, from, ids, amounts, data) returns (bytes4 retval) {
            if (retval != IERC1155Receiver.onERC1155BatchReceived.selector) revert NonERC1155Receiver();
        } catch {
            revert NonERC1155Receiver();
        }
    }
}
