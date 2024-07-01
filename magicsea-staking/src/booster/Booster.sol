// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeERC20, IERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Ownable2StepUpgradeable} from "openzeppelin-contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {ReentrancyGuard} from "openzeppelin/utils/ReentrancyGuard.sol";
import {EnumerableSet} from "openzeppelin/utils/structs/EnumerableSet.sol";

/**
 * @author BlueLabs / MagicSea
 * @title MagicSea Booster
 * @dev Refine LUM to MLUM (MagicLum) on IotaEVM
 *
 * This contracts emits already staked MLUM, and is NOT the owner of MLUM
 */
contract Booster is Ownable2StepUpgradeable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public immutable PRECISION_FACTOR;

    uint256 public constant BURN_AMOUNT_PRECISION_FACTOR = 1e25;

    /// @notice The reward token e.g. MagicLum
    IERC20 public immutable rewardToken;

    /// @notice The staked token e.g. LumToken
    IERC20 public immutable stakedToken;

    /// @notice keeps track about the total supply of staked tokens
    uint256 public stakedSupply;

    uint256 public startTime;

    uint256 public lastRewardTime;

    uint256 public accTokenPerShare;

    uint256 public bonusEndTime;

    /// @notice keeps track about all burned staked tokens
    uint256 public totalBurned;

    /// @notice time after which staked tokens is fully burned
    uint256 public burnAfterTime = 2628000; // 30.14.. days;

    uint256 public lastBurnTime;

    /// @notice linear burn rate
    uint256 public totalBurnMultiplier;

    /// @notice time when stakedsupply is burned,
    // needed for readjustment of the burn multiplier
    uint256 public totalBurnUntil;

    /// @notice pause between burns in seconds
    uint256 public burnPause = 10 minutes;

    /// @notice user reward for calling a burn cycle
    uint256 public rewardFee = 200; // 2%
    uint256 public constant MIN_REWARD_FEE = 10; // min. 0.1 %
    uint256 public constant MAX_REWARD_FEE = 1000; // max. 10%

    /// @notice user penalty if user wants to withdraw before end of lock time
    uint256 public withdrawFee = 2000; // 20% on emergency withdraw
    uint256 public constant MAX_WITHDRAW_FEE = 2000; // max 20%

    uint32 public constant MAX_LOCK_TIME = 14 days; // max 14 days

    uint256 public constant MIN_AFTER_BURN_TIME = 2 days; // Two days

    // Info of each user that stakes tokens (stakedToken)
    mapping(address => UserInfo) public userInfo;

    address[] private users;

    /// @notice reward slices
    MonthlyReward[] public slices;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 lockedAt;
        uint256 rewardClaim; // rewards saved after burning tokens
        bool initialized;
        uint256 burnRound;
    }

    // holds the token reward for every months
    struct MonthlyReward {
        uint256 index;
        uint256 startTime;
        uint256 endTime;
        uint256 rewardPerSec;
    }

    struct BurnSnapshot {
        uint256 timestamp;
        uint256 stakedSupplyBeforeBurn;
        uint256 burnedAmount;
        uint256 accRewardPerShare;
        uint256 burnPerShare;
    }

    /// @notice all burn snapshots
    BurnSnapshot[] public burnSnapshots;

    uint256 public constant SEC_PER_MONTH = 2628000; // financial month ~ 30 days

    address public constant BURN_ADMIN = 0x000000000000000000000000000000000000dEaD;

    uint32 public time_locked;

    EnumerableSet.AddressSet private allowlist;
    bool public isAllowListEnabled;

    bool public initialized = false;

    // EVENTS
    event Init(address stakedToken, address rewardToken, uint256 startTime, address indexed admin);
    event HarvestPosition(address indexed user, uint256 amount);
    event DepositPosition(address indexed user, uint256 amount);
    event WithdrawPosition(address indexed user, uint256 amount);
    event BurnStakedToken(uint256 amount);
    event UpdateBurnMultiplier(address indexed user, uint256 indexed multiplier);
    event UpdateBurnBlockQuota(address indexed user, uint256 indexed blockQuota);

    event UpdateAllowListEnabled(address indexed user, bool oldValue, bool newValue);
    event AddToAllowList(address indexed user, address indexed account);
    event RemoveFromAllowList(address indexed user, address indexed account);
    event UpdateTimeLocked(address indexed user, uint256 oldValue, uint256 newValue);
    event UpdateBurnAfterTime(address indexed user, uint256 oldValue, uint256 newValue);
    event UpdateBatchSize(address indexed user, uint256 oldValue, uint256 newValue);
    event UpdateRewardFee(address indexed user, uint256 oldValue, uint256 newValue);
    event UpdateWithdrawFee(address indexed user, uint256 oldValue, uint256 newValue);
    event UpdateBurnPause(address indexed user, uint256 oldValue, uint256 newValue);

    event LogBurn(
        address indexed user,
        uint256 timestamp,
        uint256 accPerShare,
        uint256 burnAmount,
        uint256 supplyBefore,
        uint256 supplyAfter
    );

    event EmergencyUnlock(address indexed user, uint256 amount, uint256 burnAmount, uint256 rewards);

    event RewardsAdded(address indexed user, uint256 amount);

    // MODIFIERS

    modifier onlyAllowed() {
        if (isAllowListEnabled) {
            require(allowlist.contains(msg.sender), "not allowed");
            _;
        } else {
            _;
        }
    }

    constructor(IERC20 _rewardToken, IERC20 _stakedToken) {
        rewardToken = _rewardToken;
        stakedToken = _stakedToken;

        uint256 decimalsRewardToken = uint256(IERC20Metadata(address(_rewardToken)).decimals());
        require(decimalsRewardToken < 20, "Must be inferior to 20");

        PRECISION_FACTOR = uint256(10 ** (uint256(30) - (decimalsRewardToken)));
    }

    /**
     * @dev Initializes the contract.
     * @param _startTime The time when the booster starts.
     * @param _monthlyRewardsInWei The rewards per month in WEI.
     * @param initialOwner The initial owner of the contract.
     */
    function initialize(uint256 _startTime, uint256[] memory _monthlyRewardsInWei, address initialOwner)
        external
        reinitializer(2)
    {
        __Ownable_init(initialOwner);

        startTime = _startTime;

        _createMonthlyRewardSlices(_monthlyRewardsInWei);

        lastRewardTime = _startTime;
        bonusEndTime = slices[slices.length - 1].endTime;

        time_locked = 60 * 60 * 72; // 72 h

        emit Init(address(stakedToken), address(rewardToken), _startTime, initialOwner);
    }

    /// EXTERNAL ONLY OWNER FUNCTIONS

    /**
     * @dev Adding additional rewards
     * @param monthlyRewardsInWei: array of monthly rewards in WEI
     */
    function addRewards(uint256[] memory monthlyRewardsInWei) external onlyOwner {
        MonthlyReward memory lastSlice = slices[slices.length - 1];
        uint256 currentTime = lastSlice.endTime + 1;
        uint256 startIndex = lastSlice.index + 1;
        for (uint256 i = 0; i < monthlyRewardsInWei.length; i++) {
            slices.push(
                MonthlyReward({
                    index: startIndex,
                    startTime: currentTime,
                    endTime: currentTime + SEC_PER_MONTH,
                    rewardPerSec: monthlyRewardsInWei[i]
                })
            );
            startIndex = startIndex + 1;
            currentTime = currentTime + SEC_PER_MONTH + 1;
        }
        bonusEndTime = currentTime - 1;

        emit RewardsAdded(msg.sender, slices.length);
    }

    /**
     * @dev returns length of reward slices array
     */
    function rewardSlicesLength() external view returns (uint256) {
        return slices.length;
    }

    function getRewardSlice(uint256 index)
        external
        view
        returns (uint256 _startTime, uint256 _endTime, uint256 _rewardPerSec)
    {
        require(index < slices.length, "out of index");

        MonthlyReward memory slice = slices[index];

        _startTime = slice.startTime;
        _endTime = slice.endTime;
        _rewardPerSec = slice.rewardPerSec;
    }

    /**
     * @dev adds account to allowlist, make sure allowlist is enabled
     * @param account: user account to add
     */
    function allowAccount(address account) external onlyOwner {
        require(account != address(0), "Address must not be null");
        if (allowlist.add(account)) {
            emit AddToAllowList(msg.sender, account);
        }
    }

    /**
     * @dev removes account from allowlist, make sure allowlist is enabled
     * @param account: user account to remove
     */
    function disallowAccount(address account) external onlyOwner {
        require(account != address(0), "Address must not be null");
        if (allowlist.remove(account)) {
            emit RemoveFromAllowList(msg.sender, account);
        }
    }

    /**
     * @dev enable/disable allowlist
     * @param _enable: true/false
     */
    function enableAllowlist(bool _enable) external onlyOwner {
        bool current = isAllowListEnabled;
        require(current != _enable, "no new value");
        isAllowListEnabled = _enable;
        emit UpdateAllowListEnabled(msg.sender, current, _enable);
    }

    /**
     * @dev bulk update allow list
     */
    function allowAccounts(address[] memory _accounts) external onlyOwner {
        for (uint256 i = 0; i < _accounts.length; ++i) {
            address current = _accounts[i];
            require(current != address(0), "Address must not be null");
            if (allowlist.add(current)) {
                emit AddToAllowList(msg.sender, current);
            }
        }
    }

    /**
     * @dev bulk update allow list
     */
    function disallowAccounts(address[] memory _accounts) external onlyOwner {
        for (uint256 i = 0; i < _accounts.length; ++i) {
            address current = _accounts[i];
            require(current != address(0), "Address must not be null");
            if (allowlist.remove(current)) {
                emit RemoveFromAllowList(msg.sender, current);
            }
        }
    }

    /**
     * @dev update lock time of user funds
     * @param _time_locked: lock time in seconds, must not exceed MAX_LOCK_TIME and burnAfterTime
     */
    function updateTimeLocked(uint32 _time_locked) external onlyOwner {
        require(_time_locked <= MAX_LOCK_TIME, "update: lock time too high");
        require(burnAfterTime > _time_locked, "update: lock time > burnAfterTime");
        uint256 oldVal = time_locked;
        time_locked = _time_locked;
        emit UpdateTimeLocked(msg.sender, oldVal, _time_locked);
    }

    /**
     * @dev updates time after user staked funds completely burned
     * Warning: burnAfterTime can be set lower then time_locked and thus user funds
     * could be burned ealier then user can withraw
     * @param _burnAfterTime: time in seconds, must be greater than MIN_AFTER_BURN_TIME
     */
    function updateBurnAfterTime(uint256 _burnAfterTime) external onlyOwner {
        require(_burnAfterTime >= MIN_AFTER_BURN_TIME, "update: burn after time too low");
        uint256 oldVal = burnAfterTime;
        burnAfterTime = _burnAfterTime;
        emit UpdateBurnAfterTime(msg.sender, oldVal, _burnAfterTime);
    }

    /**
     * @dev Updates burn pause (min. time between burns)
     * @param _burnPause: duration in seconds
     */
    function updateBurnPause(uint256 _burnPause) external onlyOwner {
        uint256 old = burnPause;
        burnPause = _burnPause;
        emit UpdateBurnPause(msg.sender, old, _burnPause);
    }

    /**
     * @dev Update reward fee for burn batches
     * @param _newRewardFee: the new reward, must be within MIN_REWARD_FEE and MAX_REWARD_FEE
     */
    function updateRewardFee(uint256 _newRewardFee) external onlyOwner {
        require(_newRewardFee <= MAX_REWARD_FEE, "update: reward fee too high");
        require(_newRewardFee >= MIN_REWARD_FEE, "update: reward fee too small");
        uint256 oldVal = rewardFee;
        rewardFee = _newRewardFee;
        emit UpdateRewardFee(msg.sender, oldVal, _newRewardFee);
    }

    /**
     * @dev Update withdraw fee on emergencyUnlock
     * @param _newWithdrawFee: the new reward, must not exceed MAX_WITHDRAW_FEE
     */
    function updateWithdrawFee(uint256 _newWithdrawFee) external onlyOwner {
        require(_newWithdrawFee <= MAX_WITHDRAW_FEE, "update: withdraw fee too high");
        uint256 oldVal = withdrawFee;
        withdrawFee = _newWithdrawFee;
        emit UpdateWithdrawFee(msg.sender, oldVal, _newWithdrawFee);
    }

    // EXTERNAL FUNCTIONS

    /**
     * @notice Deposit staked tokens and harvest golden pearl if _amount = 0
     * @param _amount: amount to deposit,
     */
    function deposit(uint256 _amount) external nonReentrant onlyAllowed {
        UserInfo storage user = userInfo[msg.sender];

        if (!user.initialized) {
            users.push(msg.sender);
            user.initialized = true;
        }
        _updatePool();

        (uint256 rewards, uint256 amount, uint256 rewardDebt) = _computeSnapshotRewards(user);

        // we save the rewards (if any so far) for harvesting
        user.rewardClaim = user.rewardClaim + rewards;

        //  if (_amount > 0) {
        uint256 amount_old = amount;

        uint256 userAmount = amount + _amount;

        uint256 _burnAfterTime = burnAfterTime; // gas savings
        uint256 _stakedSupply = stakedSupply + _amount;

        totalBurnMultiplier = (_stakedSupply * PRECISION_FACTOR) / (_burnAfterTime);
        totalBurnUntil = block.timestamp + _burnAfterTime;
        stakedSupply = _stakedSupply;

        // set new locked amount based on average locking window
        uint256 _time_locked = time_locked; // gas savings
        uint256 lockedFor = timeToUnlock(msg.sender);

        // avg lockedFor: (lockedFor * amount_old + blocks_locked * _amount) / user.amount
        lockedFor = (lockedFor * amount_old + _time_locked * _amount) / userAmount;

        // set new locked at
        user.lockedAt = block.timestamp - (_time_locked - lockedFor);

        user.amount = userAmount;

        user.burnRound = lastBurnRound();

        user.rewardDebt = rewardDebt + ((_amount * accTokenPerShare) / PRECISION_FACTOR);

        // get tokens from user
        stakedToken.safeTransferFrom(address(msg.sender), address(this), _amount);

        emit DepositPosition(msg.sender, _amount);
    }

    function harvest() external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];

        _updatePool();

        uint256 _accTokenPerShare = accTokenPerShare; // gas savings

        (uint256 rewards, uint256 amount, uint256 rewardDebt) = _computeSnapshotRewards(user);

        uint256 currentPendingReward = ((amount * _accTokenPerShare) / PRECISION_FACTOR) - rewardDebt;

        uint256 pending = user.rewardClaim + rewards + currentPendingReward;

        // reset claim
        user.rewardClaim = 0;

        // set new rewarddebt by adding the calculated rewardDebt and the pending
        user.rewardDebt = (amount * _accTokenPerShare) / PRECISION_FACTOR;

        user.amount = amount;
        user.burnRound = lastBurnRound();

        if (pending > 0) {
            safeGoldenPearlTransfer(address(msg.sender), pending);
        }

        emit HarvestPosition(msg.sender, pending);
    }

    /**
     * @dev Withdraw staked tokens and collect reward tokens
     *
     * @param _amount: amount to withdraw
     */
    function withdrawAndHarvest(uint256 _amount) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];

        require(timeToUnlock(msg.sender) == 0, "Your Tokens still locked you cannot withdraw yet.");

        (uint256 rewards, uint256 amount, uint256 rewardDebt) = _computeSnapshotRewards(user);

        require(amount >= _amount, "Amount to withdraw too high");

        _updatePool();

        uint256 _stakedSupply = stakedSupply; // gas savings
        uint256 _accTokenPerShare = accTokenPerShare; // gas savings

        uint256 latest = amount * _accTokenPerShare;
        uint256 latestRewards = (latest / PRECISION_FACTOR) - rewardDebt;

        uint256 totalRewards = user.rewardClaim + rewards + latestRewards;

        user.rewardDebt = (latest - (_amount * _accTokenPerShare)) / PRECISION_FACTOR;

        uint256 userAmount = amount - _amount;

        _stakedSupply = _stakedSupply - _amount;

        user.amount = userAmount;

        //  adapt the total burn multiplier to the remaining time
        totalBurnMultiplier = (_stakedSupply * PRECISION_FACTOR) / (totalBurnUntil - (block.timestamp));

        stakedSupply = _stakedSupply;

        user.burnRound = lastBurnRound();

        user.rewardClaim = 0;

        // Send rewards and staked tokens back
        safeGoldenPearlTransfer(address(msg.sender), totalRewards);
        stakedToken.safeTransfer(address(msg.sender), _amount);

        emit WithdrawPosition(msg.sender, _amount);
        emit HarvestPosition(msg.sender, totalRewards);
    }

    function lastBurnRound() internal view returns (uint256) {
        return burnSnapshots.length;
    }

    /**
     * @dev emergency unlock payouts the staked tokens and rewards.
     * Warning: This will burn a percentage (withdraw fee) of the staked tokens
     */
    function emergencyUnlock() external nonReentrant {
        require(timeToUnlock(msg.sender) > 0, "already unlocked");

        UserInfo storage user = userInfo[msg.sender];

        (uint256 rewards, uint256 amount, uint256 rewardDebt) = _computeSnapshotRewards(user);
        uint256 latest = amount * accTokenPerShare;
        uint256 latestRewards = (latest / PRECISION_FACTOR) - rewardDebt;
        uint256 totalRewards = user.rewardClaim + rewards + latestRewards;

        uint256 _burnAmount = amount * withdrawFee / 10000;
        uint256 amountToTransfer = amount - _burnAmount;

        uint256 _stakedSupply = stakedSupply; // gas savings

        _stakedSupply = _stakedSupply - amount;
        totalBurnMultiplier = (_stakedSupply * PRECISION_FACTOR) / (totalBurnUntil - block.timestamp);

        stakedSupply = _stakedSupply;

        // clear all
        user.amount = 0;
        user.rewardDebt = 0;
        user.rewardClaim = 0;
        user.burnRound = lastBurnRound();

        // send rewards
        if (totalRewards > 0) {
            safeGoldenPearlTransfer(address(msg.sender), totalRewards);
        }

        // burn amount
        _burnTokens(_burnAmount);

        // send back staked tokens after burn
        stakedToken.safeTransfer(address(msg.sender), amountToTransfer);

        emit EmergencyUnlock(msg.sender, amount, _burnAmount, totalRewards);
    }

    /**
     * Returns time in sec. until next burn is claimable
     */
    function nextClaimableBurn() external view returns (uint256) {
        uint256 _burnPause = burnPause;
        uint256 _lastBurnTime = lastBurnTime;
        uint256 secSinceLastBurn = block.timestamp - _lastBurnTime;
        if (secSinceLastBurn >= _burnPause) {
            return 0;
        }
        return (_lastBurnTime + _burnPause) - block.timestamp;
    }

    /**
     * @notice Returns the reward for the next upcoming burn
     *
     */
    function pendingBurnReward() external view returns (uint256) {
        uint256 secSinceLastBurn = block.timestamp - lastBurnTime;

        // calc burnAmount
        uint256 burnAmount = (secSinceLastBurn * totalBurnMultiplier) / PRECISION_FACTOR;

        return (burnAmount * rewardFee) / 10000;
    }

    /**
     * @notice External function to burn staking token.
     *
     * The function can be called from any after some burn pause (e.g. 5 min).
     * After calling the function the total staked supply gets burned by an amount which is defined as:
     *
     * burnAmount = secSinceLastBurn * totalBurnMultiplier
     *
     * where:
     *   secSinceLastBurn = blockTimestamp - lastBurnTime
     *   totalBurnMultiplier = totalSupply / burnAfterTimeInSec
     *
     * the caller of this function receives a REWARD_FEE percentage of the burnedAmount
     *
     * @dev The function will burn an amount of the stakedSupply and creates a new burnsnapshot
     */
    function burn() external onlyAllowed {
        // check that we are within the allowed burn time
        uint256 secSinceLastBurn = block.timestamp - lastBurnTime;
        require(secSinceLastBurn >= burnPause, "burn: you have to wait the burn pause");

        _updatePool();

        // calc burnAmount
        uint256 burnAmount = (secSinceLastBurn * totalBurnMultiplier) / PRECISION_FACTOR;

        uint256 _stakedSupply = stakedSupply; // gas savings
        uint256 _accTokenPerShare = accTokenPerShare; // gas savings

        if (burnAmount >= _stakedSupply) {
            burnAmount = _stakedSupply;
        }

        uint256 stakedSupplyBeforeBurn = _stakedSupply;
        stakedSupply = _stakedSupply - burnAmount; // set new stakedsupply

        uint256 share = 0;
        if (stakedSupplyBeforeBurn > 0) {
            share = (burnAmount * BURN_AMOUNT_PRECISION_FACTOR) / stakedSupplyBeforeBurn;
        }

        // Store snapshot
        burnSnapshots.push(
            BurnSnapshot({
                timestamp: block.timestamp,
                accRewardPerShare: _accTokenPerShare,
                burnedAmount: burnAmount,
                stakedSupplyBeforeBurn: stakedSupplyBeforeBurn,
                burnPerShare: share
            })
        );

        uint256 callerReward = (burnAmount * rewardFee) / 10000;

        lastBurnTime = block.timestamp;

        // payout the caller
        if (callerReward > 0) {
            stakedToken.safeTransfer(msg.sender, callerReward);
        }

        // send to burn admin
        _burnTokens(burnAmount - callerReward);

        emit LogBurn(
            msg.sender,
            block.timestamp,
            _accTokenPerShare,
            burnAmount,
            stakedSupplyBeforeBurn,
            stakedSupplyBeforeBurn - burnAmount
        );
    }

    function snapshotsLength() external view returns (uint256) {
        return burnSnapshots.length;
    }

    function getSnapshot(uint256 index)
        external
        view
        returns (uint256 timestamp, uint256 accRewardPerShare, uint256 burnAmount, uint256 stakedSupplyBeforeBurn)
    {
        require(index < burnSnapshots.length, "no valid index");
        BurnSnapshot memory snapshot = burnSnapshots[index];
        timestamp = snapshot.timestamp;
        accRewardPerShare = snapshot.accRewardPerShare;
        burnAmount = snapshot.burnedAmount;
        stakedSupplyBeforeBurn = snapshot.stakedSupplyBeforeBurn;
    }

    /**
     * @dev calculates rewards, amount and rewardDebt after the burns in between
     */
    function _computeSnapshotRewards(UserInfo memory user)
        internal
        view
        returns (uint256 rewards, uint256 amount, uint256 rewardDebt)
    {
        uint256 length = burnSnapshots.length;
        uint256 userAmount = user.amount; // gas savings
        uint256 lastUserBurnRound = user.burnRound; // gas savings

        if (userAmount <= 0 || length < 1 || lastUserBurnRound == length) {
            return (rewards = 0, amount = userAmount, rewardDebt = user.rewardDebt);
        }

        uint256 _amount = userAmount;
        uint256 _rewardDebt = user.rewardDebt;
        uint256 _totalPending = 0;

        uint256 index = lastUserBurnRound;

        // loop through all snapshots until we hit the limit (end of snapshots or burnAfterTime)
        while (index < length) {
            BurnSnapshot memory snapshot = burnSnapshots[index];

            if (_amount == 0) {
                break;
            }

            // calc rewards
            uint256 accRewards = _amount * snapshot.accRewardPerShare;

            uint256 pending = (accRewards / PRECISION_FACTOR) - _rewardDebt;

            _totalPending = _totalPending + pending;

            // calc burnAmount
            uint256 burnAmount = (_amount * snapshot.burnPerShare) / BURN_AMOUNT_PRECISION_FACTOR;

            // if (snapshot.timestamp >= untilTime) {
            if (burnAmount >= _amount) {
                burnAmount = _amount;
            }

            // reduce amount
            _amount = _amount - burnAmount;

            // reduce rewardDebt by the burnAmount
            _rewardDebt = (accRewards - (burnAmount * snapshot.accRewardPerShare)) / PRECISION_FACTOR;

            index++;
            // userLastBurn = snapshot.timestamp;
        }

        rewards = _totalPending;
        amount = _amount;
        rewardDebt = _rewardDebt;
    }

    // EXTERNAL VIEW FUNCTIONS

    /**
     * @notice View function to see pending reward on frontend.
     * @param _user: user address
     * @return Pending reward for a given user
     */
    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 stakedTokenSupply = stakedSupply;

        uint256 blockTime = block.timestamp;

        uint256 adjustedTokenPerShare = accTokenPerShare;
        if (blockTime > lastRewardTime && stakedTokenSupply != 0) {
            MonthlyReward memory fromSlice = getMonthlyReward(lastRewardTime);
            MonthlyReward memory toSlice = getMonthlyReward(blockTime);

            uint256 gpReward = _rewardForSlices(blockTime, fromSlice, toSlice);

            adjustedTokenPerShare = accTokenPerShare + ((gpReward * PRECISION_FACTOR) / stakedTokenSupply);
        }
        (uint256 rewards, uint256 amount, uint256 rewardDebt) = _computeSnapshotRewards(user);
        uint256 pending = ((amount * adjustedTokenPerShare) / PRECISION_FACTOR) - rewardDebt;
        return user.rewardClaim + rewards + pending;
    }

    /**
     * @dev get user info
     */
    function getUserInfo(address _user)
        external
        view
        returns (uint256 amount, uint256 rewardDebt, uint256 rewardClaim, uint256 lockedAt, uint256 burnRound)
    {
        UserInfo memory user = userInfo[_user];

        (, amount, rewardDebt) = _computeSnapshotRewards(user);

        rewardClaim = user.rewardClaim;
        burnRound = user.burnRound;
        lockedAt = user.lockedAt;
    }

    /**
     * @dev amount of all users
     */
    function usersLength() external view returns (uint256) {
        return users.length;
    }

    // PUBLIC FUNCTIONS

    /**
     * @dev get the monthly reward for a given blocktime
     */
    function getMonthlyReward(uint256 blockTime) public view returns (MonthlyReward memory) {
        uint256 _length = slices.length;
        for (uint256 i = 0; i < _length; ++i) {
            MonthlyReward memory slice = slices[i];
            if (blockTime >= slice.startTime && blockTime <= slice.endTime) {
                return slice;
            }
        }
        return slices[_length - 1];
    }

    /**
     * @dev time until user funds are unlocked and withdrawable
     */
    function timeToUnlock(address _user) public view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 _time_required = user.lockedAt + time_locked;
        if (_time_required <= block.timestamp) return 0;
        else return _time_required - block.timestamp;
    }

    // INTERNAL / PRIVATE FUNCIONS

    // updates pool
    function _updatePool() internal {
        uint256 blockTime = block.timestamp;
        uint256 _lastRewardTime = lastRewardTime;
        if (blockTime <= _lastRewardTime) {
            return;
        }

        uint256 stakedTokenSupply = stakedSupply; // gas savings

        if (stakedTokenSupply == 0) {
            lastRewardTime = blockTime;
            lastBurnTime = blockTime;
            return;
        }

        MonthlyReward memory fromSlice = getMonthlyReward(_lastRewardTime);
        MonthlyReward memory toSlice = getMonthlyReward(blockTime);

        uint256 gpReward = _rewardForSlices(blockTime, fromSlice, toSlice);

        // MLUM is not minted for the ShimmerSeaBooster, its a temporary Booster solution

        accTokenPerShare = accTokenPerShare + ((gpReward * PRECISION_FACTOR) / stakedTokenSupply);

        lastRewardTime = blockTime;
    }

    // Safe GoldenPearl transfer function, just in case if rounding error causes pool to not have enough GoldenPearls.
    function safeGoldenPearlTransfer(address _to, uint256 _amount) internal {
        uint256 gpBal = rewardToken.balanceOf(address(this));
        if (_amount > gpBal) {
            rewardToken.safeTransfer(_to, gpBal);
        } else {
            rewardToken.safeTransfer(_to, _amount);
        }
    }

    /**
     * @dev get reward for slices
     */
    function _rewardForSlices(uint256 blockTime, MonthlyReward memory fromSlice, MonthlyReward memory toSlice)
        internal
        view
        returns (uint256 reward)
    {
        if (blockTime < startTime) {
            return 0;
        }

        uint256 _lastRewardTime = lastRewardTime; // gas savings
        if (_lastRewardTime >= bonusEndTime) {
            return 0;
        }

        if (blockTime >= bonusEndTime) {
            blockTime = bonusEndTime;
        }

        if (fromSlice.index == toSlice.index) {
            return (blockTime - _lastRewardTime) * toSlice.rewardPerSec;
        }

        uint256 rewardsInBetween = 0;
        if (fromSlice.index < toSlice.index) {
            // first: rewards for the remaining blocks of the fromSlice
            uint256 firstBlocks = fromSlice.endTime - _lastRewardTime;
            uint256 firstBlockReward = firstBlocks * fromSlice.rewardPerSec;

            // second: rewards for all the blocks between
            if (toSlice.index - fromSlice.index > 1) {
                //sum up all rewards
                for (uint256 i = (fromSlice.index + 1); i < toSlice.index; i++) {
                    MonthlyReward memory currentSlice = slices[i];
                    rewardsInBetween += ((currentSlice.endTime - currentSlice.startTime) * currentSlice.rewardPerSec);
                }
            }

            //third: rewards for the block of the toSlice
            uint256 lastBlocks = blockTime - toSlice.startTime;
            uint256 lastBlockReward = lastBlocks * toSlice.rewardPerSec;

            return firstBlockReward + rewardsInBetween + lastBlockReward;
        }
    }

    /**
     * @dev transfer tokens to BURN_ADMIN address
     */
    function _burnTokens(uint256 amount) private {
        if (amount > 0) {
            totalBurned = totalBurned + amount;

            stakedToken.safeTransfer(BURN_ADMIN, amount);

            emit BurnStakedToken(amount);
        }
    }

    // create timebased reward slices
    function _createMonthlyRewardSlices(uint256[] memory monthlyRewardsInWei) private {
        require(monthlyRewardsInWei.length > 0, "zero length");
        uint256 currentTime = startTime;
        for (uint256 i = 0; i < monthlyRewardsInWei.length; i++) {
            slices.push(
                MonthlyReward({
                    index: i,
                    startTime: currentTime,
                    endTime: currentTime + SEC_PER_MONTH,
                    rewardPerSec: monthlyRewardsInWei[i]
                })
            );
            currentTime = currentTime + SEC_PER_MONTH + 1;
        }
    }
}
