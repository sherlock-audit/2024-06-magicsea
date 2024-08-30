// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/console.sol";

import "openzeppelin-contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";

import {Ownable2StepUpgradeable} from "openzeppelin-contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ERC721EnumerableUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ReentrancyGuard} from "openzeppelin/utils/ReentrancyGuard.sol";
import {EnumerableSet} from "openzeppelin/utils/structs/EnumerableSet.sol";
import {SafeERC20, IERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

import {IMlumStaking} from "./interfaces/IMlumStaking.sol";

/**
 * @title MagicLum Staking
 * @author BlueLabs / MagicSea
 * @notice This pool allows users to stake token (MLUM) and earn rewards (e.g USDC). Rewards get distributed on a daily/weekly basis.
 * Users can get higher rewards on higher lock durations.
 *
 * For this, this contract wraps ERC20 assets into non-fungible staking positions called lsNFT
 * lsNFT add the possibility to create an additional layer on liquidity providing lock features
 *
 * Every time `updatePool()` is called, we distribute the balance of that tokens as rewards to users that are
 * currently staking inside this contract, and they can claim it using `harvest`
 */
contract MlumStaking is
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable,
    IMlumStaking,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    // keeps tracks of the latest tokenId
    uint256 private _tokenIdCounter;

    // The precision factor
    uint256 public immutable PRECISION_FACTOR;

    // last balance of reward token
    uint256 private _lastRewardBalance;

    // The reward token
    IERC20 private immutable _rewardToken;

    // The staked token
    IERC20 private immutable _stakedToken;

    // keeps track about the total supply of staked tokens
    uint256 public _stakedSupply; // Sum of deposit tokens on this pool
    uint256 public _stakedSupplyWithMultiplier; // Sum of deposit token on this pool including the user's total multiplier (lockMultiplier + boostPoints)
    uint256 public _accRewardsPerShare; // Accumulated Rewards (staked token) per share, times PRECISION_FACTOR. See below

    // multiplier settings for lock times
    uint256 public constant MAX_LOCK_MULTIPLIER_LIMIT = 20000; // 20000 (200%), high limit for maxLockMultiplier (100 = 1%)

    uint256 private _maxGlobalMultiplier; // eg. 20000 (200%)
    uint256 private _maxLockDuration; // e.g. 365 days, Capped lock duration to have the maximum bonus lockMultiplier
    uint256 private _maxLockMultiplier; // eg. 20000 (200%), Max available lockMultiplier (100 = 1%)

    uint256 private _minimumLockDuration; // Minimum lock duration for creating a position

    bool public _emergencyUnlock; // Release all locks in case of emergency

    // readable via getStakingPosition
    mapping(uint256 => StakingPosition) internal _stakingPositions; // Info of each NFT position that stakes LP tokens

    uint256[10] __gap;

    constructor(IERC20 stakedToken, IERC20 rewardToken) {
        _disableInitializers();

        if (address(stakedToken) == address(0)) revert IMlumStaking_ZeroAddress();
        if (address(rewardToken) == address(0)) revert IMlumStaking_ZeroAddress();
        if (address(stakedToken) == address(rewardToken)) revert IMlumStaking_SameAddress();

        _stakedToken = stakedToken;
        _rewardToken = rewardToken;

        uint256 decimalsRewardToken = uint256(IERC20Metadata(address(_rewardToken)).decimals());
        if (decimalsRewardToken > 30) revert IMlumStaking_TooMuchTokenDecimals();

        PRECISION_FACTOR = uint256(10 ** (uint256(30) - decimalsRewardToken));

        _stakedSupply = 0;
    }

    /**
     * @dev Initializes the contract.
     * @param initialOwner The initial owner of the contract.
     */
    function initialize(address initialOwner) external reinitializer(3) {
        __Ownable_init(initialOwner);
        __ERC721_init("Lock staking position NFT", "lsNFT");

        _maxGlobalMultiplier = 20000;
        _maxLockDuration = 365 days;
        _maxLockMultiplier = 20000;
        _minimumLockDuration = 7 days;
    }

    // public views

    /**
     * @dev Returns true if "tokenId" is an existing spNFT id
     * @param tokenId The id of the lsNFT
     */
    function exists(uint256 tokenId) external view override returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    /**
     * @dev Returns the staked token
     */
    function getStakedToken() external view override returns (IERC20) {
        return _stakedToken;
    }

    /**
     * @dev Returns the reward token
     */
    function getRewardToken() external view override returns (IERC20) {
        return _rewardToken;
    }

    /**
     * @dev Returns the last reward balance
     */
    function getLastRewardBalance() external view override returns (uint256) {
        return _lastRewardBalance;
    }

    /**
     * @dev Returns last minted NFT id
     */
    function lastTokenId() external view override returns (uint256) {
        return _tokenIdCounter;
    }

    /**
     * @dev Returns the total supply of staked tokens
     */
    function getStakedSupply() external view override returns (uint256) {
        return _stakedSupply;
    }

    /**
     * @dev Returns the total supply of staked tokens with multiplier
     */
    function getStakedSupplyWithMultiplier() external view override returns (uint256) {
        return _stakedSupplyWithMultiplier;
    }

    /**
     * @dev Returns true if emergency unlocks are activated on this pool or on the master
     */
    function isUnlocked() public view returns (bool) {
        return _emergencyUnlock;
    }

    /**
     * @dev Returns true if this pool currently has deposits
     */
    function hasDeposits() external view override returns (bool) {
        return _stakedSupplyWithMultiplier > 0;
    }

    /**
     * @dev Returns expected multiplier for a "lockDuration" duration lock (result is *1e4)
     *
     * @param lockDuration The lock duration
     */
    function getMultiplierByLockDuration(uint256 lockDuration) public view returns (uint256) {
        // in case of emergency unlock
        if (isUnlocked()) return 0;

        if (_maxLockDuration == 0 || lockDuration == 0) return 0;

        // capped to maxLockDuration
        if (lockDuration >= _maxLockDuration) return _maxLockMultiplier * 1e18;

        return (_maxLockMultiplier * lockDuration * 1e18) / (_maxLockDuration);
    }

    /**
     * @dev Returns a position info
     */
    function getStakingPosition(uint256 tokenId) external view override returns (StakingPosition memory position) {
        position = _stakingPositions[tokenId];
    }

    /**
     * @dev Returns pending rewards for a position
     */
    function pendingRewards(uint256 tokenId) external view override returns (uint256) {
        StakingPosition storage position = _stakingPositions[tokenId];

        uint256 accRewardsPerShare = _accRewardsPerShare;
        uint256 stakedTokenSupply = _stakedSupply;

        uint256 rewardBalance = _rewardToken.balanceOf(address(this));

        uint256 lastRewardBalance = _lastRewardBalance;

        // recompute accRewardsPerShare if not up to date
        if (lastRewardBalance != rewardBalance && stakedTokenSupply > 0) {
            uint256 accruedReward = rewardBalance - lastRewardBalance;

            accRewardsPerShare = accRewardsPerShare + ((accruedReward * PRECISION_FACTOR) / _stakedSupplyWithMultiplier);
        }

        return position.amountWithMultiplier * accRewardsPerShare / PRECISION_FACTOR - position.rewardDebt;
    }

    // admin functions

    /**
     * Return mutliplier settings
     * @return maxGlobalMultiplier
     * @return maxLockDuration
     * @return maxLockMultiplier
     */
    function getMultiplierSettings() external view returns (uint256, uint256, uint256) {
        return (_maxGlobalMultiplier, _maxLockDuration, _maxLockMultiplier);
    }

    /**
     * Return minimum lock duration
     */
    function getMinimumLockDuration() external view returns (uint256) {
        return _minimumLockDuration;
    }

    /**
     * @dev Set lock multiplier settings
     *
     * maxLockMultiplier must be <= MAX_LOCK_MULTIPLIER_LIMIT
     * maxLockMultiplier must be <= _maxGlobalMultiplier
     *
     * Must only be called by the owner
     *
     * @param maxLockDuration The new max lock duration
     * @param maxLockMultiplier The new max lock multiplier
     */
    function setLockMultiplierSettings(uint256 maxLockDuration, uint256 maxLockMultiplier) external onlyOwner {
        if (maxLockMultiplier > _maxGlobalMultiplier) revert IMlumStaking_MaxLockMultiplierTooHigh();
        if (maxLockMultiplier > MAX_LOCK_MULTIPLIER_LIMIT) revert IMlumStaking_MaxLockMultiplierTooHigh();

        _maxLockDuration = maxLockDuration;
        _maxLockMultiplier = maxLockMultiplier;

        emit SetLockMultiplierSettings(maxLockDuration, maxLockMultiplier);
    }

    function setMinimumLockDuration(uint256 minimumLockDuration) external onlyOwner {
        _minimumLockDuration = minimumLockDuration;

        emit SetMinimumLockDuration(minimumLockDuration);
    }

    /**
     * @dev Set emergency unlock status
     *
     * Must only be called by the owner
     */
    function setEmergencyUnlock(bool emergencyUnlock_) external onlyOwner {
        _emergencyUnlock = emergencyUnlock_;
        emit SetEmergencyUnlock(emergencyUnlock_);
    }

    /**
     * @dev Updates rewards states of the given pool to be up-to-date
     */
    function updatePool() external nonReentrant {
        _updatePool();
    }

    /**
     * @dev Create a staking position (lsNFT) with an optional lockDuration
     */
    function createPosition(uint256 amount, uint256 lockDuration) external override nonReentrant {
        // no new lock can be set if the pool has been unlocked
        if (isUnlocked()) {
            if (lockDuration > 0) revert IMlumStaking_LocksDisabled();
        }

        // check for the minimum lock duration
        if (lockDuration < _minimumLockDuration) revert IMlumStaking_InvalidLockDuration();

        _updatePool();

        // handle tokens with transfer tax
        amount = _transferSupportingFeeOnTransfer(_stakedToken, msg.sender, amount);

        // createPosition: amount cannot be null
        if (amount == 0) revert IMlumStaking_ZeroAmount();

        // mint NFT position token
        uint256 currentTokenId = _mintNextTokenId(msg.sender);

        // calculate bonuses
        uint256 lockMultiplier = getMultiplierByLockDuration(lockDuration);
        uint256 amountWithMultiplier = amount + (amount * lockMultiplier / 1e4) / 1e18;

        // create position
        _stakingPositions[currentTokenId] = StakingPosition({
            initialLockDuration: lockDuration,
            amount: amount,
            rewardDebt: amountWithMultiplier * (_accRewardsPerShare) / (PRECISION_FACTOR),
            lockDuration: lockDuration,
            startLockTime: block.timestamp,
            lockMultiplier: lockMultiplier,
            amountWithMultiplier: amountWithMultiplier,
            totalMultiplier: lockMultiplier
        });

        // update total lp supply
        _stakedSupply = _stakedSupply + amount;
        _stakedSupplyWithMultiplier = _stakedSupplyWithMultiplier + amountWithMultiplier;

        emit CreatePosition(currentTokenId, amount, lockDuration);
    }

    /**
     * @dev Add to an existing staking position
     *
     * Can only be called by lsNFT's owner or operators
     */
    function addToPosition(uint256 tokenId, uint256 amountToAdd) external override nonReentrant {
        // on emergency unlock we dont allow staking
        if (isUnlocked()) {
            revert IMlumStaking_LocksDisabled();
        }

        _checkOwnerOf(tokenId);

        // addToPosition: amount cannot be null
        if (amountToAdd == 0) revert IMlumStaking_ZeroAmount();

        _updatePool();
        address nftOwner = ERC721Upgradeable.ownerOf(tokenId);
        _harvestPosition(tokenId, nftOwner);

        StakingPosition storage position = _stakingPositions[tokenId];

        // we calculate the avg lock time:
        // lock_duration = (remainin_lock_time * staked_amount + amount_to_add * inital_lock_duration) / (staked_amount + amount_to_add)
        uint256 remainingLockTime = _remainingLockTime(position);
        uint256 avgDuration = (remainingLockTime * position.amount + amountToAdd * position.initialLockDuration)
            / (position.amount + amountToAdd);

        position.startLockTime = block.timestamp;
        position.lockDuration = avgDuration;

        // lock multiplier stays the same
        position.lockMultiplier = getMultiplierByLockDuration(position.initialLockDuration);

        // handle tokens with transfer tax
        amountToAdd = _transferSupportingFeeOnTransfer(_stakedToken, msg.sender, amountToAdd);

        // update position
        position.amount = position.amount + amountToAdd;
        _stakedSupply = _stakedSupply + amountToAdd;
        _updateBoostMultiplierInfoAndRewardDebt(position);

        emit AddToPosition(tokenId, msg.sender, amountToAdd);
    }

    function _remainingLockTime(StakingPosition memory position) internal view returns (uint256) {
        uint256 blockTimestamp = block.timestamp;
        if ((position.startLockTime + position.lockDuration) <= blockTimestamp) {
            return 0;
        }
        return (position.startLockTime + position.lockDuration) - blockTimestamp;
    }

    /**
     * @dev Harvest from a staking position
     *
     * Can only be called by lsNFT's owner
     * @param tokenId The id of the lsNFT
     */
    function harvestPosition(uint256 tokenId) external override nonReentrant {
        _checkOwnerOf(tokenId);

        _updatePool();
        _harvestPosition(tokenId, ERC721Upgradeable.ownerOf(tokenId));
        _updateBoostMultiplierInfoAndRewardDebt(_stakingPositions[tokenId]);
    }

    /**
     * @dev Harvest from multiple staking positions to the owner
     *
     * Can only be called by lsNFT's owner
     *
     * @param tokenIds The ids of the lsNFTs
     */
    function harvestPositions(uint256[] calldata tokenIds) external override nonReentrant {
        _updatePool();

        uint256 length = tokenIds.length;
        for (uint256 i = 0; i < length; ++i) {
            uint256 tokenId = tokenIds[i];
            // we check for ownership then harvest
            _checkOwnerOf(tokenId);
            _harvestPosition(tokenId, ERC721Upgradeable.ownerOf(tokenId));
            _updateBoostMultiplierInfoAndRewardDebt(_stakingPositions[tokenId]);
        }
    }

    /**
     * @dev Withdraw from a staking position
     *
     * Can only be called by lsNFT's owner
     * @param tokenId The id of the lsNFT
     * @param amountToWithdraw The amount to withdraw
     */
    function withdrawFromPosition(uint256 tokenId, uint256 amountToWithdraw) external nonReentrant {
        _checkOwnerOf(tokenId);

        _updatePool();
        address nftOwner = ERC721Upgradeable.ownerOf(tokenId);
        _withdrawFromPosition(nftOwner, tokenId, amountToWithdraw);
    }

    /**
     * @dev Renew lock with the inital lock duration of a staking position
     *
     * Can only be called by lsNFT's owner
     *
     * @param tokenId The id of the lsNFT
     */
    function renewLockPosition(uint256 tokenId) external nonReentrant {
        _checkOwnerOf(tokenId);

        _updatePool();
        _lockPosition(tokenId, _stakingPositions[tokenId].initialLockDuration, true);
    }

    /**
     * @dev Extends a lock position, lockDuration is the new lock duration
     * Lock duration must be greater than existing lock duration
     * Can only be called by lsNFT's owner
     *
     * @param tokenId The id of the lsNFT
     * @param lockDuration The new lock duration
     */
    function extendLockPosition(uint256 tokenId, uint256 lockDuration) external nonReentrant {
        _checkOwnerOf(tokenId);

        _updatePool();
        _lockPosition(tokenId, lockDuration, true);
    }

    /**
     * Withdraw without caring about rewards, EMERGENCY ONLY
     *
     * Can only be called by lsNFT's owner
     *
     * @param tokenId The id of the lsNFT
     */
    function emergencyWithdraw(uint256 tokenId) external override nonReentrant {
        _checkOwnerOf(tokenId);

        StakingPosition storage position = _stakingPositions[tokenId];

        // position should be unlocked
        // emergencyWithdraw: locked
        if ((position.startLockTime + position.lockDuration) > block.timestamp && !isUnlocked()) {
            revert IMlumStaking_PositionStillLocked();
        }

        // redistribute the rewards to the pool
        {
            _updatePool();

            uint256 pending = position.amountWithMultiplier * _accRewardsPerShare / PRECISION_FACTOR - position.rewardDebt;

            _lastRewardBalance = _lastRewardBalance - pending;
        }

        uint256 amount = position.amount;

        // update total lp supply
        _stakedSupply = _stakedSupply - amount;
        _stakedSupplyWithMultiplier = _stakedSupplyWithMultiplier - position.amountWithMultiplier;

        // destroy position (ignore boost points)
        _destroyPosition(tokenId);

        emit EmergencyWithdraw(tokenId, amount);
        _stakedToken.safeTransfer(msg.sender, amount);
    }

    // internal functions

    /**
     * @dev Updates rewards states of this pool to be up-to-date
     */
    function _updatePool() internal {
        uint256 accRewardsPerShare = _accRewardsPerShare;
        uint256 rewardBalance = _rewardToken.balanceOf(address(this));
        uint256 lastRewardBalance = _lastRewardBalance;

        // recompute accRewardsPerShare if not up to date
        if (lastRewardBalance == rewardBalance || _stakedSupply == 0) {
            return;
        }

        uint256 accruedReward = rewardBalance - lastRewardBalance;
        uint256 calcAccRewardsPerShare =
            accRewardsPerShare + ((accruedReward * (PRECISION_FACTOR)) / (_stakedSupplyWithMultiplier));

        _accRewardsPerShare = calcAccRewardsPerShare;
        _lastRewardBalance = rewardBalance;

        emit PoolUpdated(block.timestamp, calcAccRewardsPerShare);
    }

    /**
     * @dev Destroys lsNFT
     * @param tokenId The id of the lsNFT
     */
    function _destroyPosition(uint256 tokenId) internal {
        // burn lsNFT
        delete _stakingPositions[tokenId];
        ERC721Upgradeable._burn(tokenId);
    }

    /**
     * @dev Computes new tokenId and mint associated lsNFT to "to" address
     * @param to The address to mint the lsNFT to
     */
    function _mintNextTokenId(address to) internal returns (uint256 tokenId) {
        _tokenIdCounter += 1;
        tokenId = _tokenIdCounter;
        _safeMint(to, tokenId);
    }

    /**
     * @dev Withdraw from a staking position and destroy it
     *
     * _updatePool() should be executed before calling this
     *
     * @param nftOwner The owner of the lsNFT
     * @param tokenId The id of the lsNFT
     * @param amountToWithdraw The amount to withdraw
     */
    function _withdrawFromPosition(address nftOwner, uint256 tokenId, uint256 amountToWithdraw) internal {
        // withdrawFromPosition: amount cannot be null
        if (amountToWithdraw == 0) revert IMlumStaking_ZeroAmount();

        StakingPosition storage position = _stakingPositions[tokenId];

        if ((position.startLockTime + position.lockDuration) > block.timestamp && !isUnlocked()) {
            revert IMlumStaking_PositionStillLocked();
        }

        if (position.amount < amountToWithdraw) revert IMlumStaking_AmountTooHigh();

        _harvestPosition(tokenId, nftOwner);

        // update position
        position.amount = position.amount - amountToWithdraw;

        // update total lp supply
        _stakedSupply = _stakedSupply - amountToWithdraw;

        if (position.amount == 0) {
            // destroy if now empty
            _stakedSupplyWithMultiplier = _stakedSupplyWithMultiplier - position.amountWithMultiplier;
            _destroyPosition(tokenId);
        } else {
            _updateBoostMultiplierInfoAndRewardDebt(position);
        }

        emit WithdrawFromPosition(tokenId, amountToWithdraw);
        _stakedToken.safeTransfer(nftOwner, amountToWithdraw);
    }

    /**
     * @dev updates position's boost multiplier, totalMultiplier, amountWithMultiplier (stakedSupplyWithMultiplier)
     * and rewardDebt without updating lockMultiplier
     *
     * @param position The staking position to update
     */
    function _updateBoostMultiplierInfoAndRewardDebt(StakingPosition storage position) internal {
        // keep the original lock multiplier and recompute current boostPoints multiplier
        uint256 newTotalMultiplier = position.lockMultiplier;
        if (newTotalMultiplier > _maxGlobalMultiplier * 1e18) newTotalMultiplier = _maxGlobalMultiplier * 1e18;

        position.totalMultiplier = newTotalMultiplier;
        uint256 amountWithMultiplier = position.amount + (position.amount * newTotalMultiplier / 1e4) / 1e18;
        // update global supply
        _stakedSupplyWithMultiplier = _stakedSupplyWithMultiplier - position.amountWithMultiplier + amountWithMultiplier;
        position.amountWithMultiplier = amountWithMultiplier;

        position.rewardDebt = amountWithMultiplier * _accRewardsPerShare / PRECISION_FACTOR;
    }

    /**
     * @dev Harvest rewards from a position
     * Will also update the position's totalMultiplier
     */
    function _harvestPosition(uint256 tokenId, address to) internal {
        require(to != address(this), "MlumStaking: cannot harvest to this contract");

        StakingPosition storage position = _stakingPositions[tokenId];

        // compute position's pending rewards
        uint256 pending = position.amountWithMultiplier * _accRewardsPerShare / PRECISION_FACTOR - position.rewardDebt;

        // transfer rewards
        if (pending > 0) {
            // send rewards
            _safeRewardTransfer(to, pending);
        }
        emit HarvestPosition(tokenId, to, pending);
    }

    /**
     * @dev Renew lock from a staking position with "lockDuration"
     *
     * @param tokenId The id of the lsNFT
     * @param lockDuration The new lock duration
     * @param resetInitial If true, reset the initial lock duration
     */
    function _lockPosition(uint256 tokenId, uint256 lockDuration, bool resetInitial) internal {
        if (isUnlocked()) revert IMlumStaking_LocksDisabled();

        StakingPosition storage position = _stakingPositions[tokenId];

        // for renew only, check if new lockDuration is at least = to the remaining active duration
        uint256 endTime = position.startLockTime + position.lockDuration;
        uint256 currentBlockTimestamp = block.timestamp;
        if (endTime > currentBlockTimestamp) {
            if (lockDuration == 0) revert IMlumStaking_InvalidLockDuration();
            if (lockDuration < (endTime - currentBlockTimestamp)) revert IMlumStaking_InvalidLockDuration();
        }

        // for extend lock postion we reset the initial lock duration
        // we have to check that the lock duration is greater then the current
        if (resetInitial) {
            if (lockDuration <= position.initialLockDuration) revert IMlumStaking_InvalidLockDuration();
            position.initialLockDuration = lockDuration;
        }

        // harvest to nft owner before updating position
        _harvestPosition(tokenId, ERC721Upgradeable.ownerOf(tokenId));

        // update position and total lp supply
        position.lockDuration = lockDuration;
        position.lockMultiplier = getMultiplierByLockDuration(lockDuration);
        position.startLockTime = currentBlockTimestamp;
        _updateBoostMultiplierInfoAndRewardDebt(position);

        emit LockPosition(tokenId, lockDuration);
    }

    /**
     * @dev Handle deposits of tokens with transfer tax
     *
     * @param token The token to transfer
     * @param user The user that will transfer the tokens
     * @param amount The amount to transfer
     */
    function _transferSupportingFeeOnTransfer(IERC20 token, address user, uint256 amount)
        internal
        returns (uint256 receivedAmount)
    {
        uint256 previousBalance = token.balanceOf(address(this));
        token.safeTransferFrom(user, address(this), amount);
        return token.balanceOf(address(this)) - previousBalance;
    }

    /**
     * @notice Safe token transfer function, just in case if rounding error
     * causes pool to not have enough reward tokens
     * @param _to The address that will receive `_amount` `rewardToken`
     * @param _amount The amount to send to `_to`
     */
    function _safeRewardTransfer(address _to, uint256 _amount) internal {
        uint256 rewardBalance = _rewardToken.balanceOf(address(this));

        if (_amount > rewardBalance) {
            _lastRewardBalance = _lastRewardBalance - rewardBalance;
            _rewardToken.safeTransfer(_to, rewardBalance);
        } else {
            _lastRewardBalance = _lastRewardBalance - _amount;
            _rewardToken.safeTransfer(_to, _amount);
        }
    }

    /**
     * @dev Forbid transfer of lsNFT other from/to zero address (minting/burning)
     */
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
        returns (address)
    {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) {
            revert IMlumStaking_TransferNotAllowed();
        }

        return super._update(to, tokenId, auth);
    }

    /**
     * @dev Require that the caller is the owner of the lsNFT
     * @param tokenId The id of the lsNFT
     */
    function _checkOwnerOf(uint256 tokenId) internal view {
        // check if sender is owner of tokenId
        if (ERC721Upgradeable.ownerOf(tokenId) != msg.sender) revert IMlumStaking_NotOwner();
    }

    // overrrides for solidity

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(IERC165, ERC721Upgradeable, ERC721EnumerableUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
    {
        super._increaseBalance(account, value);
    }

}
