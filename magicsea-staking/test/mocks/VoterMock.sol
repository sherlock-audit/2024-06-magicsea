// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "../../src/interfaces/IVoter.sol";
import "../../src/interfaces/IMasterChef.sol";
import {Constants} from "../../src/libraries/Constants.sol";

contract VoterMock is IVoter {
    uint256 private _currentVotingPeriodId;

    uint256 private _startTime;
    uint256 private _endTime;
    uint256 private _latestFinishedPeriod;

    mapping(uint256 => mapping(address => uint256)) private _poolVotesPerPeriod;

    // periodId => pool => bribeRewarders
    mapping(uint256 => mapping(address => IBribeRewarder[])) private _bribesPerPriod;

    function getMasterChef() external pure returns (IMasterChef) {
        return IMasterChef(address(0));
    }

    function getTotalWeight() external pure returns (uint256) {
        return 0;
    }

    function getTopPoolIds() external pure returns (uint256[] memory) {
        uint256[] memory ids = new uint256[](0);
        return ids;
    }

    function getWeight(uint256 pid) external pure returns (uint256) {
        {
            pid;
        }
        return 0;
    }

    function getCurrentVotingPeriod() external view returns (uint256) {
        return _currentVotingPeriodId;
    }

    function getPeriodStartTime() external pure override returns (uint256) {
        return 0;
    }

    function getVotesPerPeriod(uint256 periodId, address pool) external pure returns (uint256) {
        {
            periodId;
            pool;
        }
        return 0;
    }

    function getTotalVotes() external pure returns (uint256) {
        return 0;
    }

    function getPoolBribesForPeriod(uint256 period, address pool)
        external
        view
        returns (IBribeRewarder[] memory rewarders)
    {
        {
            period;
            pool;
        }
        rewarders = _bribesPerPriod[period][pool];
    }

    function onRegister() external {
        IBribeRewarder rewarder = IBribeRewarder(msg.sender);
        uint256 currentPeriodId = _currentVotingPeriodId;
        (address pool, uint256[] memory periods) = rewarder.getBribePeriods();
        for (uint256 i = 0; i < periods.length; ++i) {
            require(periods[i] >= currentPeriodId, "wrong period");
            require(_bribesPerPriod[periods[i]][pool].length + 1 <= Constants.MAX_BRIBES_PER_POOL, "too much bribes");
            _bribesPerPriod[periods[i]][pool].push(rewarder);
        }
    }

    function setCurrentPeriod(uint256 period) public {
        _currentVotingPeriodId = period;
    }

    function getPoolVotesPerPeriod(uint256 periodId, address pool) external view returns (uint256) {
        return _poolVotesPerPeriod[periodId][pool];
    }

    function getUserVotes(uint256 tokenId, address pool) external pure returns (uint256) {
        {
            tokenId;
            pool;
        }
        return 0;
    }

    function ownerOf(uint256 tokenId, address account) external pure override returns (bool) {
        {
            tokenId;
            account;
        }
        return true;
    }

    function getUserBribeRewaderAt(uint256 period, uint256 tokenId, uint256 index)
        external
        pure
        returns (IBribeRewarder)
    {
        {
            period;
            tokenId;
            index;
        }

        return IBribeRewarder(address(0));
    }

    function getUserBribeRewarderLength(uint256 period, uint256 tokenId) external pure returns (uint256) {
        {
            period;
            tokenId;
        }
        return 0;
    }

    function getVotedPools() external pure override returns (address[] memory) {
        return new address[](0);
    }

    function getVotedPoolsLength() external pure override returns (uint256) {
        return 0;
    }

    function getVotedPoolsAtIndex(uint256 index) external pure override returns (address, uint256) {
        {
            index;
        }
        return (address(0), 0);
    }

    function getBribeRewarderAt(uint256 period, address pool, uint256 index)
        external
        pure
        override
        returns (IBribeRewarder)
    {
        {
            period;
            pool;
            index;
        }
        return IBribeRewarder(address(0));
    }

    function getBribeRewarderLength(uint256 period, address pool) external pure override returns (uint256) {
        {
            period;
            pool;
        }
        return 0;
    }

    function setStartAndEndTime(uint256 startTime, uint256 endTime) external {
        _startTime = startTime;
        _endTime = endTime;
    }

    function getPeriodStartEndtime(uint256 periodId) external view override returns (uint256, uint256) {
        {
            periodId;
        }
        return (_startTime, _endTime);
    }

    function getLatestFinishedPeriod() external view override returns (uint256) {
        return _latestFinishedPeriod;
    }

    function setLatestFinishedPeriod(uint256 period) external {
        _latestFinishedPeriod = period;
    }

    function hasVoted(uint256 period, uint256 tokenId) external pure override returns (bool) {
        {
            period;
            tokenId;
        }
        return false;
    }
}
