// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IVoterPoolValidator {
    function isValid(address pool) external view returns (bool);
}
