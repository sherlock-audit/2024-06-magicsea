// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/console.sol";

import "openzeppelin-contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";

import {Ownable2StepUpgradeable} from "openzeppelin-contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ERC721EnumerableUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

import {ReentrancyGuard} from "openzeppelin/utils/ReentrancyGuard.sol";
import {EnumerableSet} from "openzeppelin/utils/structs/EnumerableSet.sol";
import {SafeERC20, IERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

import {IMlumStaking} from "./interfaces/IMlumStaking.sol";

/**
 * @title MagicLum Staking
 * @author BlueLabs / MagicSea
 * @notice This pool allows users to stake a token and earn rewards. Rewards get distributed on a daily/weekly basis.
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
    ReentrancyGuard,
    IMlumStaking,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    // keeps tracks of the latest tokenId
    uint256 public _tokenIdCounter;

    EnumerableSet.AddressSet private _unlockOperators; // Addresses allowed to forcibly unlock locked spNFTs
    address public _operator; // Used to delegate multiplier settings to project's owners

    // The precision factor
    uint256 public immutable PRECISION_FACTOR;

    // The time of the last pool update
    uint256 public _lastRewardTime;

    // last balance of reward token
    uint256 public _lastRewardBalance;

    // The reward token
    IERC20 public immutable rewardToken;

    // The staked token
    IERC20 public immutable stakedToken;

    // keeps track about the total supply of staked tokens
    uint256 public _stakedSupply; // Sum of deposit tokens on this pool
    uint256 public _stakedSupplyWithMultiplier; // Sum of deposit token on this pool including the user's total multiplier (lockMultiplier + boostPoints)
    uint256 public _accRewardsPerShare; // Accumulated Rewards (staked token) per share, times PRECISION_FACTOR. See below

    // readable via getMultiplierSettings
    uint256 public constant MAX_GLOBAL_MULTIPLIER_LIMIT = 25000; // 250%, high limit for maxGlobalMultiplier (100 = 1%)
    uint256 public constant MAX_LOCK_MULTIPLIER_LIMIT = 15000; // 150%, high limit for maxLockMultiplier (100 = 1%)
    uint256 private _maxGlobalMultiplier = 20000; // 200%

    uint256 private _maxLockDuration = 365 days; // 365 days, Capped lock duration to have the maximum bonus lockMultiplier
    uint256 private _maxLockMultiplier = 20000; // 200%, Max available lockMultiplier (100 = 1%)

    bool public _emergencyUnlock; // Release all locks in case of emergency

    // readable via getStakingPosition
    mapping(uint256 => StakingPosition) internal _stakingPositions; // Info of each NFT position that stakes LP tokens

    uint256[10] __gap;

    constructor(IERC20 _stakedToken, IERC20 _rewardToken) {
        _disableInitializers();
        
        require(address(_stakedToken) != address(0), "init: zero address");
        require(address(_rewardToken) != address(0), "init: zero address");

        stakedToken = _stakedToken;
        rewardToken = _rewardToken;

        uint256 decimalsRewardToken = uint256(IERC20Metadata(address(_rewardToken)).decimals());
        require(decimalsRewardToken < 30, "Must be inferior to 30");

        PRECISION_FACTOR = uint256(10 ** (uint256(30) - decimalsRewardToken));

        _stakedSupply = 0;
    }

    /**
     * @dev Initializes the contract.
     * @param initialOwner The initial owner of the contract.
     */
    function initialize(address initialOwner) external reinitializer(2) {
        __Ownable_init(initialOwner);
        __ERC721_init("Lock staking position NFT", "lsNFT");

        _maxGlobalMultiplier = 20000;
        _maxLockDuration = 365 days;
        _maxLockMultiplier = 20000;
    }

    // Events

    event AddToPosition(uint256 indexed tokenId, address user, uint256 amount);
    event CreatePosition(uint256 indexed tokenId, uint256 amount, uint256 lockDuration);
    event WithdrawFromPosition(uint256 indexed tokenId, uint256 amount);
    event EmergencyWithdraw(uint256 indexed tokenId, uint256 amount);
    event LockPosition(uint256 indexed tokenId, uint256 lockDuration);
    event HarvestPosition(uint256 indexed tokenId, address to, uint256 pending);
    event PoolUpdated(uint256 lastRewardTime, uint256 accRewardsPerShare);
    event SetLockMultiplierSettings(uint256 maxLockDuration, uint256 maxLockMultiplier);
    event SetBoostMultiplierSettings(uint256 maxGlobalMultiplier, uint256 maxBoostMultiplier);
    event SetUnlockOperator(address operator, bool isAdded);
    event SetEmergencyUnlock(bool emergencyUnlock);
    event SetOperator(address operator);

    // Modifiers

    /**
     * @dev Check if caller has operator rights
     */
    function _requireOnlyOwner() internal view {
        require(msg.sender == owner(), "FORBIDDEN");
        // onlyOwner: caller is not the owner
    }

    /**
     * @dev Check if a userAddress has privileged rights on a spNFT
     */
    function _requireOnlyOperatorOrOwnerOf(uint256 tokenId) internal view {
        // isApprovedOrOwner: caller has no rights on token
        require(ERC721Upgradeable._isAuthorized(msg.sender, msg.sender, tokenId), "FORBIDDEN");
    }

    /**
     * @dev Check if a userAddress has privileged rights on a spNFT
     */
    function _requireOnlyApprovedOrOwnerOf(uint256 tokenId) internal view {
        require(_ownerOf(tokenId) != address(0), "ERC721: operator query for nonexistent token");
        require(_isOwnerOf(msg.sender, tokenId) || getApproved(tokenId) == msg.sender, "FORBIDDEN");
    }

    /**
     * @dev Check if a msg.sender is owner of a spNFT
     */
    function _requireOnlyOwnerOf(uint256 tokenId) internal view {
        require(_ownerOf(tokenId) != address(0), "ERC721: operator query for nonexistent token");
        // onlyOwnerOf: caller has no rights on token
        require(_isOwnerOf(msg.sender, tokenId), "not owner");
    }

    // public views

    /**
     * @dev Returns the number of unlockOperators
     */
    function unlockOperatorsLength() external view returns (uint256) {
        return _unlockOperators.length();
    }

    /**
     * @dev Returns an unlockOperator from its "index"
     */
    function unlockOperator(uint256 index) external view returns (address) {
        if (_unlockOperators.length() <= index) return address(0);
        return _unlockOperators.at(index);
    }

    /**
     * @dev Returns true if "operator" address is an unlockOperator
     */
    function isUnlockOperator(address operator) external view returns (bool) {
        return _unlockOperators.contains(operator);
    }

    /**
     * @dev Returns true if "tokenId" is an existing spNFT id
     */
    function exists(uint256 tokenId) external view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    /**
     * @dev Returns last minted NFT id
     */
    function lastTokenId() external view returns (uint256) {
        return _tokenIdCounter;
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
     */
    function getMultiplierByLockDuration(uint256 lockDuration) public view returns (uint256) {
        // in case of emergency unlock
        if (isUnlocked()) return 0;

        if (_maxLockDuration == 0 || lockDuration == 0) return 0;

        // capped to maxLockDuration
        if (lockDuration >= _maxLockDuration) return _maxLockMultiplier;

        return (_maxLockMultiplier * lockDuration) / (_maxLockDuration);
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

        uint256 rewardBalance = rewardToken.balanceOf(address(this));

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
     * @dev Set lock multiplier settings
     *
     * maxLockMultiplier must be <= MAX_LOCK_MULTIPLIER_LIMIT
     * maxLockMultiplier must be <= _maxGlobalMultiplier - _maxBoostMultiplier
     *
     * Must only be called by the owner
     */
    function setLockMultiplierSettings(uint256 maxLockDuration, uint256 maxLockMultiplier) external {
        require(msg.sender == owner() || msg.sender == _operator, "FORBIDDEN");
        // onlyOperatorOrOwner: caller has no operator rights
        require(maxLockMultiplier <= MAX_LOCK_MULTIPLIER_LIMIT, "too high");
        // setLockSettings: maxGlobalMultiplier is too high
        _maxLockDuration = maxLockDuration;
        _maxLockMultiplier = maxLockMultiplier;

        emit SetLockMultiplierSettings(maxLockDuration, maxLockMultiplier);
    }

    /**
     * @dev Add or remove unlock operators
     *
     * Must only be called by the owner
     */
    function setUnlockOperator(address operator, bool add) external {
        _requireOnlyOwner();

        if (add) {
            _unlockOperators.add(operator);
        } else {
            _unlockOperators.remove(operator);
        }
        emit SetUnlockOperator(operator, add);
    }

    /**
     * @dev Set emergency unlock status
     *
     * Must only be called by the owner
     */
    function setEmergencyUnlock(bool emergencyUnlock_) external {
        _requireOnlyOwner();

        _emergencyUnlock = emergencyUnlock_;
        emit SetEmergencyUnlock(emergencyUnlock_);
    }

    /**
     * @dev Set operator (usually deposit token's project's owner) to adjust contract's settings
     *
     * Must only be called by the owner
     */
    function setOperator(address operator_) external {
        _requireOnlyOwner();

        _operator = operator_;
        emit SetOperator(operator_);
    }

    // Public functions

    /**
     * @dev Add nonReentrant to ERC721.transferFrom
     */
    function transferFrom(address from, address to, uint256 tokenId)
        public
        override(ERC721Upgradeable, IERC721)
        nonReentrant
    {
        ERC721Upgradeable.transferFrom(from, to, tokenId);
    }

    /**
     * @dev Add nonReentrant to ERC721.safeTransferFrom
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data)
        public
        override(ERC721Upgradeable, IERC721)
        nonReentrant
    {
        ERC721Upgradeable.safeTransferFrom(from, to, tokenId, _data);
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
            require(lockDuration == 0, "locks disabled");
        }

        _updatePool();

        // handle tokens with transfer tax
        amount = _transferSupportingFeeOnTransfer(stakedToken, msg.sender, amount);
        require(amount != 0, "zero amount"); // createPosition: amount cannot be null

        // mint NFT position token
        uint256 currentTokenId = _mintNextTokenId(msg.sender);

        // calculate bonuses
        uint256 lockMultiplier = getMultiplierByLockDuration(lockDuration);
        uint256 amountWithMultiplier = amount * (lockMultiplier + 1e4) / 1e4;

        // create position
        _stakingPositions[currentTokenId] = StakingPosition({
            initialLockDuration: lockDuration,
            amount: amount,
            rewardDebt: amountWithMultiplier * (_accRewardsPerShare) / (PRECISION_FACTOR),
            lockDuration: lockDuration,
            startLockTime: _currentBlockTimestamp(),
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
        _requireOnlyOperatorOrOwnerOf(tokenId);
        require(amountToAdd > 0, "0 amount"); // addToPosition: amount cannot be null

        _updatePool();
        address nftOwner = ERC721Upgradeable.ownerOf(tokenId);
        _harvestPosition(tokenId, nftOwner);

        StakingPosition storage position = _stakingPositions[tokenId];

        // we calculate the avg lock time:
        // lock_duration = (remainin_lock_time * staked_amount + amount_to_add * inital_lock_duration) / (staked_amount + amount_to_add)
        uint256 remainingLockTime = _remainingLockTime(position);
        uint256 avgDuration = (remainingLockTime * position.amount + amountToAdd * position.initialLockDuration)
            / (position.amount + amountToAdd);

        position.startLockTime = _currentBlockTimestamp();
        position.lockDuration = avgDuration;

        // lock multiplier stays the same
        position.lockMultiplier = getMultiplierByLockDuration(position.initialLockDuration);

        // handle tokens with transfer tax
        amountToAdd = _transferSupportingFeeOnTransfer(stakedToken, msg.sender, amountToAdd);

        // update position
        position.amount = position.amount + amountToAdd;
        _stakedSupply = _stakedSupply + amountToAdd;
        _updateBoostMultiplierInfoAndRewardDebt(position);

        emit AddToPosition(tokenId, msg.sender, amountToAdd);
    }

    function _remainingLockTime(StakingPosition memory position) internal view returns (uint256) {
        if ((position.startLockTime + position.lockDuration) <= _currentBlockTimestamp()) {
            return 0;
        }
        return (position.startLockTime + position.lockDuration) - _currentBlockTimestamp();
    }

    /**
     * @dev Harvest from a staking position
     *
     * Can only be called by spNFT's owner or approved address
     */
    function harvestPosition(uint256 tokenId) external override nonReentrant {
        _requireOnlyApprovedOrOwnerOf(tokenId);

        _updatePool();
        _harvestPosition(tokenId, ERC721Upgradeable.ownerOf(tokenId));
        _updateBoostMultiplierInfoAndRewardDebt(_stakingPositions[tokenId]);
    }

    /**
     * @dev Harvest from a staking position to "to" address
     *
     * Can only be called by lsNFT's owner or approved address
     * lsNFT's owner must be a contract
     */
    function harvestPositionTo(uint256 tokenId, address to) external override nonReentrant {
        _requireOnlyApprovedOrOwnerOf(tokenId);
        // legacy: require(ERC721.ownerOf(tokenId).isContract(), "FORBIDDEN");

        _updatePool();
        _harvestPosition(tokenId, to);
        _updateBoostMultiplierInfoAndRewardDebt(_stakingPositions[tokenId]);
    }

    /**
     * @dev Harvest from multiple staking positions to "to" address
     *
     * Can only be called by lsNFT's owner or approved address
     */
    function harvestPositionsTo(uint256[] calldata tokenIds, address to) external override nonReentrant {
        _updatePool();

        uint256 length = tokenIds.length;

        for (uint256 i = 0; i < length; ++i) {
            uint256 tokenId = tokenIds[i];
            _requireOnlyApprovedOrOwnerOf(tokenId);
            address tokenOwner = ERC721Upgradeable.ownerOf(tokenId);
            // if sender is the current owner, must also be the harvest dst address
            // if sender is approved, current owner must be a contract
            require(
                (msg.sender == tokenOwner && msg.sender == to), // legacy || tokenOwner.isContract()
                "FORBIDDEN"
            );

            _harvestPosition(tokenId, to);
            _updateBoostMultiplierInfoAndRewardDebt(_stakingPositions[tokenId]);
        }
    }

    /**
     * @dev Withdraw from a staking position
     *
     * Can only be called by lsNFT's owner or approved address
     */
    function withdrawFromPosition(uint256 tokenId, uint256 amountToWithdraw) external nonReentrant {
        _requireOnlyApprovedOrOwnerOf(tokenId);

        _updatePool();
        address nftOwner = ERC721Upgradeable.ownerOf(tokenId);
        _withdrawFromPosition(nftOwner, tokenId, amountToWithdraw);
    }

    /**
     * @dev Renew lock from a staking position
     *
     * Can only be called by lsNFT's owner or approved address
     */
    function renewLockPosition(uint256 tokenId) external nonReentrant {
        _requireOnlyApprovedOrOwnerOf(tokenId);

        _updatePool();
        _lockPosition(tokenId, _stakingPositions[tokenId].lockDuration, false);
    }




    /**
     * @dev Extends a lock position, lockDuration is the new lock duration
     * Lock duration must be greater than existing lock duration
     * Can only be called by lsNFT's owner or approved address
     * 
     * @param tokenId The id of the lsNFT
     * @param lockDuration The new lock duration
     */
    function extendLockPosition(uint256 tokenId, uint256 lockDuration) external nonReentrant {
        _requireOnlyApprovedOrOwnerOf(tokenId);

        _updatePool();
        _lockPosition(tokenId, lockDuration, true);
    }

    /**
     * Withdraw without caring about rewards, EMERGENCY ONLY
     *
     * Can only be called by lsNFT's owner
     */
    function emergencyWithdraw(uint256 tokenId) external override nonReentrant {
        _requireOnlyOwnerOf(tokenId);

        StakingPosition storage position = _stakingPositions[tokenId];

        // position should be unlocked
        require(
            _unlockOperators.contains(msg.sender)
                || (position.startLockTime + position.lockDuration) <= _currentBlockTimestamp() || isUnlocked(),
            "locked"
        );
        // emergencyWithdraw: locked

        uint256 amount = position.amount;

        // update total lp supply
        _stakedSupply = _stakedSupply - amount;
        _stakedSupplyWithMultiplier = _stakedSupplyWithMultiplier - position.amountWithMultiplier;

        // destroy position (ignore boost points)
        _destroyPosition(tokenId);

        emit EmergencyWithdraw(tokenId, amount);
        stakedToken.safeTransfer(msg.sender, amount);
    }

    // internal functions

    /**
     * @dev Returns whether "userAddress" is the owner of "tokenId" lsNFT
     */
    function _isOwnerOf(address userAddress, uint256 tokenId) internal view returns (bool) {
        return userAddress == ERC721Upgradeable.ownerOf(tokenId);
    }

    /**
     * @dev Updates rewards states of this pool to be up-to-date
     */
    function _updatePool() internal {
        uint256 accRewardsPerShare = _accRewardsPerShare;
        uint256 rewardBalance = rewardToken.balanceOf(address(this));
        uint256 lastRewardBalance = _lastRewardBalance;

        // recompute accRewardsPerShare if not up to date
        if (lastRewardBalance == rewardBalance || _stakedSupply == 0) {
            return;
        }

        uint256 accruedReward = rewardBalance - lastRewardBalance;
        _accRewardsPerShare =
            accRewardsPerShare + ((accruedReward * (PRECISION_FACTOR)) / (_stakedSupplyWithMultiplier));

        _lastRewardBalance = rewardBalance;

        emit PoolUpdated(_currentBlockTimestamp(), accRewardsPerShare);
    }

    /**
     * @dev Destroys lsNFT
     *
     * "boostPointsToDeallocate" is set to 0 to ignore boost points handling if called during an emergencyWithdraw
     * Users should still be able to deallocate xGRAIL from the YieldBooster contract
     */
    function _destroyPosition(uint256 tokenId) internal {
        // burn lsNFT
        delete _stakingPositions[tokenId];
        ERC721Upgradeable._burn(tokenId);
    }

    /**
     * @dev Computes new tokenId and mint associated lsNFT to "to" address
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
     */
    function _withdrawFromPosition(address nftOwner, uint256 tokenId, uint256 amountToWithdraw) internal {
        require(amountToWithdraw > 0, "null");
        // withdrawFromPosition: amount cannot be null

        StakingPosition storage position = _stakingPositions[tokenId];
        require(
            _unlockOperators.contains(nftOwner)
                || (position.startLockTime + position.lockDuration) <= _currentBlockTimestamp() || isUnlocked(),
            "locked"
        );
        // withdrawFromPosition: invalid amount
        require(position.amount >= amountToWithdraw, "invalid");

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
        stakedToken.safeTransfer(nftOwner, amountToWithdraw);
    }

    /**
     * @dev updates position's boost multiplier, totalMultiplier, amountWithMultiplier (stakedSupplyWithMultiplier)
     * and rewardDebt without updating lockMultiplier
     */
    function _updateBoostMultiplierInfoAndRewardDebt(StakingPosition storage position) internal {
        // keep the original lock multiplier and recompute current boostPoints multiplier
        uint256 newTotalMultiplier = position.lockMultiplier;
        if (newTotalMultiplier > _maxGlobalMultiplier) newTotalMultiplier = _maxGlobalMultiplier;

        position.totalMultiplier = newTotalMultiplier;
        uint256 amountWithMultiplier = position.amount * (newTotalMultiplier + 1e4) / 1e4;
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
     */
    function _lockPosition(uint256 tokenId, uint256 lockDuration, bool resetInitial) internal {
        require(!isUnlocked(), "locks disabled");

        StakingPosition storage position = _stakingPositions[tokenId];

        // for renew only, check if new lockDuration is at least = to the remaining active duration
        uint256 endTime = position.startLockTime + position.lockDuration;
        uint256 currentBlockTimestamp = _currentBlockTimestamp();
        if (endTime > currentBlockTimestamp) {
            require(lockDuration >= (endTime - currentBlockTimestamp) && lockDuration > 0, "invalid");
        }

        // for extend lock postion we reset the initial lock duration
        // we have to check that the lock duration is greater then the current
        if (resetInitial) {
            require(lockDuration > position.initialLockDuration, "invalid");
            position.initialLockDuration = lockDuration;
        }

        _harvestPosition(tokenId, msg.sender);

        // update position and total lp supply
        position.lockDuration = lockDuration;
        position.lockMultiplier = getMultiplierByLockDuration(lockDuration);
        position.startLockTime = currentBlockTimestamp;
        _updateBoostMultiplierInfoAndRewardDebt(position);

        emit LockPosition(tokenId, lockDuration);
    }

    /**
     * @dev Handle deposits of tokens with transfer tax
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
        uint256 rewardBalance = rewardToken.balanceOf(address(this));

        if (_amount > rewardBalance) {
            _lastRewardBalance = _lastRewardBalance - rewardBalance;
            rewardToken.safeTransfer(_to, rewardBalance);
        } else {
            _lastRewardBalance = _lastRewardBalance - _amount;
            rewardToken.safeTransfer(_to, _amount);
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
            revert("Forbidden: Transfer failed");
        }

        return super._update(to, tokenId, auth);
    }

    /**
     * @dev Utility function to get the current block timestamp
     */
    function _currentBlockTimestamp() internal view virtual returns (uint256) {
        /* solhint-disable not-rely-on-time */
        return block.timestamp;
    }

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
