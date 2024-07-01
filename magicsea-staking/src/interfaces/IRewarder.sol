// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

interface IRewarder {
    function getToken() external view returns (IERC20);

    function getCaller() external view returns (address);

    function initialize(address initialOwner) external;
}
