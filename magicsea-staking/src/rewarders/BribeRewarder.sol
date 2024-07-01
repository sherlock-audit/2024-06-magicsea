// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable2StepUpgradeable} from "openzeppelin-contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {SafeERC20, IERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Clone} from "../libraries/Clone.sol";
import {Constants} from "../libraries/Constants.sol";
import {Math} from "../libraries/Math.sol";
import {Amounts} from "../libraries/Amounts.sol";
import {Rewarder2} from "../libraries/Rewarder2.sol";
import {IVoter} from "../interfaces/IVoter.sol";
import {IMlumStaking} from "../interfaces/IMlumStaking.sol";

import "../interfaces/IBribeRewarder.sol";

import "forge-std/console.sol";

/**
 * @title BribeRewarder
 * @author MagicSea / BlueLabs
 * @notice bribe pools and pay rewards to voters
 *
 * TODO
 * - emit per seconds,
 * - accTokenPerShare per periodId,
 * - claim with tokenId and accrue all periods before start bribe and after last bribe
 * - pendingReward only with tokenId
 * - optionals: claim with mutliple tokenIds
 *
 */
contract BribeRewarder is Ownable2StepUpgradeable, Clone, IBribeRewarder {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using Amounts for Amounts.Parameter;
    using Rewarder2 for Rewarder2.Parameter;

    address public immutable implementation;

    address internal immutable _caller; // Voter

    /// @dev period => tokenId => parameter
    mapping(uint256 => Amounts.Parameter) internal _userVotesPerVotingPeriod;

    /// @dev period where bribes start
    uint256 internal _startVotingPeriod;

    /// @dev last period for bribes
    uint256 internal _lastVotingPeriod;

    uint256 internal _amountPerPeriod;

    /// period => tokenId => rewardDebt
    mapping(uint256 => mapping(uint256 => uint256)) private _rewardDebt;

    struct RewardPerPeriod {
        Amounts.Parameter userVotes;
        Rewarder2.Parameter rewarder;
    }

    RewardPerPeriod[] internal _rewards;

    mapping(uint256 => mapping(uint256 => uint256)) private unclaimedRewards;

    /// @dev timestamp of last update, bribes are continuous
    uint256 internal _lastUpdateTimestamp;

    // TODO
    // accTokenPerShare
    // rewards Per Sec over bribing period

    modifier onlyVoter() {
        _checkVoter();
        _;
    }

    constructor(address caller) {
        _caller = caller;
        implementation = address(this);

        _disableInitializers();
    }

    /**
     * @dev Initializes the BaseRewarder contract.
     * @param initialOwner The initial owner of the contract.
     */
    function initialize(address initialOwner) public virtual initializer {
        __Ownable_init(initialOwner);
    }

    /**
     * @dev Allows the contract to receive native tokens only if the token is address(0).
     */
    receive() external payable {
        _nativeReceived();
    }

    /**
     * @dev Allows the contract to receive native tokens only if the token is address(0).
     */
    fallback() external payable {
        _nativeReceived();
    }

    /**
     * @dev Funds the rewarder and bribes for given start and end period with the amount for each period
     * @param startId start period id
     * @param lastId last period to reward
     * @param amountPerPeriod reward amount for each period
     */
    function fundAndBribe(uint256 startId, uint256 lastId, uint256 amountPerPeriod) external payable onlyOwner {
        IERC20 token = _token();
        uint256 totalAmount = _calcTotalAmount(startId, lastId, amountPerPeriod);

        if (address(token) == address(0)) {
            if (msg.value < totalAmount) {
                revert BribeRewarder__InsufficientFunds();
            }
        } else {
            token.safeTransferFrom(msg.sender, address(this), totalAmount);
        }

        _bribe(startId, lastId, amountPerPeriod);
    }

    /**
     * @dev Bribes for given start and end period with the amount for each period
     * @param startId start period id
     * @param lastId last period to reward
     * @param amountPerPeriod reward amount for each period
     */
    function bribe(uint256 startId, uint256 lastId, uint256 amountPerPeriod) public onlyOwner {
        _bribe(startId, lastId, amountPerPeriod);
    }

    /**
     * Deposits votes for the given period and token id, only callable by the voter contract
     *
     * @param periodId period id of the voting period
     * @param tokenId owners token id
     * @param deltaAmount amount of votes
     */
    function deposit(uint256 periodId, uint256 tokenId, uint256 deltaAmount) public onlyVoter {
        _modify(periodId, tokenId, deltaAmount.toInt256(), false);

        emit Deposited(periodId, tokenId, _pool(), deltaAmount);
    }

    /**
     * Claim the reward for the given period and token id
     * @param tokenId token id of the owner
     */
    function claim(uint256 tokenId) external override {
        uint256 endPeriod = IVoter(_caller).getLatestFinishedPeriod();

        uint256 totalAmount;

        // calc emission per period cause every period can every other durations
        for (uint256 i = _startVotingPeriod; i <= endPeriod; ++i) {
            totalAmount += _modify(i, tokenId, 0, true);
        }

        emit Claimed(tokenId, _pool(), totalAmount);
    }

    function getPendingReward(uint256 tokenId) external view override returns (uint256 totalReward) {
        uint256 endPeriod = IVoter(_caller).getLatestFinishedPeriod();

        for (uint256 periodId = _startVotingPeriod; periodId <= endPeriod; ++periodId) {
            RewardPerPeriod storage reward = _rewards[_indexByPeriodId(periodId)];
            Amounts.Parameter storage amounts = reward.userVotes;
            Rewarder2.Parameter storage rewarder = reward.rewarder;

            uint256 balance = amounts.getAmountOf(tokenId);
            uint256 totalSupply = amounts.getTotalAmount();

            uint256 totalRewards = totalSupply > 0 ? _calculateRewards(periodId) : 0;

            totalReward += rewarder.getPendingReward(bytes32(tokenId), balance, totalSupply, totalRewards);
        }
        return totalReward;
    }

    /**
     * Get the bribe periods
     * @return bribed pool address
     * @return array of bribed period ids
     */
    function getBribePeriods() external view returns (address, uint256[] memory) {
        uint256 length = (_lastVotingPeriod - _startVotingPeriod) + 1;
        uint256[] memory periodIds = new uint256[](length);

        uint256 period = _startVotingPeriod;
        for (uint256 i = 0; i < length; ++i) {
            periodIds[i] = period;
            period++;
        }
        return (_pool(), periodIds);
    }

    function getToken() public view virtual override returns (IERC20) {
        return _token();
    }

    function getPool() public view virtual override returns (address) {
        return _pool();
    }

    function getCaller() public view virtual override returns (address) {
        return _caller;
    }

    function getStartVotingPeriodId() public view virtual override returns (uint256) {
        return _startVotingPeriod;
    }

    function getLastVotingPeriodId() public view virtual override returns (uint256) {
        return _lastVotingPeriod;
    }

    // INTERNAL FUNCTIONS

    /**
     * @dev bribe pool for start and last id
     */
    function _bribe(uint256 startId, uint256 lastId, uint256 amountPerPeriod) internal {
        _checkAlreadyInitialized();
        if (lastId < startId) revert BribeRewarder__WrongEndId();
        if (amountPerPeriod == 0) revert BribeRewarder__ZeroReward();

        IVoter voter = IVoter(_caller);

        if (startId <= voter.getCurrentVotingPeriod()) {
            revert BribeRewarder__WrongStartId();
        }

        uint256 totalAmount = _calcTotalAmount(startId, lastId, amountPerPeriod);

        uint256 balance = _balanceOfThis(_token());

        if (balance < totalAmount) revert BribeRewarder__InsufficientFunds();

        _startVotingPeriod = startId;
        _lastVotingPeriod = lastId;
        _amountPerPeriod = amountPerPeriod;

        // create rewads per period
        uint256 bribeEpochs = _calcPeriods(startId, lastId);
        for (uint256 i = 0; i <= bribeEpochs; ++i) {
            _rewards.push();
        }

        _lastUpdateTimestamp = block.timestamp;

        IVoter(_caller).onRegister();

        emit BribeInit(startId, lastId, amountPerPeriod);
    }

    function _modify(uint256 periodId, uint256 tokenId, int256 deltaAmount, bool isPayOutReward)
        private
        returns (uint256 rewardAmount)
    {
        if (!IVoter(_caller).ownerOf(tokenId, msg.sender)) {
            revert BribeRewarder__NotOwner();
        }

        // extra check so we dont calc rewards before starttime
        (uint256 startTime,) = IVoter(_caller).getPeriodStartEndtime(periodId);
        if (block.timestamp <= startTime) {
            _lastUpdateTimestamp = startTime;
        }

        RewardPerPeriod storage reward = _rewards[_indexByPeriodId(periodId)];
        Amounts.Parameter storage amounts = reward.userVotes;
        Rewarder2.Parameter storage rewarder = reward.rewarder;

        (uint256 oldBalance, uint256 newBalance, uint256 oldTotalSupply,) = amounts.update(tokenId, deltaAmount);

        uint256 totalRewards = _calculateRewards(periodId);

        rewardAmount = rewarder.update(bytes32(tokenId), oldBalance, newBalance, oldTotalSupply, totalRewards);

        if (block.timestamp > _lastUpdateTimestamp) {
            _lastUpdateTimestamp = block.timestamp;
        }

        if (isPayOutReward) {
            rewardAmount = rewardAmount + unclaimedRewards[periodId][tokenId];
            unclaimedRewards[periodId][tokenId] = 0;
            if (rewardAmount > 0) {
                IERC20 token = _token();
                _safeTransferTo(token, msg.sender, rewardAmount);
            }
        } else {
            unclaimedRewards[periodId][tokenId] += rewardAmount;
        }
    }

    function _calculateRewards(uint256 periodId) internal view returns (uint256) {
        (uint256 startTime, uint256 endTime) = IVoter(_caller).getPeriodStartEndtime(periodId);

        if (endTime == 0 || startTime > block.timestamp) {
            return 0;
        }

        uint256 duration = endTime - startTime;
        uint256 emissionsPerSecond = _amountPerPeriod / duration;

        uint256 lastUpdateTimestamp = _lastUpdateTimestamp;
        uint256 timestamp = block.timestamp > endTime ? endTime : block.timestamp;
        return timestamp > lastUpdateTimestamp ? (timestamp - lastUpdateTimestamp) * emissionsPerSecond : 0;
    }

    function _indexByPeriodId(uint256 periodId) internal view returns (uint256) {
        return periodId - _startVotingPeriod;
    }

    function _checkAlreadyInitialized() internal view virtual {
        if (_rewards.length > 0) {
            revert BribeRewarder__AlreadyInitialized();
        }
    }

    function _calcTotalAmount(uint256 startId, uint256 lastId, uint256 amountPerPeriod)
        internal
        pure
        returns (uint256)
    {
        return _calcPeriods(startId, lastId) * amountPerPeriod;
    }

    function _calcPeriods(uint256 startId, uint256 lastId) internal pure returns (uint256) {
        return (lastId - startId) + 1;
    }

    /**
     * @dev Safely transfers the specified amount of tokens to the specified account.
     * @param token The token to transfer.
     * @param account The account to transfer the tokens to.
     * @param amount The amount of tokens to transfer.
     */
    function _safeTransferTo(IERC20 token, address account, uint256 amount) internal virtual {
        if (amount == 0) return;

        if (address(token) == address(0)) {
            (bool s,) = account.call{value: amount}("");
            if (!s) revert BribeRewarder__NativeTransferFailed();
        } else {
            token.safeTransfer(account, amount);
        }
    }

    /**
     * @dev Blocks the renouncing of ownership.
     */
    function renounceOwnership() public pure override {
        revert BribeRewarder__CannotRenounceOwnership();
    }

    /**
     * @dev Returns the address of the token to be distributed as rewards.
     * @return The address of the token to be distributed as rewards.
     */
    function _token() internal pure virtual returns (IERC20) {
        return IERC20(_getArgAddress(0));
    }

    /**
     * @dev Returns the pool ID of the staking pool.
     * @return The pool ID.
     */
    function _pool() internal pure virtual returns (address) {
        return _getArgAddress(20);
    }

    function _periods() internal view virtual returns (uint256) {
        return (_lastVotingPeriod - _startVotingPeriod) + 1;
    }

    /**
     * @dev Returns the balance of the specified token held by the contract.
     * @param token The token to check the balance of.
     * @return The balance of the token held by the contract.
     */
    function _balanceOfThis(IERC20 token) internal view virtual returns (uint256) {
        return address(token) == address(0) ? address(this).balance : token.balanceOf(address(this));
    }

    /**
     * @dev check if sender is _caller (= voter)
     */
    function _checkVoter() internal view virtual {
        if (msg.sender != address(_caller)) {
            revert BribeRewarder__OnlyVoter();
        }
    }

    /**
     * @dev Reverts if the contract receives native tokens and the rewarder is not native.
     */
    function _nativeReceived() internal view virtual {
        if (address(_token()) != address(0)) {
            revert BribeRewarder__NotNativeRewarder();
        }
    }

    function getAmountPerPeriod() external view override returns (uint256) {
        return _amountPerPeriod;
    }
}
