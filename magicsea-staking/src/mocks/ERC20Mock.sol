// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin/token/ERC20/ERC20.sol";
import "openzeppelin/access/AccessControl.sol";
import "openzeppelin/token/ERC20/extensions/ERC20Permit.sol";

contract ERC20Mock is ERC20, AccessControl, ERC20Permit {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(string memory name, string memory symbol, address defaultAdmin, address minter)
        ERC20(name, symbol)
        ERC20Permit(name)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(MINTER_ROLE, minter);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) returns (uint256) {
        if (amount > 0) _mint(to, amount);

        return amount;
    }
}
