// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IBribeRewarder} from "./IBribeRewarder.sol";
import {IMasterChef} from "./IMasterChef.sol";

interface IVoter {
    error IVoter__InvalidLength();
    error IVoter_VotingPeriodNotStarted();
    error IVoter_VotingPeriodEnded();
    error IVoter__AlreadyVoted();
    error IVoter__NotOwner();
    error IVoter__InsufficientVotingPower();
    error IVoter__TooManyPoolIds();
    error IVoter__DuplicatePoolId(uint256 pid);
    error IVoter__InsufficientLockTime();
    error Voter__InvalidRegisterCaller();
    error Voter__PoolNotVotable();
    error IVoter__NoFinishedPeriod();
    error IVoter_ZeroValue();

    event VotingPeriodStarted();
    event Voted(uint256 indexed tokenId, uint256 votingPeriod, address[] votedPools, uint256[] votesDeltaAmounts);
    event TopPoolIdsWithWeightsSet(uint256[] poolIds, uint256[] pidWeights);
    event VoterPoolValidatorUpdated(address indexed validator);
    event VotingDurationUpdated(uint256 duration);
    event MinimumLockTimeUpdated(uint256 lockTime);
    event MinimumVotesPerPoolUpdated(uint256 minimum);
    event OperatorUpdated(address indexed operator);

    struct VotingPeriod {
        uint256 startTime;
        uint256 endTime;
    }

    function getMasterChef() external view returns (IMasterChef);

    function getTotalWeight() external view returns (uint256);

    function getTopPoolIds() external view returns (uint256[] memory);

    function getWeight(uint256 pid) external view returns (uint256);

    function hasVoted(uint256 period, uint256 tokenId) external view returns (bool);

    function getCurrentVotingPeriod() external view returns (uint256);

    function getLatestFinishedPeriod() external view returns (uint256);

    function getPeriodStartTime() external view returns (uint256);

    function getPeriodStartEndtime(uint256 periodId) external view returns (uint256, uint256);

    function getVotesPerPeriod(uint256 periodId, address pool) external view returns (uint256);

    function getVotedPools() external view returns (address[] memory);

    function getVotedPoolsLength() external view returns (uint256);

    function getVotedPoolsAtIndex(uint256 index) external view returns (address, uint256);

    function getTotalVotes() external view returns (uint256);

    function getUserVotes(uint256 tokenId, address pool) external view returns (uint256);

    function getPoolVotesPerPeriod(uint256 periodId, address pool) external view returns (uint256);

    function getUserBribeRewaderAt(uint256 period, address account, uint256 index)
        external
        view
        returns (IBribeRewarder);

    function getUserBribeRewarderLength(uint256 period, address account) external view returns (uint256);

    function getBribeRewarderAt(uint256 period, address pool, uint256 index) external view returns (IBribeRewarder);

    function getBribeRewarderLength(uint256 period, address pool) external view returns (uint256);

    function ownerOf(uint256 tokenId, address account) external view returns (bool);

    function onRegister() external;
}
