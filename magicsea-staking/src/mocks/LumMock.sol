// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin/token/ERC20/ERC20.sol";
import "openzeppelin/access/AccessControl.sol";
import "openzeppelin/token/ERC20/extensions/ERC20Permit.sol";

import "../interfaces/ILum.sol";

contract LumMock is ERC20, AccessControl, ERC20Permit, ILum {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(address defaultAdmin, address minter)
        ERC20("Lum Mock Token", "mockLUM")
        ERC20Permit("Lum Mock Token")
    {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(MINTER_ROLE, minter);
    }

    function mint(address to, uint256 amount) external override onlyRole(MINTER_ROLE) returns (uint256) {
        if (amount > 0) _mint(to, amount);

        return amount;
    }
}
