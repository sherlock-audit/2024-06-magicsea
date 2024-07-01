// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeERC20, IERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Ownable2StepUpgradeable} from "openzeppelin-contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {EnumerableSet} from "openzeppelin/utils/structs/EnumerableSet.sol";
import {EnumerableMap} from "openzeppelin/utils/structs/EnumerableMap.sol";

import {IMlumStaking} from "./interfaces/IMlumStaking.sol";
import {IBribeRewarder} from "./interfaces/IBribeRewarder.sol";
import {IRewarderFactory} from "./interfaces/IRewarderFactory.sol";
import {IMasterChef, IMasterChefRewarder} from "./interfaces/IMasterChef.sol";
import {IVoterPoolValidator} from "./interfaces/IVoterPoolValidator.sol";
import {IVoter} from "./interfaces/IVoter.sol";
import {Amounts} from "./libraries/Amounts.sol";
import {Constants} from "./libraries/Constants.sol";

contract Voter is Ownable2StepUpgradeable, IVoter {
    using Amounts for Amounts.Parameter;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    using EnumerableMap for EnumerableMap.AddressToUintMap;

    IMasterChef internal immutable _masterChef;
    IMlumStaking internal immutable _mlumStaking;
    IRewarderFactory internal immutable _rewarderFactory;

    uint256 private _currentVotingPeriodId;

    /// @dev votingPeriodId => tokenId => hasVoted
    mapping(uint256 => mapping(uint256 => bool)) private _hasVotedInPeriod;

    /// @dev period => total amount of votes
    mapping(uint256 => uint256) private _totalVotesInPeriod; // total Weight in period

    /// @dev minimum votes (mlum) to get created
    uint256 private _minimumVotesPerPool = 50e18;

    uint256 private _periodDuration = 1209600;

    uint256 private _minimumLockTime = 60 * 60 * 24 * 30 * 3;

    /// @dev period => pool => votes
    mapping(uint256 => mapping(address => uint256)) private _poolVotesPerPeriod;

    // period id => rewarders;
    mapping(uint256 => EnumerableSet.Bytes32Set) private _registeredBribesPerPeriod; //extra check

    // periodId => tokenId  => bribes
    mapping(uint256 => mapping(uint256 => IBribeRewarder[])) private _userBribesPerPeriod;

    // periodId => pool => bribeRewarders
    mapping(uint256 => mapping(address => IBribeRewarder[])) private _bribesPerPriod;

    /// @dev tokenId => pool => votes
    mapping(uint256 => mapping(address => uint256)) private _userVotes;

    /// @dev period => startTime
    mapping(uint256 => VotingPeriod) _startTimes;

    /// @dev votes per pool
    EnumerableMap.AddressToUintMap private _votes;

    /// @dev total votes
    uint256 private _totalVotes;

    /// @dev weight per pid
    mapping(uint256 => uint256) private _weights; // pid => weight

    /// @dev totalWeight of pids
    uint256 private _topPidsTotalWeights;

    /// @dev stores the top pids
    EnumerableSet.UintSet private _topPids;

    /// @dev set pool validator;
    IVoterPoolValidator private _poolValidator;

    address private _operator;

    uint256[9] __gap;

    constructor(IMasterChef masterChef, IMlumStaking mlumStaking, IRewarderFactory factory) {
        _disableInitializers();

        _masterChef = masterChef;
        _mlumStaking = mlumStaking;
        _rewarderFactory = factory;
    }

    /**
     * @dev Initializes the contract.
     * @param initialOwner The initial owner of the contract.
     */
    function initialize(address initialOwner) external reinitializer(2) {
        __Ownable_init(initialOwner);

        _minimumVotesPerPool = 50e18;
        _periodDuration = 1209600;
        _minimumLockTime = 60 * 60 * 24 * 30 * 3;
    }

    /**
     * @dev start a new voting period
     */
    function startNewVotingPeriod() public onlyOwner {
        _currentVotingPeriodId++;

        VotingPeriod storage period = _startTimes[_currentVotingPeriodId];
        period.startTime = block.timestamp;
        period.endTime = block.timestamp + _periodDuration;

        emit VotingPeriodStarted();
    }

    function _votingStarted() internal view returns (bool) {
        return _startTimes[_currentVotingPeriodId].startTime != 0
            && _startTimes[_currentVotingPeriodId].startTime <= block.timestamp;
    }

    function _votingEnded() internal view returns (bool) {
        return _votingStarted() && _startTimes[_currentVotingPeriodId].endTime <= block.timestamp;
    }

    /**
     * @dev bribe rewarder registers itself
     * TODO check if rewarder is from allowed rewarderFactory
     */
    function onRegister() external override {
        IBribeRewarder rewarder = IBribeRewarder(msg.sender);

        _checkRegisterCaller(rewarder);

        uint256 currentPeriodId = _currentVotingPeriodId;
        (address pool, uint256[] memory periods) = rewarder.getBribePeriods();
        for (uint256 i = 0; i < periods.length; ++i) {
            // TODO check if rewarder token + pool  is already registered

            require(periods[i] >= currentPeriodId, "wrong period");
            require(_bribesPerPriod[periods[i]][pool].length + 1 <= Constants.MAX_BRIBES_PER_POOL, "too much bribes");
            _bribesPerPriod[periods[i]][pool].push(rewarder);
        }
    }

    /**
     * Cast votes for current voting period
     *
     * @param tokenId - token id of mlum staking position
     * @param pools - array of pool addresses
     * @param deltaAmounts - array of amounts must not exceed the total voting power
     */
    function vote(uint256 tokenId, address[] calldata pools, uint256[] calldata deltaAmounts) external {
        if (pools.length != deltaAmounts.length) revert IVoter__InvalidLength();

        // check voting started
        if (!_votingStarted()) revert IVoter_VotingPeriodNotStarted();
        if (_votingEnded()) revert IVoter_VotingPeriodEnded();

        // check ownership of tokenId
        if (_mlumStaking.ownerOf(tokenId) != msg.sender) {
            revert IVoter__NotOwner();
        }

        uint256 currentPeriodId = _currentVotingPeriodId;
        // check if alreay voted
        if (_hasVotedInPeriod[currentPeriodId][tokenId]) {
            revert IVoter__AlreadyVoted();
        }

        // check if _minimumLockTime >= initialLockDuration and it is locked
        if (_mlumStaking.getStakingPosition(tokenId).initialLockDuration < _minimumLockTime) {
            revert IVoter__InsufficientLockTime();
        }
        if (_mlumStaking.getStakingPosition(tokenId).lockDuration < _periodDuration) {
            revert IVoter__InsufficientLockTime();
        }

        uint256 votingPower = _mlumStaking.getStakingPosition(tokenId).amountWithMultiplier;

        // check if deltaAmounts > votingPower
        uint256 totalUserVotes;
        for (uint256 i = 0; i < pools.length; ++i) {
            totalUserVotes += deltaAmounts[i];
        }

        if (totalUserVotes > votingPower) {
            revert IVoter__InsufficientVotingPower();
        }

        IVoterPoolValidator validator = _poolValidator;

        for (uint256 i = 0; i < pools.length; ++i) {
            address pool = pools[i];

            if (address(validator) != address(0) && !validator.isValid(pool)) {
                revert Voter__PoolNotVotable();
            }

            uint256 deltaAmount = deltaAmounts[i];

            _userVotes[tokenId][pool] += deltaAmount;
            _poolVotesPerPeriod[currentPeriodId][pool] += deltaAmount;

            if (_votes.contains(pool)) {
                _votes.set(pool, _votes.get(pool) + deltaAmount);
            } else {
                _votes.set(pool, deltaAmount);
            }

            _notifyBribes(_currentVotingPeriodId, pool, tokenId, deltaAmount); // msg.sender, deltaAmount);
        }

        _totalVotes += totalUserVotes;

        _hasVotedInPeriod[currentPeriodId][tokenId] = true;

        emit Voted(tokenId, currentPeriodId, pools, deltaAmounts);
    }

    function _notifyBribes(uint256 periodId, address pool, uint256 tokenId, uint256 deltaAmount) private {
        IBribeRewarder[] storage rewarders = _bribesPerPriod[periodId][pool];
        for (uint256 i = 0; i < rewarders.length; ++i) {
            if (address(rewarders[i]) != address(0)) {
                rewarders[i].deposit(periodId, tokenId, deltaAmount);
                _userBribesPerPeriod[periodId][tokenId].push(rewarders[i]);
            }
        }
    }

    function createFarms(address[] calldata pools) external onlyOwner {
        uint256 farmLengths = _masterChef.getNumberOfFarms();
        uint256 minimumVotes = _minimumVotesPerPool;
        for (uint256 i = 0; i < pools.length; ++i) {
            if (_votes.get(pools[i]) >= minimumVotes && !hasFarm(pools[i], farmLengths)) {
                _masterChef.add(IERC20(pools[i]), IMasterChefRewarder(address(0)));
            }
        }
    }

    function hasFarm(address pool, uint256 farmLength) internal view returns (bool) {
        for (uint256 i = 0; i < farmLength; ++i) {
            if (address(_masterChef.getToken(i)) == pool) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Set farm pools with their weight;
     *
     * WARNING:
     * Caller is responsible to updateAll oldPids on masterChef before using this function
     * and also call updateAll for the new pids after.
     *
     * @param pids - list of pids
     * @param weights - list of weights
     */
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

    function updatePoolValidator(IVoterPoolValidator poolValidator) external onlyOwner {
        _poolValidator = poolValidator;
        emit VoterPoolValidatorUpdated(address(poolValidator));
    }

    /**
     * @dev returns current voting period
     */
    function getCurrentVotingPeriod() external view override returns (uint256) {
        return _currentVotingPeriodId;
    }

    /**
     * @dev returns current period start time
     */
    function getPeriodStartTime() external view override returns (uint256) {
        return _startTimes[_currentVotingPeriodId].startTime;
    }

    /**
     * @dev get votes per period
     * @param periodId - period of the vote
     * @param pool - pool address
     */
    function getVotesPerPeriod(uint256 periodId, address pool) external view override returns (uint256) {
        return _poolVotesPerPeriod[periodId][pool];
    }

    /**
     * @dev get total accrued votes
     */
    function getTotalVotes() external view override returns (uint256) {
        return _totalVotes;
    }

    /**
     * @dev Get accrued user votes for given tokenId and pool
     *
     */
    function getUserVotes(uint256 tokenId, address pool) external view override returns (uint256) {
        return _userVotes[tokenId][pool];
    }

    /**
     * @dev Get pool votes for given period
     */
    function getPoolVotesPerPeriod(uint256 periodId, address pool) external view override returns (uint256) {
        return _poolVotesPerPeriod[periodId][pool];
    }

    /**
     * @dev Get accrued pool votes
     */
    function getPoolVotes(address pool) external view returns (uint256) {
        if (_votes.contains(pool)) {
            return _votes.get(pool);
        }
        return 0;
    }

    /**
     * @dev get voted pools
     */
    function getVotedPools() external view returns (address[] memory) {
        return _votes.keys();
    }

    /**
     * returns votedPoolsLengths
     */
    function getVotedPoolsLength() external view returns (uint256) {
        return _votes.length();
    }

    function getVotedPoolsAtIndex(uint256 index) external view returns (address, uint256) {
        return _votes.at(index);
    }

    function getMlumStaking() external view returns (IMlumStaking) {
        return _mlumStaking;
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

    function hasVoted(uint256 periodId, uint256 tokenId) external view override returns (bool) {
        return _hasVotedInPeriod[periodId][tokenId];
    }

    function ownerOf(uint256 tokenId, address account) external view returns (bool) {
        return _mlumStaking.ownerOf(tokenId) == account;
    }

    /**
     * @dev get bribe rewarder at index
     */
    function getUserBribeRewaderAt(uint256 period, uint256 tokenId, uint256 index)
        external
        view
        returns (IBribeRewarder)
    {
        return _userBribesPerPeriod[period][tokenId][index];
    }

    /**
     * Returns number of bribe rewarders for period and tokenId
     */
    function getUserBribeRewarderLength(uint256 period, uint256 tokenId) external view returns (uint256) {
        return _userBribesPerPeriod[period][tokenId].length;
    }

    /**
     * checks if rewarder registers on rewarderfactory
     */
    function _checkRegisterCaller(IBribeRewarder rewarder) internal view {
        if (_rewarderFactory.getRewarderType(rewarder) != IRewarderFactory.RewarderType.BribeRewarder) {
            revert Voter__InvalidRegisterCaller();
        }
    }

    /**
     * Get rewarder at index
     * @param period - period id
     * @param pool - pool address
     * @param index - index
     */
    function getBribeRewarderAt(uint256 period, address pool, uint256 index)
        external
        view
        override
        returns (IBribeRewarder)
    {
        return _bribesPerPriod[period][pool][index];
    }

    /**
     * Returns rewarders length
     * @param period - voting period id
     * @param pool - pool address
     */
    function getBribeRewarderLength(uint256 period, address pool) external view override returns (uint256) {
        return _bribesPerPriod[period][pool].length;
    }

    /**
     * Get start and endtime for period
     * @param periodId - periodId
     * @return startTime - periodStartTime
     * @return endTime - period endTime
     */
    function getPeriodStartEndtime(uint256 periodId) external view override returns (uint256, uint256) {
        return (_startTimes[periodId].startTime, _startTimes[periodId].endTime);
    }

    /**
     * @dev returns the latest ended period, either the period before the current period
     * or the current period if its ended. Reverts if no period is finished so far
     */
    function getLatestFinishedPeriod() external view override returns (uint256) {
        // the current period ended and no new period exists
        if (_votingEnded()) {
            return _currentVotingPeriodId;
        }
        if (_currentVotingPeriodId == 0) revert IVoter__NoFinishedPeriod();
        return _currentVotingPeriodId - 1;
    }

    /**
     * Get duration of voting epoch
     */
    function getPeriodDuration() external view returns (uint256) {
        return _periodDuration;
    }

    /**
     * Get minimum time which a position needs be locked for voting
     */
    function getMinimumLockTime() external view returns (uint256) {
        return _minimumLockTime;
    }

    /**
     * mininmum votes per pool
     */
    function getMinimumVotesPerPool() external view returns (uint256) {
        return _minimumVotesPerPool;
    }

    /**
     * @dev update duration of voding period
     * @param duration - duration in seconds
     */
    function updatePeriodDuration(uint256 duration) external onlyOwner {
        if (duration == 0) revert IVoter_ZeroValue();
        _periodDuration = duration;
        emit VotingDurationUpdated(duration);
    }

    /**
     * @dev update minimum time a position needs to be locked
     * @param lockTime - locktime in seconds
     */
    function updateMinimumLockTime(uint256 lockTime) external onlyOwner {
        if (lockTime == 0) revert IVoter_ZeroValue();
        _minimumLockTime = lockTime;
        emit MinimumLockTimeUpdated(lockTime);
    }

    /**
     * @dev update votes per pool
     * @param votesPerPool - minimum votes per pool got counted into farms
     */
    function updateMinimumVotesPerPool(uint256 votesPerPool) external onlyOwner {
        // no check needed
        _minimumVotesPerPool = votesPerPool;
        emit MinimumVotesPerPoolUpdated(votesPerPool);
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
