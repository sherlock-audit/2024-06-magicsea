// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable2StepUpgradeable} from "openzeppelin-contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {EnumerableSet} from "openzeppelin/utils/structs/EnumerableSet.sol";

import {IVoter} from "../interfaces/IVoter.sol";
import {IBribeRewarder} from "../interfaces/IBribeRewarder.sol";
import {IMasterChef} from "../interfaces/IMasterChef.sol";

/**
 * @title AdminVoter - Intermediary contract for voting
 * @author BlueLabs / MagicSea
 */
contract AdminVoter is Ownable2StepUpgradeable, IVoter {
    using EnumerableSet for EnumerableSet.UintSet;

    IMasterChef internal immutable _masterChef;

    /// @dev weight per pid
    mapping(uint256 => uint256) private _weights; // pid => weight

    /// @dev totalWeight of pids
    uint256 private _topPidsTotalWeights;

    /// @dev stores the top pids
    EnumerableSet.UintSet private _topPids;

    address private _operator;

    uint256[9] __gap;

    constructor(IMasterChef masterChef) {
        _disableInitializers();

        _masterChef = masterChef;
    }

    function initialize(address initialOwner) external reinitializer(1) {
        __Ownable_init(initialOwner);
    }

    function getMasterChef() external view override returns (IMasterChef) {
        return _masterChef;
    }

    function getTotalWeight() external view override returns (uint256) {
        return _topPidsTotalWeights;
    }

    function getTopPoolIds() external view override returns (uint256[] memory) {
        return _topPids.values();
    }

    function getWeight(uint256 pid) external view override returns (uint256) {
        return _weights[pid];
    }

    function hasVoted(uint256 period, uint256 tokenId) external pure override returns (bool) {
        {
            period;
            tokenId;
        }
        return false;
    }

    function getCurrentVotingPeriod() external pure override returns (uint256) {
        return 0;
    }

    function getLatestFinishedPeriod() external pure override returns (uint256) {
        return 0;
    }

    function getPeriodStartTime() external pure override returns (uint256) {
        return 0;
    }

    function getPeriodStartEndtime(uint256 periodId) external pure override returns (uint256, uint256) {
        {
            periodId;
        }
        return (0, 0);
    }

    function getVotesPerPeriod(uint256 periodId, address pool) external pure override returns (uint256) {
        {
            periodId;
            pool;
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

    function getTotalVotes() external pure override returns (uint256) {
        return 0;
    }

    function getUserVotes(uint256 tokenId, address pool) external pure override returns (uint256) {
        {
            tokenId;
            pool;
        }
        return 0;
    }

    function getPoolVotesPerPeriod(uint256 periodId, address pool) external pure override returns (uint256) {
        {
            periodId;
            pool;
        }
        return 0;
    }

    function getUserBribeRewaderAt(uint256 period, address account, uint256 index)
        external
        pure
        override
        returns (IBribeRewarder)
    {
        {
            period;
            account;
            index;
        }
        return IBribeRewarder(address(0));
    }

    function getUserBribeRewarderLength(uint256 period, address account) external pure override returns (uint256) {
        {
            period;
            account;
        }
        return 0;
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

    function ownerOf(uint256 tokenId, address account) external pure override returns (bool) {
        {
            tokenId;
            account;
        }
        return false;
    }

    function onRegister() external pure override {
        revert IVoter__NotOwner();
    }

    function setTopPoolIdsWithWeights(uint256[] calldata pids, uint256[] calldata weights) external {
        if (msg.sender != _operator) _checkOwner();

        uint256 length = pids.length;
        if (length != weights.length) revert IVoter__InvalidLength();

        uint256[] memory oldIds = _topPids.values();

        if (oldIds.length > 0) {
            // masterchef snould be updated beforehand

            for (uint256 i = oldIds.length; i > 0;) {
                uint256 pid = oldIds[--i];

                _topPids.remove(pid);
                _weights[pid] = 0;
            }
        }

        for (uint256 i; i < length; ++i) {
            uint256 pid = pids[i];
            if (!_topPids.add(pid)) revert IVoter__DuplicatePoolId(pid);
        }

        uint256 totalWeights;
        for (uint256 i; i < length; ++i) {
            uint256 pid = pids[i];

            uint256 weight = weights[i];

            _weights[pid] = weight;

            totalWeights += weight;
        }

        _topPidsTotalWeights = totalWeights;

        emit TopPoolIdsWithWeightsSet(pids, weights);
    }

    /**
     * @dev Updates the operator.
     * @param operator The new operator.
     */
    function updateOperator(address operator) external onlyOwner {
        _operator = operator;
        emit OperatorUpdated(operator);
    }
}
