// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

interface ILum is IERC20 {
    function mint(address account, uint256 amount) external returns (uint256);
}
