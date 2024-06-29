// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IRewarder} from "./IRewarder.sol";

interface IBribeRewarder is IRewarder {
    error BribeRewarder__OnlyVoter();
    error BribeRewarder__InsufficientFunds();
    error BribeRewarder__WrongStartId();
    error BribeRewarder__WrongEndId();
    error BribeRewarder__ZeroReward();
    error BribeRewarder__NativeTransferFailed();
    error BribeRewarder__NotOwner();
    error BribeRewarder__CannotRenounceOwnership();
    error BribeRewarder__NotNativeRewarder();

    event Claimed(uint256 indexed periodId, uint256 indexed tokenId, address indexed pool, uint256 amount);
    event Deposited(uint256 indexed periodId, uint256 indexed tokenId, address indexed pool, uint256 amount);
    event BribeInit(uint256 indexed startId, uint256 indexed lastId, uint256 amountPerPeriod);

    function bribe(uint256 startId, uint256 lastId, uint256 amountPerPeriod) external;

    function claim(uint256 periodId, uint256 tokenId) external;

    function deposit(uint256 periodId, uint256 tokenId, uint256 deltaAmount) external;

    function getPool() external view returns (address);

    function getPendingReward(uint256 periodId, uint256 tokenId) external view returns (uint256);

    function getBribePeriods() external view returns (address pool, uint256[] memory);

    function getStartVotingPeriodId() external view returns (uint256);

    function getLastVotingPeriodId() external view returns (uint256);

    function getAmountPerPeriod() external view returns (uint256);
}
