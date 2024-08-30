// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

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
    error BribeRewarder__AlreadyInitialized();
    error BribeRewarder__PeriodNotFound();
    error BribeRewarder__AmountTooLow();
    error BribeRewarder__OnlyVoterAdmin();

    event Claimed(address indexed account, address indexed pool, uint256 amount);
    event Deposited(uint256 indexed periodId, address indexed account, address indexed pool, uint256 amount);
    event BribeInit(uint256 indexed startId, uint256 indexed lastId, uint256 amountPerPeriod);
    event Swept(IERC20 indexed token, address indexed account, uint256 amount);

    function bribe(uint256 startId, uint256 lastId, uint256 amountPerPeriod) external;

    function claim(address account) external;

    function deposit(uint256 periodId, address account, uint256 deltaAmount) external;

    function getPool() external view returns (address);

    function getPendingReward(address account) external view returns (uint256);

    function getBribePeriods() external view returns (address pool, uint256[] memory);

    function getStartVotingPeriodId() external view returns (uint256);

    function getLastVotingPeriodId() external view returns (uint256);

    function getAmountPerPeriod() external view returns (uint256);

    function sweep(IERC20 token, address account) external;
}
