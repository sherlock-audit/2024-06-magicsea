// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {IRewarder} from "../interfaces/IRewarder.sol";
import {IBribeRewarder} from "../interfaces/IBribeRewarder.sol";
import {IBaseRewarder} from "../interfaces/IBaseRewarder.sol";

interface IRewarderFactory {
    error RewarderFactory__ZeroAddress();
    error RewarderFactory__InvalidRewarderType();
    error RewarderFactory__InvalidPid();
    error RewarderFactory__TokenNotWhitelisted();
    error RewarderFactory__InvalidLength();

    enum RewarderType {
        InvalidRewarder,
        MasterChefRewarder,
        BribeRewarder
    }

    event RewarderCreated(
        RewarderType indexed rewarderType, IERC20 indexed token, uint256 indexed pid, IBaseRewarder rewarder
    );

    event BribeRewarderCreated(
        RewarderType indexed rewarderType, IERC20 indexed token, address indexed pool, IBribeRewarder rewarder
    );

    event RewarderImplementationSet(RewarderType indexed rewarderType, IRewarder indexed implementation);

    function getBribeCreatorFee() external view returns (uint256);

    function getWhitelistedTokenInfo (address token) external view returns (bool, uint256);

    function getRewarderImplementation(RewarderType rewarderType) external view returns (IRewarder);

    function getRewarderCount(RewarderType rewarderType) external view returns (uint256);

    function getRewarderAt(RewarderType rewarderType, uint256 index) external view returns (IRewarder);

    function getRewarderType(IRewarder rewarder) external view returns (RewarderType);

    function setRewarderImplementation(RewarderType rewarderType, IRewarder implementation) external;

    function createRewarder(RewarderType rewarderType, IERC20 token, uint256 pid) external returns (IBaseRewarder);

    function createBribeRewarder(IERC20 token, address pool) external returns (IBribeRewarder);

    function setWhitelist(address[] calldata tokens, uint256[] calldata minBribeAmounts) external;
}
