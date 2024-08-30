// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable2StepUpgradeable} from "openzeppelin-contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {SafeERC20, IERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Clone} from "../libraries/Clone.sol";
import {Constants} from "../libraries/Constants.sol";
import {Math} from "../libraries/Math.sol";
import {IVoter} from "../interfaces/IVoter.sol";
import {IMlumStaking} from "../interfaces/IMlumStaking.sol";

import {IRewarderFactory} from "../interfaces/IRewarderFactory.sol";

import "../interfaces/IBribeRewarder.sol";

import "forge-std/console.sol";

/**
 * @title BribeRewarder
 * @author MagicSea / BlueLabs
 * @notice bribe pools and pay rewards to voters
 */
contract BribeRewarder is Ownable2StepUpgradeable, Clone, IBribeRewarder {
    using SafeERC20 for IERC20;
    using Math for uint256;

    address public immutable implementation;

    address internal immutable _caller; // Voter

    address internal immutable _rewarderFactory;

    /// @dev period where bribes start
    uint256 internal _startVotingPeriod;

    /// @dev last period for bribes
    uint256 internal _lastVotingPeriod;

    uint256 internal _amountPerPeriod;

    /// @dev period => account => user votes
    mapping(uint256 periodId => mapping(address account => uint256 deltaVotes)) internal _userVotesPerPeriod;

    /// @dev period => account => rewardDebt
    mapping(uint256 periodId => mapping(address account => uint256)) internal _rewardDebt;

    struct RewardPerPeriod {
        uint256 totalVotes;
        uint256 accRewardPerShare;
        uint256 lastUpdateTimestamp;
    }

    /// @dev holds all reward information over first to last bribe periods / epoches
    RewardPerPeriod[] internal _rewards;


    modifier onlyVoter() {
        _checkVoter();
        _;
    }

    constructor(address caller, address rewarderFactory) {
        _caller = caller;
        implementation = address(this);
        _rewarderFactory = rewarderFactory;

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
     * Deposits votes for the given period and user account, only callable by the voter contract
     *
     * @param periodId period id of the voting period
     * @param account user account which voted
     * @param deltaAmount amount of votes
     */
    function deposit(uint256 periodId, address account, uint256 deltaAmount) public override onlyVoter {
        _deposit(periodId, account, deltaAmount);
        emit Deposited(periodId, account, _pool(), deltaAmount);
    }

    /**
     * Claim the reward for the given account
     *
     * @param account indivual voter
     */
    function claim(address account) external override {
        uint256 endPeriod = IVoter(_caller).getLatestFinishedPeriod();
        uint256 totalAmount;

        if (endPeriod > _lastVotingPeriod) endPeriod = _lastVotingPeriod;

        // calc emission per period cause every period can every other durations
        for (uint256 i = _startVotingPeriod; i <= endPeriod; ++i) {
            totalAmount += _claim(i, account);
        }

        emit Claimed(account, _pool(), totalAmount);
    }


    /**
    * Get pending rewards for account
    * @param account user account
    */
    function getPendingReward(address account) external view override returns (uint256 totalReward) {
        uint256 endPeriod = IVoter(_caller).getLatestFinishedPeriod();

        if (endPeriod > _lastVotingPeriod) endPeriod = _lastVotingPeriod;

        for (uint256 periodId = _startVotingPeriod; periodId <= endPeriod; ++periodId) {
            RewardPerPeriod storage reward = _rewards[_indexByPeriodId(periodId)];

            uint256 totalRewards = _calculateRewards(reward.lastUpdateTimestamp, periodId);
            uint256 totalSupply = reward.totalVotes;
            if (totalSupply > 0) {
                uint256 accRewardPerShare = reward.accRewardPerShare + _shiftPrecision(totalRewards) / totalSupply;
                totalReward += _unshiftPrecision(_userVotesPerPeriod[periodId][account] * accRewardPerShare) - _rewardDebt[periodId][account];
            } else {
                totalReward += _unshiftPrecision(_userVotesPerPeriod[periodId][account] * reward.accRewardPerShare) - _rewardDebt[periodId][account];
            }
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

    /**
     * @dev Returns the address of the token to be distributed as rewards.
     */
    function getToken() public view virtual override returns (IERC20) {
        return _token();
    }

    /**
     * @dev Returns the pool address which is bribed
     */
    function getPool() public view virtual override returns (address) {
        return _pool();
    }

    function getCaller() public view virtual override returns (address) {
        return _caller;
    }

    /**
     * @dev Returns the start period id of the bribed periods
     */
    function getStartVotingPeriodId() public view virtual override returns (uint256) {
        return _startVotingPeriod;
    }

    /**
     * @dev Returns the last period id of the bribed periods
     */
    function getLastVotingPeriodId() public view virtual override returns (uint256) {
        return _lastVotingPeriod;
    }

    /**
     * @dev Returns the amount of reward per period
     */
    function getAmountPerPeriod() external view override returns (uint256) {
        return _amountPerPeriod;
    }

    // INTERNAL FUNCTIONS

    /**
     * @dev bribe pool for start and last id
     *
     * @param startId start period id
     * @param lastId last period to reward
     * @param amountPerPeriod reward amount for each period
     */
    function _bribe(uint256 startId, uint256 lastId, uint256 amountPerPeriod) internal {
        _checkAlreadyInitialized();

        if (lastId < startId) revert BribeRewarder__WrongEndId();
        if (amountPerPeriod == 0) revert BribeRewarder__ZeroReward();

        // check whitelist
        (, uint256 minAmount) = IRewarderFactory(_rewarderFactory).getWhitelistedTokenInfo(address(_token()));
        if (amountPerPeriod < minAmount) {
            revert BribeRewarder__AmountTooLow();
        }


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

        // create rewards per period
        uint256 bribeEpochs = _calcPeriods(startId, lastId);
        for (uint256 i = 0; i <= bribeEpochs; ++i) {
            RewardPerPeriod storage period = _rewards.push();
            period.lastUpdateTimestamp = block.timestamp;
        }

        IVoter(_caller).onRegister();

        emit BribeInit(startId, lastId, amountPerPeriod);
    }

    /**
     * Deposit votes for the given period and user account
     *
     * @param periodId period id of the voting period
     * @param account account
     * @param deltaAmount amount of votes
     */
    function _deposit(uint256 periodId, address account, uint256 deltaAmount) internal {
        uint256 accRewardPerShare = _update(periodId, deltaAmount);

        _userVotesPerPeriod[periodId][account] += deltaAmount;
        _rewardDebt[periodId][account] += _unshiftPrecision(deltaAmount * accRewardPerShare);
    }

    /**
     * @dev Claim the reward for the given period and account
     *
     * @param periodId period id of the voting period
     * @param account indivual voter
     */
    function _claim(uint256 periodId, address account) internal returns (uint256 rewardAmount) {
        uint256 accRewardPerShare = _update(periodId, 0);

       rewardAmount = _unshiftPrecision(_userVotesPerPeriod[periodId][account] * accRewardPerShare) - _rewardDebt[periodId][account];
        if (rewardAmount > 0) {
            IERC20 token = _token();
            _safeTransferTo(token, account, rewardAmount);
        }
    }

    /**
     * Update rewards for given period
     *
     * @param periodId period id of the voting period
     * @param amountToAdd amount of votes to add to total votes, 0 if no votes added (e.g. on claim)
     *
     * @return accRewardPerShare updated reward per share (scaled by ACC_PRECISION)
     */
    function _update(uint256 periodId, uint256 amountToAdd) internal returns (uint256) {
        RewardPerPeriod storage reward = _rewards[_indexByPeriodId(periodId)];

        // extra check so we dont calc rewards before starttime
        (uint256 startTime,) = IVoter(_caller).getPeriodStartEndtime(periodId);
        if (block.timestamp <= startTime || reward.totalVotes == 0) {
            reward.lastUpdateTimestamp = startTime;
        }

        uint256 totalRewards = _calculateRewards(reward.lastUpdateTimestamp, periodId);

        reward.accRewardPerShare = reward.totalVotes > 0 ? reward.accRewardPerShare + _shiftPrecision(totalRewards)  / reward.totalVotes : 0;
        reward.totalVotes += amountToAdd;

        if (block.timestamp > reward.lastUpdateTimestamp) {
            reward.lastUpdateTimestamp = block.timestamp;
        }

        return reward.accRewardPerShare;
    }

    /**
     * @dev Calculate rewards for given period depending on the last update timestamp
     *
     * @param lastUpdateTimestamp last update timestamp
     * @param periodId period id of the voting period
     *
     * @return rewards for the period
     */
    function _calculateRewards(uint256 lastUpdateTimestamp, uint256 periodId) internal view returns (uint256) {
        (uint256 startTime, uint256 endTime) = IVoter(_caller).getPeriodStartEndtime(periodId);

        if (endTime == 0 || startTime > block.timestamp) {
            return 0;
        }

        uint256 duration = endTime - startTime;
        uint256 timestamp = block.timestamp > endTime ? endTime : block.timestamp;

        return timestamp > lastUpdateTimestamp ? (timestamp - lastUpdateTimestamp) * _amountPerPeriod / duration : 0;
    }

    /**
     * @dev Returns the index of the period in the rewards array.
     * @param periodId The period ID.
     * @return The index of the period in the rewards array.
     */
    function _indexByPeriodId(uint256 periodId) internal view returns (uint256) {
        return periodId - _startVotingPeriod;
    }

    /**
     * @dev Reverts if the contract has already been initialized.
     */
    function _checkAlreadyInitialized() internal view virtual {
        if (_rewards.length > 0) {
            revert BribeRewarder__AlreadyInitialized();
        }
    }

    /**
     * @dev Calculates the total amount of tokens to be distributed as rewards.
     * @param startId The start period ID.
     * @param lastId The last period ID.
     * @param amountPerPeriod The amount of tokens to be distributed per period.
     * @return The total amount of tokens to be distributed as rewards.
     */
    function _calcTotalAmount(uint256 startId, uint256 lastId, uint256 amountPerPeriod)
        internal
        pure
        returns (uint256)
    {
        return _calcPeriods(startId, lastId) * amountPerPeriod;
    }

    /**
     * @dev Calculates the number of periods between the start and last period.
     * @param startId The start period ID.
     * @param lastId The last period ID.
     * @return The number of periods between the start and last period.
     */
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
     * @dev Transfers any remaining tokens to the specified account.
     * If the bribe rewarder is not initialized, the owner can sweep the funds.
     *
     * Otherwise only the voter admin can sweep the funds.
     *
     * @param token The token to transfer.
     * @param account The account to transfer the tokens to.
     */
    function sweep(IERC20 token, address account) public virtual {

        // if not initialized, bribe rewarder owner can sweep the funds
        if (_rewards.length == 0) {
           _checkOwner();
        } else {
            // get owner of voter (= _caller)
            if (Ownable2StepUpgradeable(_caller).owner() != msg.sender) {
                revert BribeRewarder__OnlyVoterAdmin();
            }
        }

        uint256 balance = _balanceOfThis(token);

        _safeTransferTo(token, account, balance);

        emit Swept(token, account, balance);
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

    /**
     * @dev Shifts value to the left by the precision bits.
     * @param value value to shift
     */
    function _shiftPrecision(uint256 value) internal pure returns (uint256) {
        return value << Constants.ACC_PRECISION_BITS;
    }

    /**
     * @dev Unshifts value to the right by the precision bits.
     * @param value value to unshift
     */
    function _unshiftPrecision(uint256 value) internal pure returns (uint256) {
        return value >> Constants.ACC_PRECISION_BITS;
    }


}
