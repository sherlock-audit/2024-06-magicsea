// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Constants Library
 * @dev A library that defines various constants used throughout the codebase.
 */
library Constants {
    uint256 internal constant ACC_PRECISION_BITS = 64;
    uint256 internal constant PRECISION = 1e18;

    uint256 internal constant MAX_NUMBER_OF_FARMS = 32;
    uint256 internal constant MAX_NUMBER_OF_REWARDS = 32;

    uint256 internal constant MAX_LUM_PER_SECOND = 10e18;

    uint256 internal constant MAX_BRIBES_PER_POOL = 5;
}
