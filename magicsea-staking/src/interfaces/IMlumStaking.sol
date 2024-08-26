// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/token/ERC721/IERC721.sol";

interface IMlumStaking is IERC721 {
    // Info of each NFT (staked position).
    struct StakingPosition {
        uint256 amount; // How many lp tokens the user has provided
        uint256 amountWithMultiplier; // Amount + lock bonus faked amount (amount + amount*multiplier)
        uint256 startLockTime; // The time at which the user made his deposit
        uint256 initialLockDuration; // lock duration on creation
        uint256 lockDuration; // The lock duration in seconds
        uint256 lockMultiplier; // Active lock multiplier (times 1e2)
        uint256 rewardDebt; // Reward debt
        uint256 totalMultiplier; // lockMultiplier
    }

    error IMlumStaking_TooMuchTokenDecimals();
    error IMlumStaking_ZeroAddress();
    error IMlumStaking_NotOwner();
    error IMlumStaking_MaxLockMultiplierTooHigh();
    error IMlumStaking_LocksDisabled();
    error IMlumStaking_ZeroAmount();
    error IMlumStaking_PositionStillLocked();
    error IMlumStaking_InvalidLockDuration();
    error IMlumStaking_TransferNotAllowed();
    error IMlumStaking_AmountTooHigh();
    error IMlumStaking_SameAddress();

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
    event SetEmergencyUnlock(bool emergencyUnlock);
    event SetMinimumLockDuration(uint256 minimumLockDuration);

    function exists(uint256 tokenId) external view returns (bool);

    function getStakedToken() external view returns (IERC20);

    function getRewardToken() external view returns (IERC20);

    function getMultiplierSettings() external view returns (uint256, uint256, uint256);

    function getLastRewardBalance() external view returns (uint256);

    function lastTokenId() external view returns (uint256);

    function getStakedSupply() external view returns (uint256);

    function getStakedSupplyWithMultiplier() external view returns (uint256);

    function hasDeposits() external view returns (bool);

    function getStakingPosition(uint256 tokenId) external view returns (StakingPosition memory position);

    function pendingRewards(uint256 tokenId) external view returns (uint256);

    function createPosition(uint256 amount, uint256 lockDuration) external;

    function addToPosition(uint256 tokenId, uint256 amountToAdd) external;

    function harvestPosition(uint256 tokenId) external;

    function harvestPositions(uint256[] calldata tokenIds) external;

    function withdrawFromPosition(uint256 tokenId, uint256 amountToWithdraw) external;

    function emergencyWithdraw(uint256 tokenId) external;

    function setMinimumLockDuration(uint256 minimumLockDuration) external;
}
