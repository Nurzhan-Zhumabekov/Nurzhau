// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Box
 * @notice Simple controlled contract owned by the TimelockController.
 *         Demonstrates end-to-end governance: DAO votes to call store(42).
 */
contract Box is Ownable {
    uint256 private _value;

    event ValueStored(uint256 newValue);

    constructor(address timelockController) Ownable(timelockController) {}

    /// @notice Store a value — only governance (via timelock) can call.
    function store(uint256 newValue) external onlyOwner {
        _value = newValue;
        emit ValueStored(newValue);
    }

    /// @notice Read the stored value.
    function retrieve() external view returns (uint256) {
        return _value;
    }
}
